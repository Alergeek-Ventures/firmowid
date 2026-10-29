defmodule Firmowid.Payroll.UserEmploymentContract do
  @moduledoc "Ash resource representing a user's employment contract."
  use Ash.Resource,
    otp_app: :firmowid,
    domain: Firmowid.Payroll,
    authorizers: [Ash.Policy.Authorizer],
    data_layer: AshPostgres.DataLayer,
    extensions: [AshStateMachine, AshOban]

  alias AshOban.Checks.AshObanInteraction
  alias Firmowid.Blobs
  alias Firmowid.Checks.ActorRole
  alias Firmowid.Checks.SystemActorRole
  alias Firmowid.Core.Member
  alias Firmowid.Payroll.Actions.NotifyAdminsAboutSignedContract
  alias Firmowid.Payroll.Changes.MaybeActivateContract
  alias Firmowid.Payroll.Changes.SyncUserBankAccount
  alias Firmowid.Payroll.Signals
  alias Firmowid.Payroll.UserEmploymentContract.Worker.ActivateSigned
  alias Firmowid.Payroll.Workers.EmploymentContractEmailWorker
  alias Firmowid.Resource

  require Resource

  @contract_details_fields [
    :starts_at,
    :contract_type,
    :position,
    :status,
    :signed_at,
    :payout_day,
    :payout_month_offset
  ]

  postgres do
    table "user_employment_contracts"
    repo Firmowid.Repo

    references do
      reference :member, on_delete: :delete
    end
  end

  state_machine do
    state_attribute :status
    initial_states [:pending_signature]
    default_initial_state :pending_signature

    transitions do
      transition :submit_signed, from: :pending_signature, to: :signed
      transition :activate, from: :signed, to: :active
    end
  end

  oban do
    use_tenant_from_record? true

    triggers do
      trigger :activate_signed_contracts do
        action :activate
        read_action :read_global
        where expr(status == :signed and starts_at <= today())
        scheduler_cron "0 3 * * *"
        max_attempts 3
        queue :default

        worker_module_name ActivateSigned
        scheduler_module_name Firmowid.Payroll.UserEmploymentContract.Scheduler.ActivateSigned
      end
    end
  end

  code_interface do
    define :read, action: :read
    define :list, action: :list
    define :destroy, action: :destroy
    define :update_employment_contract, action: :update
    define :submit_signed, action: :submit_signed
    define :activate, action: :activate
    define :read_global, action: :read_global
    define :notify_admins, args: [:signal]

    define :load_pending_contract,
      action: :load_pending_contract,
      args: [:member_id],
      get?: true,
      not_found_error?: false

    define :load_current_contract,
      action: :load_current_contract,
      args: [:member_id],
      get?: true,
      not_found_error?: false
  end

  actions do
    defaults [:read, :destroy]

    read :get_by_id do
      description "Returns an employment contract given its id."
      argument :id, :uuid
      get? true

      prepare build(filter: expr(id == ^arg(:id))) do
        where present(:id)
      end
    end

    read :list do
      description "Returns all employment contracts given member_id."

      argument :member_id, :uuid
      argument :month, :integer
      argument :year, :integer

      prepare build(filter: expr(member_id == ^arg(:member_id))) do
        where present(:member_id)
      end

      prepare build(filter: expr(fragment("extract(month from ?) = ?", starts_at, ^arg(:month)))) do
        where present(:month)
      end

      prepare build(filter: expr(fragment("extract(year from ?) = ?", starts_at, ^arg(:year)))) do
        where present(:year)
      end
    end

    read :read_global do
      description "Unscoped read for AshOban schedulers — reads across all organizations."
      multitenancy :allow_global
      pagination keyset?: true
    end

    read :load_pending_contract do
      description "Returns pending_signature contract for a member or nil."
      argument :member_id, :uuid, allow_nil?: false
      get? true

      prepare build(filter: expr(member_id == ^arg(:member_id) and status == :pending_signature))
    end

    read :load_current_contract do
      description """
      Returns the contract currently in effect for a member, or nil.
      """

      argument :member_id, :uuid, allow_nil?: false
      get? true

      prepare build(
                filter:
                  expr(
                    member_id == ^arg(:member_id) and
                      status in [:pending_signature, :signed, :active] and
                      starts_at <= today()
                  ),
                sort: [starts_at: :desc],
                limit: 1
              )
    end

    create :create do
      description "Create an employment contract record for a member."
      primary? true

      accept [:salary, :member_id, :blob_id, :hourly_rate_confirmed | @contract_details_fields]

      argument :user_salary, :map
      argument :bank_account_number, :string

      change fn changeset, _context ->
        salary = Ash.Changeset.get_attribute(changeset, :salary)
        member_id = Ash.Changeset.get_attribute(changeset, :member_id)
        starts_at = Ash.Changeset.get_attribute(changeset, :starts_at)

        Ash.Changeset.set_argument(changeset, :user_salary, %{
          hourly_rate: Money.to_decimal(salary),
          member_id: member_id,
          starts_at: starts_at
        })
      end

      change manage_relationship(:user_salary, type: :create)

      change MaybeActivateContract
      change SyncUserBankAccount

      # Schedule email notification to the employee if the contract is pending signature. The email will be sent at 9:00 AM Warsaw time on the signed_at date (or today if signed_at is nil).
      change after_action(fn _changeset, contract, _context ->
               if contract.status == :pending_signature do
                 signed_at = contract.signed_at || Date.utc_today()

                 warsaw_time = DateTime.new!(signed_at, ~T[09:00:00], "Europe/Warsaw")
                 utc_time = DateTime.shift_zone!(warsaw_time, "Etc/UTC")

                 scheduled_at =
                   if DateTime.after?(utc_time, DateTime.utc_now()) do
                     utc_time
                   end

                 with {:ok, _job} <-
                        EmploymentContractEmailWorker.enqueue(
                          contract.id,
                          contract.organization_id,
                          scheduled_at
                        ),
                      do: {:ok, contract}
               else
                 {:ok, contract}
               end
             end)
    end

    update :update do
      description "Update employment contract details."
      primary? true

      accept @contract_details_fields

      require_atomic? false

      change MaybeActivateContract
    end

    update :submit_signed do
      description "Employee submits signed contract, replacing the original blob."
      accept []
      require_atomic? false

      argument :upload_path, :string, allow_nil?: false
      argument :upload_filename, :string, allow_nil?: true

      change transition_state(:signed)

      # Replace the blob with the uploaded signed contract
      change fn changeset, context ->
        upload_path = Ash.Changeset.get_argument(changeset, :upload_path)

        upload_filename =
          Ash.Changeset.get_argument(changeset, :upload_filename) || "umowa.pdf"

        case Blobs.create_or_reuse_blob(
               upload_path,
               "application/pdf",
               upload_filename,
               tenant: context.tenant,
               actor: context.actor
             ) do
          {:ok, blob} ->
            Ash.Changeset.force_change_attribute(changeset, :blob_id, blob.id)

          {:error, error} ->
            Ash.Changeset.add_error(changeset, error)
        end
      end

      change MaybeActivateContract

      emit Signals, :employment_contract_signed, fields: [contract_id: :id]
    end

    update :activate do
      description "Activate a signed contract (scheduled job)."
      accept []
      require_atomic? false

      change transition_state(:active)
    end

    action :notify_admins do
      description "Emails organization admins that an employee submitted a signed contract."
      argument :signal, Signals.EmploymentContractSigned, allow_nil?: false
      run NotifyAdminsAboutSignedContract
    end
  end

  policies do
    bypass [{SystemActorRole, roles: [:avatar_cleanup]}, action(:read)] do
      authorize_if expr(blob_id == ^actor(:blob_id))
    end

    bypass [
      {SystemActorRole, roles: [:organization_cleanup]},
      action([:list, :destroy])
    ] do
      authorize_if expr(not is_nil(^actor(:org_id)) and organization_id == ^actor(:org_id))
    end

    policy action_type(:create) do
      authorize_if {SystemActorRole, roles: [:document_blob_processor]}
      forbid_if always()
    end

    policy action_type(:read) do
      authorize_if {ActorRole, role: :admin}
      authorize_if expr(member_id == ^actor([:member, :id]))

      authorize_if {SystemActorRole, roles: [:document_blob_processor, :employment_contract_notifier]}
    end

    policy action(:update) do
      authorize_if {ActorRole, role: :admin}
    end

    policy action(:submit_signed) do
      authorize_if expr(member_id == ^actor([:member, :id]) and status == :pending_signature)
    end

    policy action(:activate) do
      authorize_if {AshObanInteraction, []}
      authorize_if {SystemActorRole, roles: [:document_blob_processor]}
      authorize_if expr(member_id == ^actor([:member, :id]))
      authorize_if {ActorRole, role: :admin}
      forbid_if always()
    end

    policy action(:read_global) do
      authorize_if {AshObanInteraction, []}
      forbid_if always()
    end

    policy action(:notify_admins) do
      authorize_if signal_in(Signals, :employment_contract_signed)
    end
  end

  multitenancy do
    strategy :attribute
    attribute :organization_id
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :salary, AshMoney.Types.Money, allow_nil?: false
    attribute :starts_at, :date, allow_nil?: false
    attribute :signed_at, :date, allow_nil?: true
    attribute :hourly_rate_confirmed, :boolean
    attribute :payout_day, :integer, constraints: [min: 1, max: 31]
    attribute :payout_month_offset, :integer, constraints: [min: 0, max: 1]

    attribute :contract_type, :atom,
      constraints: [one_of: [:uop, :b2b, :uz, :uod]],
      allow_nil?: true

    attribute :position, :string, allow_nil?: true

    attribute :status, :atom,
      constraints: [one_of: [:pending_signature, :signed, :active]],
      default: :pending_signature,
      allow_nil?: false

    Resource.firmowid_timestamps()
  end

  relationships do
    belongs_to :member, Member do
      allow_nil? false
      attribute_writable? true
    end

    belongs_to :organization, Firmowid.Core.Organization do
      allow_nil? false
    end

    belongs_to :blob, Firmowid.Blobs.Blob do
      allow_nil? false
      attribute_writable? true
    end

    has_one :user_salary, Firmowid.Payroll.UserSalary do
      destination_attribute :employment_contract_id
    end
  end

  signals_in do
    from Signals do
      on :employment_contract_signed, :notify_admins, delivery: {AshOban.Signals, queue: :default, max_attempts: 3}
    end
  end

  identities do
    identity :unique_contract_per_member_org, [:member_id, :organization_id, :starts_at] do
      message "User already has an employment contract with the same start date"
    end

    identity :unique_blob, [:blob_id] do
      message "Blob is already associated with another employment contract"
    end
  end
end
