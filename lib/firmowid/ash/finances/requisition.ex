defmodule Firmowid.Ash.Finances.Requisition do
  @moduledoc """
  GoCardless bank connection requisition.

  Tracks the lifecycle of a bank connection request.
  """
  use Ash.Resource,
    domain: Firmowid.Ash.Finances,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshStateMachine, AshOban],
    notifiers: [Ash.Notifier.PubSub]

  alias AshOban.Checks.AshObanInteraction
  alias Firmowid.Ash.Finances.Changes.DeleteRemoteRequisition
  alias Firmowid.Ash.Resource

  require Resource

  postgres do
    table "requisitions"
    repo Firmowid.Repo
  end

  state_machine do
    state_attribute :status
    initial_states [:pending]
    default_initial_state :pending

    transitions do
      transition :accept, from: :pending, to: :accepted
      transition :reject, from: [:pending, :accepted], to: :rejected
      transition :auto_reject, from: :pending, to: :rejected
      transition :expire, from: :accepted, to: :expired
    end
  end

  oban do
    use_tenant_from_record? true

    triggers do
      trigger :check_status do
        action :check_status
        read_action :read_global
        where expr(status == :pending)
        scheduler_cron "* * * * *"
        max_attempts 7
        queue :requisition_checks

        worker_module_name Firmowid.Ash.Finances.Requisition.Worker.CheckStatus
        scheduler_module_name Firmowid.Ash.Finances.Requisition.Scheduler.CheckStatus
      end

      trigger :auto_reject do
        action :auto_reject
        read_action :read_global
        where expr(status == :pending and inserted_at < ago(1, "hour"))
        scheduler_cron "0 * * * *"
        max_attempts 3
        queue :requisition_checks

        worker_module_name Firmowid.Ash.Finances.Requisition.Worker.AutoReject
        scheduler_module_name Firmowid.Ash.Finances.Requisition.Scheduler.AutoReject
      end

      trigger :cleanup_orphan do
        action :cleanup_orphan
        read_action :read_global
        where expr(inserted_at < ago(1, "hour") and not exists(bank_accounts, true))
        scheduler_cron "0 * * * *"
        max_attempts 3
        queue :requisition_checks

        worker_module_name Firmowid.Ash.Finances.Requisition.Worker.CleanupOrphan
        scheduler_module_name Firmowid.Ash.Finances.Requisition.Scheduler.CleanupOrphan
      end

      trigger :delete_remote do
        action :delete_remote
        read_action :read_global
        where expr(status in [:rejected, :expired] and is_nil(remote_deleted_at))
        scheduler_cron "0 * * * *"
        max_attempts 5
        queue :requisition_checks

        worker_module_name Firmowid.Ash.Finances.Requisition.Worker.DeleteRemote
        scheduler_module_name Firmowid.Ash.Finances.Requisition.Scheduler.DeleteRemote
      end
    end
  end

  code_interface do
    define :accept
    define :reject
    define :expire
  end

  actions do
    defaults [:read, :destroy]

    read :read_global do
      description "Unscoped read for AshOban schedulers — reads across all organizations."
      multitenancy :allow_global
      pagination keyset?: true
    end

    # Generic action: calls GoCardless API, persists record, returns redirect link.
    action :create_requisition, :string do
      description "Create a GoCardless requisition and return its redirect URL."
      argument :institution_id, :string, allow_nil?: false
      argument :max_transaction_days, :integer, allow_nil?: false
      argument :redirect_url, :string, allow_nil?: false

      run Firmowid.Ash.Finances.Actions.CreateRequisition
    end

    # Internal create action used by CreateRequisition generic action.
    # Protected by policy — never exposed through domain.
    create :persist do
      description "Persist a requisition record created by the external requisition flow."
      accept [:id]
    end

    # Polls GoCardless API and transitions based on status.
    # Handles full lifecycle: pending → accepted/rejected.
    update :check_status do
      require_atomic? false
      description "AshOban trigger action — polls GoCardless API and transitions state."
      primary? true
      change Firmowid.Ash.Finances.Changes.CheckRequisitionStatus
    end

    # Accepts a linked requisition — creates bank accounts and increments billing.
    # Called by CheckRequisitionStatus when GoCardless returns "LN".
    # Not exposed through domain.
    update :accept do
      description "Accept a requisition and create the linked bank accounts."
      require_atomic? false
      change transition_state(:accepted)
      change Firmowid.Ash.Finances.Changes.CreateBankAccounts
    end

    # Rejects a requisition — decrements billing (if was accepted) and queues cleanup.
    # Called by CheckRequisitionStatus when GoCardless returns "RJ".
    # Not exposed through domain.
    update :reject do
      description "Reject a requisition that cannot proceed."
      require_atomic? false
      change transition_state(:rejected)
    end

    # Scheduled trigger: rejects stale pending requisitions.
    # Not exposed through domain — internal only.
    update :auto_reject do
      require_atomic? false
      description "Scheduled trigger — rejects requisitions pending for >1 hour."
      change transition_state(:rejected)
    end

    # Scheduled trigger: deletes orphaned requisitions (no bank accounts).
    # Not exposed through domain — internal only.
    destroy :cleanup_orphan do
      require_atomic? false
      description "Scheduled trigger — deletes requisitions with no bank accounts after 1 hour."
      change DeleteRemoteRequisition
    end

    # Called from BankAccount sync when GoCardless returns invalid/expired requisition.
    # Not exposed through domain — internal only.
    update :expire do
      require_atomic? false
      description "Expires a requisition when GoCardless reports it as invalid during sync."
      change transition_state(:expired)
    end

    # Async remote cleanup — queued by other actions, never scheduled.
    # Not exposed through domain — internal only.
    update :delete_remote do
      require_atomic? false
      description "Deletes remote requisition + agreement from GoCardless."
      change DeleteRemoteRequisition
    end
  end

  policies do
    bypass AshObanInteraction do
      authorize_if always()
    end

    bypass actor_attribute_equals(:role, :admin) do
      authorize_if always()
    end

    bypass {Firmowid.Ash.Checks.SystemActorRole, roles: [:bank_sync]} do
      authorize_if action(:expire)
    end

    policy action(:read_global) do
      forbid_if always()
    end

    # System actors don't manage bank connections
    policy Firmowid.Ash.Checks.IsSystemActor do
      forbid_if always()
    end

    policy action(:create_requisition) do
      authorize_if actor_attribute_equals(:role, :admin)
    end

    # Internal lifecycle actions are executed by background automation and
    # delegated transitions where actor metadata may be absent.
    policy action([:check_status, :accept, :reject]) do
      authorize_if always()
    end

    # :invoicing and :accountant: read-only
    policy [action(:read), {Firmowid.Ash.Checks.AtLeastRole, role: :invoicing}] do
      authorize_if always()
    end

    # Internal actions — should never be called directly
    policy action([:persist, :auto_reject, :cleanup_orphan, :delete_remote]) do
      forbid_if always()
    end

    policy action(:expire) do
      forbid_if always()
    end
  end

  pub_sub do
    module FirmowidWeb.Core.Endpoint
    prefix "requisition"

    publish :accept, ["linked", :_tenant]
    publish :reject, ["rejected", :_tenant]
    publish :expire, ["expired", :_tenant]
  end

  multitenancy do
    strategy :attribute
    attribute :organization_id
  end

  attributes do
    # GoCardless assigns the UUID directly — not a UUIDv7.
    attribute :id, :uuid, primary_key?: true, writable?: true, public?: true, allow_nil?: false

    # Managed by AshStateMachine — maps to the existing `requisition_status` PG enum.
    attribute :status, :atom,
      constraints: [one_of: [:pending, :accepted, :rejected, :expired]],
      default: :pending,
      allow_nil?: false,
      public?: true

    attribute :remote_deleted_at, :utc_datetime, public?: true

    Resource.firmowid_timestamps()
  end

  relationships do
    belongs_to :organization, Firmowid.Ash.Core.Organization do
      allow_nil? false
    end

    has_many :bank_accounts, Firmowid.Ash.Finances.BankAccount do
      destination_attribute :requisition_id
    end
  end

  identities do
    identity :unique_id, [:id]
  end
end
