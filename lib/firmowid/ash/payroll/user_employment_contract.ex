defmodule Firmowid.Ash.Payroll.UserEmploymentContract do
  @moduledoc "Ash resource representing a user's employment contract."
  use Ash.Resource,
    otp_app: :firmowid,
    domain: Firmowid.Ash.Payroll,
    authorizers: [Ash.Policy.Authorizer],
    data_layer: AshPostgres.DataLayer,
    extensions: [AshStateMachine, AshOban],
    primary_read_warning?: false

  alias AshOban.Checks.AshObanInteraction
  alias Firmowid.Ash.Blobs
  alias Firmowid.Ash.Checks.SystemActorRole
  alias Firmowid.Ash.Payroll.Changes.UpdateUserPosition
  alias Firmowid.Ash.Payroll.UserEmploymentContract.Worker.ActivateSigned
  alias Firmowid.Ash.Payroll.UserEmploymentContract.Worker.TerminateExpired
  alias Firmowid.Ash.Resource

  require Logger
  require Resource

  postgres do
    table "user_employment_contracts"
    repo Firmowid.Repo
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
        where expr(status == :signed and starts_at <= fragment("CURRENT_DATE"))
        scheduler_cron "0 1 * * *"
        max_attempts 3
        queue :default

        worker_module_name ActivateSigned
        scheduler_module_name Firmowid.Ash.Payroll.UserEmploymentContract.Scheduler.ActivateSigned
      end

      trigger :terminate_expired_contracts do
        action :terminate
        read_action :read_global
        where expr(status == :active)
        scheduler_cron "0 1 * * *"
        max_attempts 3
        queue :contract_lifecycle

        worker_module_name TerminateExpired

        scheduler_module_name Firmowid.Ash.Payroll.UserEmploymentContract.Scheduler.TerminateExpired
      end
    end
  end

  code_interface do
    define :destroy, action: :destroy
    define :update_employment_contract, action: :update
    define :submit_signed, action: :submit_signed
    define :activate, action: :activate
    define :read_global, action: :read_global

    define :load_pending_contract,
      action: :load_pending_contract,
      args: [:user_id],
      get?: true,
      not_found_error?: false

    define :load_latest_contract,
      action: :load_latest_contract,
      args: [:user_id],
      get?: true,
      not_found_error?: false
  end

  actions do
    defaults [:destroy]

    read :get_by_id do
      description "Returns an employment contract given its id."
      argument :id, :uuid
      primary? true
      get? true

      prepare build(filter: expr(id == ^arg(:id))) do
        where present(:id)
      end
    end

    read :read do
      description "Returns all employment contracts given user_id."

      argument :user_id, :uuid
      argument :month, :integer
      argument :year, :integer

      prepare build(filter: expr(user_id == ^arg(:user_id))) do
        where present(:user_id)
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
      description "Returns pending_signature contract for a user or nil."
      argument :user_id, :uuid, allow_nil?: false
      get? true

      prepare build(filter: expr(user_id == ^arg(:user_id) and status == :pending_signature))
    end

    read :load_latest_contract do
      description "Returns most recent contract for a user."
      argument :user_id, :uuid, allow_nil?: false
      get? true

      prepare build(
                filter: expr(user_id == ^arg(:user_id)),
                sort: [starts_at: :desc],
                limit: 1
              )
    end

    create :create do
      description "Create an employment contract record for a user."
      primary? true

      accept [
        :starts_at,
        :salary,
        :user_id,
        :blob_id,
        :contract_type,
        :position,
        :status,
        :signed_at
      ]

      argument :user_salary, :map

      change fn changeset, _context ->
        salary = Ash.Changeset.get_attribute(changeset, :salary)
        user_id = Ash.Changeset.get_attribute(changeset, :user_id)
        starts_at = Ash.Changeset.get_attribute(changeset, :starts_at)

        Ash.Changeset.set_argument(changeset, :user_salary, %{
          hourly_rate: Money.to_decimal(salary),
          user_id: user_id,
          starts_at: starts_at
        })
      end

      change manage_relationship(:user_salary, type: :create)

      change MaybeActivateContract

      # Schedule email notification to the employee if the contract is pending signature. The email will be sent at 9:00 AM Warsaw time on the signed_at date (or today if signed_at is nil).
      change after_transaction(fn
               _changeset, {:ok, contract}, _context ->
                 if contract.status == :pending_signature do
                   signed_at = contract.signed_at || Date.utc_today()

                   warsaw_time = DateTime.new!(signed_at, ~T[09:00:00], "Europe/Warsaw")
                   utc_time = DateTime.shift_zone!(warsaw_time, "Etc/UTC")

                   scheduled_at =
                     if DateTime.after?(utc_time, DateTime.utc_now()) do
                       utc_time
                     end

                   EmploymentContractEmailWorker.enqueue(
                     contract.id,
                     contract.organization_id,
                     scheduled_at
                   )

                   {:ok, contract}
                 else
                   {:ok, contract}
                 end

               _changeset, {:error, reason}, _context ->
                 Logger.warning("Failed to enqueue employment contract email notification reason=#{inspect(reason)}")

                 {:error, reason}
             end)
    end

    update :update do
      description "Update employment contract details."
      primary? true
      accept [:contract_type, :status, :signed_at]
    end

    update :submit_signed do
      description "Employee submits signed contract, replacing the original blob."
      accept []
      require_atomic? false

      argument :upload_path, :string, allow_nil?: false
      argument :upload_filename, :string, allow_nil?: true

      change transition_state(:signed)

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

      change after_transaction(fn
               _changeset, {:ok, contract}, _context ->
                 EmploymentContractEmailWorker.enqueue_admin_notification(
                   contract.id,
                   contract.organization_id
                 )

                 {:ok, contract}

               _changeset, {:error, reason}, _context ->
                 {:error, reason}
             end)
    end

    update :activate do
      description "Activate a signed contract (scheduled job)."
      accept []
      require_atomic? false

      change transition_state(:active)
    end
  end

  policies do
    policy action_type(:create) do
      authorize_if {SystemActorRole, roles: [:document_blob_processor]}
      forbid_if always()
    end

    policy action_type(:read) do
      authorize_if actor_attribute_equals(:role, :admin)
      authorize_if expr(user_id == ^actor(:id))
      authorize_if {SystemActorRole, roles: [:document_blob_processor]}
    end

    policy action(:update) do
      authorize_if actor_attribute_equals(:role, :admin)
    end

    policy action(:submit_signed) do
      authorize_if expr(user_id == ^actor(:id) and status == :pending_signature)
    end

    policy action(:activate) do
      authorize_if {AshObanInteraction, []}
      authorize_if {SystemActorRole, roles: [:document_blob_processor]}
      authorize_if expr(user_id == ^actor(:id))
      authorize_if actor_attribute_equals(:role, :admin)
      forbid_if always()
    end

    policy action(:read_global) do
      authorize_if {AshObanInteraction, []}
      forbid_if always()
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
    belongs_to :user, Firmowid.Ash.Core.User do
      allow_nil? false
      attribute_writable? true
    end

    belongs_to :organization, Firmowid.Ash.Core.Organization do
      allow_nil? false
    end

    belongs_to :blob, Firmowid.Ash.Blobs.Blob do
      allow_nil? false
      attribute_writable? true
    end

    has_one :user_salary, Firmowid.Ash.Payroll.UserSalary do
      destination_attribute :employment_contract_id
    end
  end

  identities do
    identity :unique_contract_per_user_org, [:user_id, :organization_id, :starts_at] do
      message "User already has an employment contract with the same start date"
    end

    identity :unique_blob, [:blob_id] do
      message "Blob is already associated with another employment contract"
    end
  end
end
