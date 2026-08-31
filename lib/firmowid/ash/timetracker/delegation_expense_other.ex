defmodule Firmowid.Ash.Timetracker.DelegationExpenseOther do
  @moduledoc "Other expense attached to a delegation."

  use Ash.Resource,
    otp_app: :firmowid,
    domain: Firmowid.Ash.Timetracker,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias Firmowid.Ash.Resource

  require Resource

  postgres do
    table "delegation_expense_other"
    repo Firmowid.Repo
  end

  code_interface do
    define :read, action: :read
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      description "Create another expense for a delegation."
      primary? true
      accept [:delegation_id, :original_filename, :document_number, :expense_amount, :description]
    end

    update :update do
      description "Update another expense while settling a delegation."
      primary? true
      accept [:document_number, :expense_amount, :description]
    end
  end

  policies do
    bypass actor_attribute_equals(:role, :admin) do
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if relates_to_actor_via([:delegation, :user])
    end

    policy action_type([:create, :update, :destroy]) do
      authorize_if expr(delegation.status == :in_progress and delegation.user_id == ^actor(:id))
    end
  end

  multitenancy do
    strategy :attribute
    attribute :organization_id
  end

  attributes do
    uuid_v7_primary_key :id
    attribute :original_filename, :string, allow_nil?: false, public?: true
    attribute :document_number, :string, allow_nil?: false, default: "", public?: true

    attribute :expense_amount, AshMoney.Types.Money,
      allow_nil?: false,
      public?: true,
      default: Money.new(:PLN, 0)

    attribute :description, :string,
      allow_nil?: false,
      default: "",
      constraints: [allow_empty?: true],
      public?: true

    Resource.firmowid_timestamps()
  end

  relationships do
    belongs_to :delegation, Firmowid.Ash.Timetracker.Delegation do
      allow_nil? false
      attribute_writable? true
    end

    belongs_to :organization, Firmowid.Ash.Core.Organization do
      allow_nil? false
    end
  end
end
