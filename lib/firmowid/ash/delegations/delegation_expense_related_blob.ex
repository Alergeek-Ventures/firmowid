defmodule Firmowid.Ash.Delegations.DelegationExpenseRelatedBlob do
  @moduledoc "Join resource for additional documents supporting a delegation expense."

  use Ash.Resource,
    otp_app: :firmowid,
    domain: Firmowid.Ash.Delegations,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias Firmowid.Ash.Resource

  require Resource

  postgres do
    table "delegation_expense_related_blobs"
    repo Firmowid.Repo

    references do
      reference :delegation_expense, on_delete: :delete
    end
  end

  code_interface do
    define :read, action: :read
    define :create, action: :create
    define :destroy, action: :destroy
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      description "Associate a supporting document with a delegation expense."
      primary? true
      accept [:delegation_expense_id, :blob_id]
    end
  end

  policies do
    bypass actor_attribute_equals(:role, :admin) do
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if relates_to_actor_via([:delegation_expense, :delegation, :user])
    end

    policy action_type([:create, :destroy]) do
      authorize_if expr(
                     delegation_expense.delegation.status == :in_progress and
                       delegation_expense.delegation.user_id == ^actor(:id)
                   )
    end
  end

  multitenancy do
    strategy :attribute
    attribute :organization_id
  end

  attributes do
    uuid_v7_primary_key :id
    attribute :organization_id, :uuid, allow_nil?: false
    Resource.firmowid_timestamps()
  end

  relationships do
    belongs_to :delegation_expense, Firmowid.Ash.Delegations.DelegationExpense do
      allow_nil? false
      attribute_writable? true
    end

    belongs_to :blob, Firmowid.Ash.Blobs.Blob do
      allow_nil? false
      attribute_writable? true
    end
  end

  identities do
    identity :unique_expense_blob, [:delegation_expense_id, :blob_id]
  end
end
