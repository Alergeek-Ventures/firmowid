defmodule Firmowid.Ash.Assistant.Conversation do
  @moduledoc "One canonical assistant transcript per user and organization."
  use Ash.Resource,
    domain: Firmowid.Ash.Assistant,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshOban],
    notifiers: [Firmowid.Ash.Assistant.Notifier]

  alias Firmowid.Ash.Assistant.Changes.StartTurn
  alias Firmowid.Ash.Checks.AtLeastRole

  postgres do
    table "assistant_conversations"
    repo Firmowid.Repo

    references do
      reference :user, on_delete: :delete
      reference :organization, on_delete: :delete
    end
  end

  oban do
    use_tenant_from_record? true

    triggers do
      trigger :respond do
        action :respond
        scheduler_cron false
        queue :assistant
        actor_persister :none
        default_actor %{assistant_worker?: true}
        # A rescued job gets one cleanup attempt, NEVER a second execution.
        max_attempts 2
        timeout to_timeout(minute: 10)
        lock_for_update? false
        worker_module_name Firmowid.Ash.Assistant.Conversation.Worker.Respond
        scheduler_module_name Firmowid.Ash.Assistant.Conversation.Scheduler.Respond
      end
    end
  end

  code_interface do
    define :respond, action: :respond
    define :save_progress, action: :save_progress
    define :read_for_job, action: :read_for_job, get_by: [:id]
  end

  actions do
    defaults [:read]

    read :read_for_job do
      description "Reads a tenant-scoped conversation for its assistant job."
    end

    create :get_or_create do
      description "Creates the actor's conversation or returns the existing one without modifying it."
      accept []
      upsert? true
      upsert_identity :owner
      upsert_fields []
      upsert_condition expr(false)
      return_skipped_upsert? true
      change relate_actor(:user)
    end

    update :send_message do
      description "Appends a user turn and enqueues its durable response at the rendered revision."
      primary? true
      accept []
      require_atomic? false
      argument :text, :string, allow_nil?: false, constraints: [min_length: 1, max_length: 20_000]
      argument :expected_version, :integer, allow_nil?: false
      change {StartTurn, mode: :message}
      change optimistic_lock(:version)
    end

    update :respond_to_plan do
      description "Approves or denies exactly the pending calls at the rendered revision."
      accept []
      require_atomic? false
      argument :decision, :atom, allow_nil?: false, constraints: [one_of: [:approve, :deny]]
      argument :expected_version, :integer, allow_nil?: false
      change {StartTurn, mode: :approval}
      change optimistic_lock(:version)
    end

    action :respond do
      description "Executes one assistant run or marks an interrupted run as failed without replaying it."
      argument :primary_key, :map, allow_nil?: false
      argument :run_id, :uuid, allow_nil?: false
      run Firmowid.Ash.Assistant.Actions.Respond
    end

    update :save_progress do
      description "Persists completed assistant/tool messages and lifecycle state from its job."
      accept [:transcript, :status, :error, :approvals]
      require_atomic? false
      change optimistic_lock(:version)
    end
  end

  policies do
    # Only the assistant's storage/lifecycle actions accept AshOban's context.
    # This context is deliberately NOT passed to any financial tool.
    policy action([:read_for_job, :respond, :save_progress]) do
      authorize_if AshOban.Checks.AshObanInteraction
    end

    policy action(:get_or_create) do
      authorize_if relating_to_actor(:user)
    end

    policy action([:read, :send_message, :respond_to_plan]) do
      authorize_if relates_to_actor_via(:user)
    end

    policy action([:get_or_create, :read, :send_message, :respond_to_plan]) do
      authorize_if {AtLeastRole, role: :employee}
    end
  end

  multitenancy do
    strategy :attribute
    attribute :organization_id
  end

  attributes do
    uuid_v7_primary_key :id
    attribute :transcript, {:array, :map}, allow_nil?: false, default: []

    attribute :status, :atom,
      allow_nil?: false,
      default: :idle,
      constraints: [one_of: [:idle, :running, :awaiting_approval, :failed]]

    attribute :version, :integer, allow_nil?: false, default: 1
    attribute :error, :string
    attribute :run_id, :uuid
    attribute :approvals, :map, allow_nil?: false, default: %{}
    timestamps()
  end

  relationships do
    belongs_to :user, Firmowid.Ash.Core.User, allow_nil?: false
    belongs_to :organization, Firmowid.Ash.Core.Organization, allow_nil?: false
  end

  identities do
    identity :owner, [:user_id, :organization_id]
  end
end
