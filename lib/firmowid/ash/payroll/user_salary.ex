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
    repo Firmowid.Repo
    identity_wheres_to_sql active_user_salary: "deleted_at IS NULL"
  end

  code_interface do
    define :create
    define :create_with_retire
    define :retire
    define :get_latest, args: [:user_id]
    define :as_of, args: [:date]
    define :bulk_update_salaries, args: [:entries]
  end

  actions do
    defaults [:read, :destroy]

    update :update do
      description "Update the hourly rate for an existing salary record."
      primary? true
      accept [:hourly_rate]
    end

    create :create do
      description "Create a salary record for a user."
      accept [:hourly_rate, :user_id]
    end

    update :retire do
      description "Retire a salary record by setting its deleted date."
      accept []
      change set_attribute(:deleted_at, &Date.utc_today/0)
    end

    create :create_with_retire do
      description "Retires any existing active salary for the user, then creates the new one."
      primary? true
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

    action :bulk_update_salaries, {:array, :struct} do
      description """
      Admin-only. Creates new salaries (retiring existing ones) for multiple
      employees in a single atomic transaction. Uses Ash.bulk_create for
      proper transaction management.
      """

      argument :entries, {:array, :map}, allow_nil?: false

      run fn input, context ->
        result =
          Ash.bulk_create(
            input.arguments.entries,
            __MODULE__,
            :create_with_retire,
            actor: context.actor,
            tenant: context.tenant,
            transaction: :all,
            return_records?: true,
            return_errors?: true,
            stop_on_error?: true
          )

        case result do
          %Ash.BulkResult{status: :success} ->
            {:ok, result.records}

          %Ash.BulkResult{errors: errors} ->
            {:error, List.first(errors)}
        end
      end
    end
  end

  policies do
    bypass actor_attribute_equals(:role, :admin) do
      authorize_if always()
    end

    # System actors have no access to payroll data
    policy Firmowid.Ash.Checks.IsSystemActor do
      forbid_if always()
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
end
