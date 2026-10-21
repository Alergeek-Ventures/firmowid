# credo:disable-for-this-file AshCredo.Check.Design.MissingPrimaryAction
# credo:disable-for-this-file AshCredo.Check.Warning.AuthorizeFalse
defmodule Firmowid.Ash.Delegations.Delegation do
  @moduledoc "A company-funded business trip submitted by an employee."

  use Ash.Resource,
    otp_app: :firmowid,
    domain: Firmowid.Ash.Delegations,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshStateMachine]

  alias Firmowid.Ash.Checks.ActorRole
  alias Firmowid.Ash.Core.Member
  alias Firmowid.Ash.Delegations.Actions.NotifyAdminsAboutDelegation
  alias Firmowid.Ash.Delegations.Actions.NotifyEmployeeAboutApprovedDelegation
  alias Firmowid.Ash.Delegations.Changes.AssignReference
  alias Firmowid.Ash.Delegations.Changes.CreateSignedCommandBlob
  alias Firmowid.Ash.Delegations.Changes.PrepareDelegationCompletion
  alias Firmowid.Ash.Delegations.Signals
  alias Firmowid.Ash.Delegations.Validations.HasDateChangeReason
  alias Firmowid.Ash.Delegations.Validations.HasExpenses
  alias Firmowid.Ash.Resource

  require Resource

  postgres do
    table "delegations"
    repo Firmowid.Repo

    references do
      reference :member, on_delete: :delete
    end
  end

  state_machine do
    state_attribute :status
    initial_states [:pending]
    default_initial_state :pending

    transitions do
      transition :approve, from: :pending, to: :in_progress
      transition :complete, from: :in_progress, to: :complete
    end
  end

  actions do
    defaults [:read]

    read :by_reference do
      description "Find a delegation by its public reference."
      get? true

      argument :reference, :string, allow_nil?: false
      filter expr(reference == ^arg(:reference))
    end

    read :list_for_member do
      description "Delegations submitted by a given organization member."
      argument :member_id, :uuid, allow_nil?: false
      prepare build(filter: expr(member_id == ^arg(:member_id)), sort: [inserted_at: :desc])
    end

    create :create do
      description "Submit a new business trip delegation."
      primary? true

      accept [
        :title,
        :billing_month,
        :destination,
        :transport_types,
        :purpose,
        :expected_cost,
        :start_date,
        :end_date
      ]

      change set_attribute(:member_id, actor([:member, :id]))
      change set_attribute(:reference, "pending")
      change AssignReference

      validate compare(:end_date, greater_than_or_equal_to: :start_date),
        message: "nie może być wcześniejsza niż data wyjazdu"

      validate compare(:expected_cost, greater_than_or_equal_to: Money.new(:PLN, 0)),
        message: "musi być większa lub równa 0 PLN"

      emit Signals, :delegation_submitted, fields: [delegation_id: :id]
    end

    update :approve do
      description "Approve a pending delegation and mark it as in progress."
      primary? true
      require_atomic? false
      accept [:advance_amount, :signed_command_filename]

      argument :upload_path, :string, allow_nil?: false

      argument :content_type, :string,
        allow_nil?: false,
        constraints: [match: ~r/^application\/pdf$/]

      change CreateSignedCommandBlob
      validate present(:signed_command_filename)

      validate compare(:advance_amount, greater_than_or_equal_to: Money.new(:PLN, 0)),
        message: "musi być większa lub równa 0 PLN"

      change transition_state(:in_progress)

      emit Signals, :delegation_approved, fields: [delegation_id: :id]
    end

    update :prepare_command do
      description "Set the advance amount used in a pending business trip order."
      require_atomic? false
      accept [:advance_amount]
      validate attribute_equals(:status, :pending)

      validate compare(:advance_amount, greater_than_or_equal_to: Money.new(:PLN, 0)),
        message: "musi być większa lub równa 0 PLN"
    end

    update :update_billing_month do
      description "Set the billing month for a pending business trip delegation."
      require_atomic? false
      accept [:billing_month]
      validate attribute_equals(:status, :pending)
    end

    update :complete do
      description "Mark an in-progress delegation as complete."
      require_atomic? false
      accept [:date_change_reason]

      argument :expenses, {:array, :map}, allow_nil?: false, default: []

      change PrepareDelegationCompletion

      change manage_relationship(:expenses,
               type: :direct_control,
               on_match: {:update, :complete},
               on_no_match: :error,
               on_missing: :ignore,
               # The parent completion action authorizes the employee and owns this transaction.
               authorize?: false
             )

      validate {HasExpenses, []}
      validate {HasDateChangeReason, []}

      change transition_state(:complete)
    end

    update :detect_dates do
      description "Store delegation dates detected from its evidence documents."
      require_atomic? false
      accept [:detected_start_date, :detected_end_date]
    end

    action :notify_admins do
      description "Emails organization admins about a newly submitted delegation."
      argument :signal, Signals.DelegationSubmitted, allow_nil?: false
      run NotifyAdminsAboutDelegation
    end

    action :notify_employee do
      description "Emails the employee that their delegation was approved."
      argument :signal, Signals.DelegationApproved, allow_nil?: false
      run NotifyEmployeeAboutApprovedDelegation
    end
  end

  policies do
    bypass {ActorRole, role: :admin} do
      authorize_if always()
    end

    bypass {Firmowid.Ash.Checks.SystemActorRole, roles: [:leave_notifier]} do
      authorize_if action_type(:read)
    end

    policy action(:create) do
      authorize_if actor_present()
    end

    policy action(:notify_admins) do
      authorize_if signal_in(Signals, :delegation_submitted)
    end

    policy action(:notify_employee) do
      authorize_if signal_in(Signals, :delegation_approved)
    end

    policy action_type(:read) do
      authorize_if expr(member_id == ^actor([:member, :id]))
    end

    policy action(:approve) do
      forbid_if always()
    end

    policy action(:prepare_command) do
      forbid_if always()
    end

    policy action(:complete) do
      authorize_if expr(status == :in_progress and member_id == ^actor([:member, :id]))
    end

    policy action(:detect_dates) do
      authorize_if expr(status == :in_progress and member_id == ^actor([:member, :id]))
    end
  end

  multitenancy do
    strategy :attribute
    attribute :organization_id
  end

  attributes do
    uuid_v7_primary_key :id
    attribute :reference, :string, allow_nil?: false, public?: true
    attribute :title, :string, allow_nil?: false, public?: true
    attribute :billing_month, :date, allow_nil?: false, public?: true
    attribute :destination, :string, allow_nil?: false, public?: true

    attribute :transport_types, {:array, :atom},
      allow_nil?: false,
      public?: true,
      constraints: [
        min_length: 1,
        items: [one_of: [:railway, :airplane, :bus, :public_transport, :other]]
      ]

    attribute :purpose, :string, allow_nil?: false, public?: true
    attribute :expected_cost, AshMoney.Types.Money, allow_nil?: false, public?: true

    attribute :advance_amount, AshMoney.Types.Money,
      allow_nil?: false,
      default: Money.new(:PLN, 0),
      public?: true

    attribute :signed_command_filename, :string, public?: true
    attribute :start_date, :date, allow_nil?: false, public?: true
    attribute :end_date, :date, allow_nil?: false, public?: true
    attribute :detected_start_date, :date, public?: true
    attribute :detected_end_date, :date, public?: true
    attribute :date_change_reason, :string, public?: true

    attribute :status, :atom do
      allow_nil? false
      default :pending
      public? true
      constraints one_of: [:pending, :in_progress, :complete]
    end

    Resource.firmowid_timestamps()
  end

  relationships do
    belongs_to :member, Member do
      allow_nil? false
      attribute_writable? true
    end

    belongs_to :organization, Firmowid.Ash.Core.Organization do
      allow_nil? false
    end

    belongs_to :signed_command_blob, Firmowid.Ash.Blobs.Blob do
      description "Employer-signed business trip order."
      allow_nil? true
      attribute_writable? true
    end

    has_many :expenses, Firmowid.Ash.Delegations.DelegationExpense
  end

  signals_in do
    from Signals do
      on :delegation_submitted, :notify_admins, delivery: {AshOban.Signals, queue: :notification_emails, max_attempts: 3}

      on :delegation_approved, :notify_employee, delivery: {AshOban.Signals, queue: :notification_emails, max_attempts: 3}
    end
  end

  aggregates do
    sum :expenses_total, :expenses, :expense_amount
  end

  identities do
    identity :unique_reference, [:organization_id, :reference]
  end
end
