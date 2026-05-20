defmodule Firmowid.Ash.Assistant.Session do
  @moduledoc """
  Persistent state for a universal assistant conversation.

  Sessions are intentionally decoupled from any single page so the same backend
  flow can later power a floating assistant available across the application.
  """

  use Ash.Resource,
    domain: Firmowid.Ash.Assistant,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshStateMachine],
    primary_read_warning?: false

  alias Firmowid.Ash.Assistant.PendingMatch
  alias Firmowid.Ash.Assistant.Prompts.InvoiceMatching, as: InvoiceMatchingPrompt
  alias Firmowid.Ash.Checks.AtLeastRole
  alias Firmowid.Ash.Resource

  require Resource

  postgres do
    table "assistant_sessions"
    repo Firmowid.Repo
  end

  state_machine do
    state_attribute :status
    initial_states [:active]
    default_initial_state :active

    transitions do
      transition :claim_processing, from: :active, to: :processing
      transition :complete_turn, from: :processing, to: :active
      transition :propose_match, from: [:active, :processing], to: :waiting_confirmation
      transition :sync_pending_turn, from: :waiting_confirmation, to: :waiting_confirmation
      transition :reject_match, from: :waiting_confirmation, to: :active
      transition :accept_match, from: :waiting_confirmation, to: :active
      transition :fail_session, from: :processing, to: :errored

      transition :close,
        from: [:active, :processing, :waiting_confirmation, :errored],
        to: :closed
    end
  end

  code_interface do
    define :by_id, args: [:id], action: :by_id
    define :read, action: :read
    define :start, args: [:entry_context], action: :start_invoice_matching
    define :claim_processing, action: :claim_processing
    define :complete_turn, args: [:messages], action: :complete_turn
    define :propose_match, args: [:messages, :pending_match], action: :propose_match
    define :sync_pending_turn, args: [:messages], action: :sync_pending_turn
    define :reject_match, args: [:messages], action: :reject_match
    define :accept_match, args: [:messages], action: :accept_match
    define :fail_session, args: [:last_error], action: :fail_session
    define :close, action: :close
  end

  actions do
    defaults []

    read :read do
      description "List assistant sessions ordered by most recently updated."
      primary? true
      prepare build(sort: [updated_at: :desc])
    end

    read :by_id do
      description "Fetch an assistant session by ID."
      get_by [:id]
    end

    create :start_invoice_matching do
      description "Start a new invoice-matching assistant session."
      accept [:entry_context]

      change relate_actor(:user)
      change set_attribute(:assistant_type, :invoice_matching)
      change set_attribute(:status, :active)

      change fn changeset, _context ->
        entry_context = Ash.Changeset.get_attribute(changeset, :entry_context) || %{}

        changeset
        |> Ash.Changeset.change_attribute(
          :system_prompt,
          InvoiceMatchingPrompt.system_prompt(entry_context)
        )
        |> Ash.Changeset.change_attribute(:messages, [
          %{"role" => "assistant", "content" => InvoiceMatchingPrompt.intro_message()}
        ])
        |> Ash.Changeset.change_attribute(
          :title,
          Map.get(entry_context, "title") || Map.get(entry_context, :title)
        )
      end
    end

    update :claim_processing do
      description "Claim a session for processing and switch it to the processing state."
      accept []
      change optimistic_lock(:lock_version)
      change transition_state(:processing)
    end

    update :complete_turn do
      description "Complete a processed turn and return the session to the active state."
      primary? true
      accept [:messages]
      require_atomic? false

      change optimistic_lock(:lock_version)
      change transition_state(:active)
      change set_attribute(:pending_match, nil)
      change set_attribute(:last_error, nil)
    end

    update :propose_match do
      description "Store a proposed invoice match and wait for user confirmation."
      accept [:messages, :pending_match]

      change optimistic_lock(:lock_version)
      change transition_state(:waiting_confirmation)
      change set_attribute(:last_error, nil)
    end

    update :sync_pending_turn do
      description "Update messages while keeping the session in waiting-confirmation state."
      accept [:messages]

      change optimistic_lock(:lock_version)
      change transition_state(:waiting_confirmation)
      change set_attribute(:last_error, nil)
    end

    update :reject_match do
      description "Reject the pending match and return the session to the active state."
      accept [:messages]
      require_atomic? false

      change optimistic_lock(:lock_version)
      change transition_state(:active)
      change set_attribute(:pending_match, nil)
      change set_attribute(:last_error, nil)
    end

    update :accept_match do
      description "Accept the pending match and return the session to the active state."
      accept [:messages]
      require_atomic? false

      change optimistic_lock(:lock_version)
      change transition_state(:active)
      change set_attribute(:pending_match, nil)
      change set_attribute(:last_error, nil)
    end

    update :fail_session do
      description "Mark a session as errored and store the last error details."
      accept [:last_error]
      require_atomic? false

      change optimistic_lock(:lock_version)
      change transition_state(:errored)
      change set_attribute(:pending_match, nil)
    end

    update :close do
      description "Close an assistant session and clear transient matching state."
      accept []
      require_atomic? false

      change optimistic_lock(:lock_version)
      change transition_state(:closed)
      change set_attribute(:pending_match, nil)
      change set_attribute(:last_error, nil)
    end
  end

  policies do
    bypass actor_attribute_equals(:role, :admin) do
      authorize_if always()
    end

    policy [action_type(:read), {AtLeastRole, role: :invoicing}] do
      authorize_if relates_to_actor_via(:user)
    end

    policy [action_type(:create), {AtLeastRole, role: :invoicing}] do
      authorize_if relating_to_actor(:user)
    end

    policy [action_type([:update, :destroy]), {AtLeastRole, role: :invoicing}] do
      authorize_if relates_to_actor_via(:user)
    end
  end

  multitenancy do
    strategy :attribute
    attribute :organization_id
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :assistant_type, :atom,
      constraints: [one_of: [:invoice_matching]],
      allow_nil?: false,
      default: :invoice_matching,
      public?: true

    attribute :status, :atom,
      constraints: [one_of: [:active, :processing, :waiting_confirmation, :closed, :errored]],
      allow_nil?: false,
      default: :active,
      public?: true

    attribute :lock_version, :integer,
      allow_nil?: false,
      default: 1,
      writable?: false,
      public?: true

    attribute :title, :string, public?: true
    attribute :system_prompt, :string, allow_nil?: false
    attribute :entry_context, :map, allow_nil?: false, default: %{}
    attribute :messages, {:array, :map}, allow_nil?: false, default: []
    attribute :pending_match, PendingMatch
    attribute :last_error, :string

    Resource.firmowid_timestamps()
  end

  relationships do
    belongs_to :organization, Firmowid.Ash.Core.Organization do
      allow_nil? false
    end

    belongs_to :user, Firmowid.Ash.Core.User do
      allow_nil? false
      attribute_writable? true
    end
  end
end
