defmodule Firmowid.Ash.Payroll.UserSalary do
  @moduledoc """
  Ash resource wrapping the existing `user_salaries` table.

  Attribute multitenancy via `organization_id`. Supports CRUD plus:

  - `bulk_create_salaries` — admin-only action creating new salaries for multiple employees atomically

  Each salary belongs to an organization member.
  """
  use Ash.Resource,
    domain: Firmowid.Ash.Payroll,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias Firmowid.Ash.Checks.ActorRole
  alias Firmowid.Ash.Checks.SystemActorRole
  alias Firmowid.Ash.Resource

  require Resource

  postgres do
    table "user_salaries"
    repo Firmowid.Repo

    references do
      reference :member, on_delete: :delete
    end
  end

  code_interface do
    define :read, action: :read
    define :list, action: :list
    define :destroy, action: :destroy
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      description "Create a salary record for an organization member."
      primary? true
      accept [:hourly_rate, :member_id, :starts_at]
      change {Firmowid.Ash.Payroll.Changes.SkipUnchangedRate, []}
    end

    read :list do
      description """
      Returns all salaries for all users.
      Can be filter by active_at (date) to return salaries active on a specific date and by user_id to return salaries for a specific user.
      """

      argument :user_id, :uuid
      argument :active_at, :date

      prepare build(sort: [starts_at: :desc])

      prepare build(filter: expr(member.user_id == ^arg(:user_id))) do
        where present(:user_id)
      end

      prepare build(
                filter:
                  expr(
                    type(starts_at, :date) <= ^arg(:active_at) and
                      (is_nil(ends_at) or
                         type(ends_at, :date) > ^arg(:active_at))
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
          Firmowid.Ash.Payroll.create_salary(
            input.arguments.entries,
            actor: context.actor,
            tenant: context.tenant,
            bulk_options: [
              transaction: :all,
              return_records?: true,
              return_errors?: true,
              stop_on_error?: true
            ]
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
    bypass [
      {SystemActorRole, roles: [:organization_cleanup]},
      action([:read, :list, :destroy])
    ] do
      authorize_if expr(not is_nil(^actor(:org_id)) and organization_id == ^actor(:org_id))
    end

    bypass {ActorRole, role: :admin} do
      authorize_if always()
    end

    bypass action_type(:read) do
      authorize_if {SystemActorRole, roles: [:document_blob_processor]}
    end

    policy action_type(:create) do
      authorize_if {SystemActorRole, roles: [:document_blob_processor]}
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
      default &DateTime.utc_now/0
    end

    Resource.firmowid_timestamps()
  end

  relationships do
    belongs_to :member, Firmowid.Ash.Core.Member do
      allow_nil? false
      attribute_writable? true
    end

    belongs_to :organization, Firmowid.Ash.Core.Organization do
      allow_nil? false
    end

    belongs_to :employment_contract, Firmowid.Ash.Payroll.UserEmploymentContract do
      # dla istniejących rekordów bez kontraktu
      allow_nil? true
      attribute_writable? true
    end
  end

  calculations do
    calculate :ends_at, :date, Firmowid.Ash.Payroll.Calculations.EndsAt

    calculate :monthly_payout, :map, Firmowid.Ash.Payroll.UserSalary.Calculations.MonthlyPayout do
      description """
      Calculates one month's net pay from its declarations and sourced payroll
      facts, without inventing missing history.
      """

      argument :month, :date, allow_nil?: false
    end

    calculate :payout_estimates,
              {:array, Firmowid.Ash.Payroll.UserSalary.Types.PayoutEstimate},
              Firmowid.Ash.Payroll.UserSalary.Calculations.PayoutEstimates do
      description "A complete current tax profile selects one estimate. Otherwise returns legacy hypothetical variants. No annual limits, progressive PIT or PPK are tracked."
      argument :month, :date, allow_nil?: false
    end

    calculate :monthly_amount,
              AshMoney.Types.Money,
              Firmowid.Ash.Payroll.UserSalary.Calculations.MonthlyAmount do
      description "Expected salary using this rate and the employee's rounded-up session hours for a month."
      argument :month, :date, allow_nil?: false
    end
  end

  identities do
    identity :unique_starts_at_per_member, [:member_id, :organization_id, :starts_at] do
      nils_distinct? false
      message "Member already has salary record with the same start date"
    end
  end
end
