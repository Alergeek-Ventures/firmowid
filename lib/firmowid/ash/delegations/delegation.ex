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

  alias Firmowid.Ash.Core.User
  alias Firmowid.Ash.Delegations.Changes.PrepareDelegationCompletion
  alias Firmowid.Ash.Delegations.Changes.CreateSignedCommandBlob
  alias Firmowid.Ash.Delegations.Validations.HasDateChangeReason
  alias Firmowid.Ash.Delegations.Validations.HasExpenses
  alias Firmowid.Ash.Delegations.Workers.DelegationEmailWorker
  alias Firmowid.Ash.Resource

  require Resource

  postgres do
    table "delegations"
    repo Firmowid.Repo
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

    read :list_for_user do
      description "Delegations submitted by a given employee."
      argument :user_id, :uuid, allow_nil?: false
      prepare build(filter: expr(user_id == ^arg(:user_id)), sort: [inserted_at: :desc])
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

      change set_attribute(:user_id, actor(:id))
      change set_attribute(:reference, "pending")

      validate compare(:end_date, greater_than_or_equal_to: :start_date),
        message: "nie może być wcześniejsza niż data wyjazdu"

      validate compare(:expected_cost, greater_than_or_equal_to: Money.new(:PLN, 0)),
        message: "musi być większa lub równa 0 PLN"

      change after_transaction(fn
               _changeset, {:ok, delegation}, _context ->
                 DelegationEmailWorker.enqueue(delegation.id, delegation.organization_id)
                 {:ok, delegation}

               _changeset, {:error, reason}, _context ->
                 {:error, reason}
             end)
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

      change after_transaction(fn
               _changeset, {:ok, delegation}, _context ->
                 DelegationEmailWorker.enqueue_approval(delegation.id, delegation.organization_id)
                 {:ok, delegation}

               _changeset, {:error, reason}, _context ->
                 {:error, reason}
             end)
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
  end

  policies do
    bypass actor_attribute_equals(:role, :admin) do
      authorize_if always()
    end

    bypass {Firmowid.Ash.Checks.SystemActorRole, roles: [:leave_notifier]} do
      authorize_if action_type(:read)
    end

    policy action(:create) do
      authorize_if actor_present()
    end

    policy action_type(:read) do
      authorize_if expr(user_id == ^actor(:id))
    end

    policy action(:approve) do
      forbid_if always()
    end

    policy action(:prepare_command) do
      forbid_if always()
    end

    policy action(:complete) do
      authorize_if expr(status == :in_progress and user_id == ^actor(:id))
    end

    policy action(:detect_dates) do
      authorize_if expr(status == :in_progress and user_id == ^actor(:id))
    end
  end

  multitenancy do
    strategy :attribute
    attribute :organization_id
  end

  attributes do
    uuid_v7_primary_key :id
    attribute :reference, :string, allow_nil?: false, default: "", public?: true
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
    belongs_to :user, User do
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

  aggregates do
    sum :expenses_total, :expenses, :expense_amount
  end

  identities do
    identity :unique_reference, [:reference]
  end
end
