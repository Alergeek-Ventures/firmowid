defmodule Firmowid.Assistant.Conversation do
  @moduledoc "Assistant sessions, context and lifecycle owned by a user within an organization."
  use Ash.Resource,
    domain: Firmowid.Assistant,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshOban, AshStateMachine],
    notifiers: [Ash.Notifier.PubSub]

  alias Firmowid.Assistant
  alias Firmowid.Assistant.Changes.AppendMessage
  alias Firmowid.Assistant.Changes.RecordApproval
  alias Firmowid.Assistant.Changes.SetSubject
  alias Firmowid.Assistant.Transcript
  alias Firmowid.Checks.AtLeastRole

  postgres do
    table "assistant_conversations"
    repo Firmowid.Repo

    references do
      reference :user, on_delete: :delete
      reference :organization, on_delete: :delete
    end

    custom_indexes do
      index [:organization_id, :user_id, :inserted_at, :id]
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
        read_metadata fn record -> %{run_id: record.run_id} end
        where expr(status == :running)
        worker_read_action :read_for_job
        on_error :fail
        on_error_fails_job? true
        max_attempts 1
        timeout to_timeout(minute: 10)
        lock_for_update? false
        worker_module_name Firmowid.Assistant.Conversation.Worker.Respond
        scheduler_module_name Firmowid.Assistant.Conversation.Scheduler.Respond
      end
    end
  end

  state_machine do
    state_attribute :status
    initial_states [:idle, :running]
    default_initial_state :idle

    transitions do
      transition :send_message, from: [:idle, :failed], to: :running
      transition :respond_to_plan, from: :awaiting_approval, to: :running
      transition :append_response, from: :running, to: :running
      transition :await_approval, from: :running, to: :awaiting_approval
      transition :complete, from: :running, to: :idle
      transition :fail, from: :running, to: :failed
    end
  end

  code_interface do
    define :respond
    define :append_response
    define :await_approval
    define :complete
    define :fail
    define :read_for_job, get_by: [:id]
  end

  actions do
    defaults [:read]

    read :list do
      description "Lists the actor's conversations, newest first."
      prepare build(sort: [inserted_at: :desc, id: :desc])

      pagination do
        required? false
        keyset? true
        default_limit 20
        max_page_size 100
      end
    end

    read :read_for_job do
      description "Reads only the running conversation belonging to this job's run."

      filter expr(
               status == :running and
                 run_id == ^context([:ash_oban, :job, :args, "metadata", "run_id"])
             )
    end

    create :start do
      description "Starts an independent conversation and enqueues its first response."
      primary? true
      accept []
      argument :text, :string, allow_nil?: false, constraints: [min_length: 1, max_length: 20_000]
      change relate_actor(:user)
      change transition_state(:running)
      change AppendMessage, only_when_valid?: true
      change set_attribute(:run_id, &Ash.UUID.generate/0)
      change run_oban_trigger(:respond)
    end

    create :for_subject do
      description "Starts an idle conversation with an authorized subject, awaiting the user's question."
      accept []

      argument :subject_type, :atom,
        allow_nil?: false,
        constraints: [one_of: [:transaction, :sales_invoice, :cost_invoice, :employee, :project]]

      argument :subject_id, :uuid, allow_nil?: false
      change relate_actor(:user)
      change SetSubject, only_when_valid?: true
    end

    update :send_message do
      description "Appends a user turn and enqueues its durable response at the rendered revision."
      primary? true
      accept []
      require_atomic? false
      argument :text, :string, allow_nil?: false, constraints: [min_length: 1, max_length: 20_000]
      argument :expected_version, :integer, allow_nil?: false
      # Check the rendered version before optimistic_lock increments the row version.
      validate compare(:expected_version, is_equal: :version), message: "stale_conversation"
      change transition_state(:running)
      change AppendMessage, only_when_valid?: true
      change set_attribute(:approvals, %{})
      change set_attribute(:error, nil)
      change set_attribute(:run_id, &Ash.UUID.generate/0)
      change optimistic_lock(:version)
      change run_oban_trigger(:respond)
    end

    update :respond_to_plan do
      description "Approves or denies exactly the pending calls at the rendered revision."
      accept []
      require_atomic? false
      argument :decision, :atom, allow_nil?: false, constraints: [one_of: [:approve, :deny]]
      argument :expected_version, :integer, allow_nil?: false
      validate compare(:expected_version, is_equal: :version), message: "stale_conversation"
      change transition_state(:running)
      change RecordApproval, only_when_valid?: true
      change set_attribute(:error, nil)
      change set_attribute(:run_id, &Ash.UUID.generate/0)
      change optimistic_lock(:version)
      change run_oban_trigger(:respond)
    end

    update :respond do
      description "Executes one assistant run without replaying financial operations."
      transaction? false
      require_atomic? false
      accept []
      manual Firmowid.Assistant.Actions.Respond
    end

    update :append_response do
      description "Stores one completed assistant or tool message in the running session."
      accept []
      require_atomic? false
      argument :role, :atom, allow_nil?: false, constraints: [one_of: [:assistant, :tool]]
      argument :parts, {:array, :map}, allow_nil?: false, constraints: [min_length: 1]
      change transition_state(:running)

      change fn changeset, _context ->
               Ash.Changeset.manage_relationship(
                 changeset,
                 :messages,
                 %{
                   role: Ash.Changeset.get_argument(changeset, :role),
                   parts: Ash.Changeset.get_argument(changeset, :parts)
                 },
                 type: :create
               )
             end,
             only_when_valid?: true

      change optimistic_lock(:version)
    end

    update :await_approval do
      description "Pauses the running turn for a version-bound user decision."
      accept []
      require_atomic? false
      change transition_state(:awaiting_approval)
      change set_attribute(:approvals, %{})
      change optimistic_lock(:version)
    end

    update :complete do
      description "Completes the running turn."
      accept []
      require_atomic? false
      change transition_state(:idle)
      change set_attribute(:approvals, %{})
      change optimistic_lock(:version)
    end

    update :fail do
      description "Closes unanswered calls as unknown without replaying financial operations."
      accept []
      require_atomic? false
      argument :reason, :string, allow_nil?: false, default: "response_failed"
      change transition_state(:failed)
      change set_attribute(:error, arg(:reason))
      change set_attribute(:approvals, %{})

      change fn changeset, context ->
               messages =
                 Assistant.list_messages!(%{conversation_id: changeset.data.id},
                   actor: context.actor,
                   tenant: context.tenant,
                   context: context.source_context,
                   page: false
                 )

               Ash.Changeset.manage_relationship(
                 changeset,
                 :messages,
                 Transcript.unknown_results(messages),
                 type: :create
               )
             end,
             only_when_valid?: true

      change optimistic_lock(:version)
    end
  end

  policies do
    # Only the assistant's storage/lifecycle actions accept AshOban's context.
    # This context is deliberately NOT passed to any financial tool.
    policy action([:read_for_job, :respond, :append_response, :await_approval, :complete, :fail]) do
      authorize_if AshOban.Checks.AshObanInteraction
    end

    policy action([:start, :for_subject]) do
      authorize_if relating_to_actor(:user)
    end

    policy action([:read, :list, :send_message, :respond_to_plan]) do
      authorize_if relates_to_actor_via(:user)
    end

    policy action([:start, :for_subject, :read, :list, :send_message, :respond_to_plan]) do
      authorize_if {AtLeastRole, role: :employee}
    end
  end

  pub_sub do
    module Phoenix.PubSub
    name Firmowid.PubSub
    prefix "assistant:conversation"
    transform fn notification -> {:assistant_updated, notification.data.id} end
    publish_all :create, [:id]
    publish_all :update, [:id], except: [:respond]
  end

  multitenancy do
    strategy :attribute
    attribute :organization_id
  end

  attributes do
    uuid_v7_primary_key :id
    attribute :subject, :map
    attribute :title, :string

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
    belongs_to :user, Firmowid.Core.User, allow_nil?: false
    belongs_to :organization, Firmowid.Core.Organization, allow_nil?: false
    has_many :messages, Firmowid.Assistant.Message, sort: [id: :asc]
  end
end
