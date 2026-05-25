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
    authorizers: [Ash.Policy.Authorizer],
    primary_read_warning?: false

  alias Firmowid.Ash.Core.User
  alias Firmowid.Ash.Resource

  require Resource

  postgres do
    table "user_salaries"
    repo Firmowid.Repo
  end

  actions do
    defaults [:destroy]

    create :create do
      description "Create a salary record for a user."
      primary? true
      accept [:hourly_rate, :user_id]
    end

    read :read do
      description """
      Returns all salaries for all users.
      Can be filter by active_at (date) to return salaries active on a specific date and by user_id to return salaries for a specific user.
      """

      primary? true

      argument :user_id, :uuid
      argument :active_at, :date

      prepare build(sort: [starts_at: :desc])

      prepare build(filter: expr(user == ^arg(:user_id))) do
        where present(:user_id)
      end

      prepare build(
                filter:
                  expr(
                    starts_at <= ^arg(:active_at) and
                      (is_nil(ends_at) or
                         ends_at > ^arg(:active_at))
                  )
              ) do
        where present(:active_at)
      end
    end

    action :bulk_create_salaries, {:array, :struct} do
      description """
      Admin-only. Creates new salaries for multiple employees in a single atomic transaction.
      Uses Ash.bulk_create for proper transaction management.
      """

      argument :entries, {:array, :map}, allow_nil?: false

      run fn input, context ->
        result =
          Ash.bulk_create(
            input.arguments.entries,
            __MODULE__,
            :create,
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

    attribute :starts_at, :utc_datetime do
      public? true
      allow_nil? false
      default &Date.utc_today/0
    end

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

  calculations do
    calculate :ends_at, :date, Firmowid.Ash.Payroll.Calculations.EndsAt
  end

  identities do
    identity :unique_starts_at_per_user, [:user_id, :organization_id, :starts_at] do
      nils_distinct? false
      message "User already has salary record with the same start date"
    end
  end
end
