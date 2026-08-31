# credo:disable-for-this-file AshCredo.Check.Design.MissingPrimaryAction
defmodule Firmowid.Ash.Delegations.Delegation do
  @moduledoc "A company-funded business trip submitted by an employee."

  use Ash.Resource,
    otp_app: :firmowid,
    domain: Firmowid.Ash.Delegations,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshStateMachine]

  alias Firmowid.Ash.Core.User
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
        :advance_payment_amount,
        :start_date,
        :end_date
      ]

      change set_attribute(:user_id, actor(:id))

      validate compare(:end_date, greater_than_or_equal_to: :start_date),
        message: "nie może być wcześniejsza niż data wyjazdu"

      validate compare(:advance_payment_amount, greater_than_or_equal_to: Money.new(:PLN, 0)),
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
      accept []
      change transition_state(:in_progress)

      change after_transaction(fn
               _changeset, {:ok, delegation}, _context ->
                 DelegationEmailWorker.enqueue_approval(delegation.id, delegation.organization_id)
                 {:ok, delegation}

               _changeset, {:error, reason}, _context ->
                 {:error, reason}
             end)
    end

    update :complete do
      description "Mark an in-progress delegation as complete."
      require_atomic? false
      accept []
      change transition_state(:complete)
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

    policy action([:approve, :complete]) do
      authorize_if action(:approve)
      authorize_if expr(status == :in_progress and user_id == ^actor(:id))
    end
  end

  multitenancy do
    strategy :attribute
    attribute :organization_id
  end

  attributes do
    uuid_v7_primary_key :id
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
    attribute :advance_payment_amount, AshMoney.Types.Money, allow_nil?: false, public?: true
    attribute :start_date, :date, allow_nil?: false, public?: true
    attribute :end_date, :date, allow_nil?: false, public?: true

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

    has_many :transport_expenses, Firmowid.Ash.Delegations.DelegationExpenseTransport
    has_many :accommodation_expenses, Firmowid.Ash.Delegations.DelegationExpenseAccommodation
    has_many :other_expenses, Firmowid.Ash.Delegations.DelegationExpenseOther
  end
end
