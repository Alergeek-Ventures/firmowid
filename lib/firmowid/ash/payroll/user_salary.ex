defmodule Firmowid.Ash.Payroll.UserSalary do
  @moduledoc """
  Ash resource wrapping the existing `user_salaries` table.

  Attribute multitenancy via `organization_id`. Supports CRUD plus:

  - `retire` — soft-delete that sets `deleted_at`
  - `create_with_retire` — retires any existing active salary, then creates the new one
  - `get_latest` — returns the single active (non-retired) salary for a user
  - `as_of` — returns salaries that were active on a given date (end-of-month lookup)
  - `salaries_csv` — generic action producing a payroll CSV string for a month/year

  The partial unique index `user_salaries_active_unique_index` ensures only one
  active (non-retired) salary per user per organization.
  """
  use Ash.Resource,
    domain: Firmowid.Ash.Payroll,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias Firmowid.Ash.Core.User
  alias Firmowid.Ash.Resource

  require Resource

  postgres do
    table "user_salaries"
    repo(Firmowid.Repo)
    migrate?(false)
  end

  code_interface do
    define :create
    define :create_with_retire
    define :retire
    define :get_latest, args: [:user_id]
    define :as_of, args: [:date]
    define :salaries_csv, args: [:month, :year]
  end

  actions do
    defaults [:read, :destroy, update: :*]

    create :create do
      accept [:hourly_rate, :user_id]
    end

    update :retire do
      accept []
      change set_attribute(:deleted_at, &Date.utc_today/0)
    end

    create :create_with_retire do
      description "Retires any existing active salary for the user, then creates the new one."
      accept [:hourly_rate, :user_id]
      change Firmowid.Ash.Payroll.Changes.RetireExistingSalary
    end

    read :get_latest do
      description "Returns the active (non-retired) salary for a given user."
      get? true
      prepare build(limit: 1)

      argument :user_id, :uuid do
        allow_nil? false
      end

      prepare fn query, _context ->
        user_id = Ash.Query.get_argument(query, :user_id)
        Ash.Query.do_filter(query, user_id: user_id, deleted_at: [is_nil: true])
      end
    end

    read :as_of do
      description "Returns salaries active on a given date (end-of-month lookup). Optionally filter to a single user."

      argument :date, :date do
        allow_nil? false
      end

      argument :user_id, :uuid

      prepare fn query, _context ->
        date = Ash.Query.get_argument(query, :date)
        as_of_date = Date.end_of_month(date)
        as_of_end_dt = DateTime.new!(as_of_date, ~T[23:59:59], "Etc/UTC")

        query
        |> Ash.Query.do_filter(
          updated_at: [less_than_or_equal: as_of_end_dt],
          or: [
            [deleted_at: [is_nil: true]],
            [deleted_at: [greater_than: as_of_date]]
          ]
        )
        |> Ash.Query.sort(user_id: :asc, deleted_at: :desc_nils_first)
        |> Ash.Query.distinct([:user_id])
        |> then(fn query ->
          case Ash.Query.get_argument(query, :user_id) do
            nil -> query
            uid -> Ash.Query.do_filter(query, user_id: uid)
          end
        end)
      end
    end

    action :salaries_csv, :string do
      description "Generates a payroll CSV for a given month and year. Joins salary-as-of data with hours records."

      argument :month, :integer do
        allow_nil? false
        constraints min: 1, max: 12
      end

      argument :year, :integer do
        allow_nil? false
        constraints min: 1900
      end

      run fn input, context ->
        import Ecto.Query

        %{month: month, year: year} = input.arguments
        as_of_date = Date.new!(year, month, 1)

        latest_salary_as_of_query = salary_as_of_subquery(as_of_date, context.tenant)

        csv =
          from(u in User,
            left_join: us in subquery(latest_salary_as_of_query),
            on: us.user_id == u.id,
            join: hr in Firmowid.Ash.Timetracker.HoursRecord,
            on: hr.user_id == u.id and hr.month == ^month and hr.year == ^year,
            order_by: u.name,
            select: %{
              name: u.name,
              hourly_rate: us.hourly_rate,
              number_of_hours: hr.number_of_hours,
              salary:
                "? * ?"
                |> fragment(us.hourly_rate, hr.number_of_hours)
                |> coalesce(0)
                |> type(:decimal)
                |> selected_as(:salary)
            }
          )
          # TODO: replace raw Ecto with Ash reads when cross-domain joins
          # (User × UserSalary × HoursRecord) are supported in Ash.
          |> Firmowid.Repo.all()
          |> CSV.encode(
            headers: [
              name: "Imie i Nazwisko",
              hourly_rate: "Stawka godzinowa",
              number_of_hours: "Liczba godzin",
              salary: "Wynagrodzenie"
            ]
          )
          |> Enum.join()

        {:ok, csv}
      end
    end
  end

  policies do
    bypass actor_attribute_equals(:role, :admin) do
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if actor_attribute_equals(:role, :admin)
    end

    policy action_type(:action) do
      authorize_if actor_attribute_equals(:role, :admin)
    end
  end

  multitenancy do
    strategy :attribute
    attribute :organization_id
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :hourly_rate, :decimal do
      public? true
      allow_nil? false
      constraints min: 0
    end

    attribute :deleted_at, :date, public?: true

    Resource.firmowid_timestamps()
  end

  relationships do
    belongs_to :user, User do
      allow_nil? false
      attribute_writable? true
    end

    belongs_to :organization, Firmowid.Ash.Core.Organization do
      allow_nil? false
    end
  end

  identities do
    identity :active_user_salary, [:user_id, :organization_id] do
      nils_distinct? false
      where expr(is_nil(deleted_at))
      message "User already has an active salary record"
    end
  end

  # ── Shared raw-Ecto helpers ───────────────────────────────────────────
  #
  # These exist because several cost/reporting queries need to join
  # salary-as-of data with non-Ash tables (User, Session, HoursRecord)
  # in a single SQL query. The Ash `:as_of` read action above handles the
  # pure-Ash path; the subquery below covers the raw-Ecto join path.

  @doc """
  Returns an Ecto subquery selecting `%{user_id, hourly_rate}` for the salary
  that was active at the end of the given month, scoped to `organization_id`.

  Uses `DISTINCT ON (user_id)` ordered by `updated_at DESC` so the most
  recently updated record wins. Soft-deleted records whose `deleted_at`
  predates `end_of_month(date)` are excluded.

  Intended for use as a subquery in raw-Ecto joins — prefer the `:as_of` Ash
  read action when no cross-domain join is needed.
  """
  @spec salary_as_of_subquery(Date.t(), String.t()) :: Ecto.Query.t()
  def salary_as_of_subquery(%Date{} = date, organization_id) do
    import Ecto.Query

    as_of_date = Date.end_of_month(date)
    as_of_end_dt = DateTime.new!(as_of_date, ~T[23:59:59], "Etc/UTC")

    __MODULE__
    |> where([us], us.organization_id == ^organization_id)
    |> where([us], us.updated_at <= ^as_of_end_dt)
    |> where([us], is_nil(us.deleted_at) or us.deleted_at > ^as_of_date)
    |> order_by([us], asc: us.user_id, desc: us.updated_at)
    |> distinct([us], us.user_id)
    |> select([us], %{user_id: us.user_id, hourly_rate: us.hourly_rate})
  end
end
