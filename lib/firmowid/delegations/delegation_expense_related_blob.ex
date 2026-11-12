defmodule Firmowid.Delegations.DelegationExpenseRelatedBlob do
  @moduledoc "Join resource for additional documents supporting a delegation expense."

  use Ash.Resource,
    otp_app: :firmowid,
    domain: Firmowid.Delegations,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias Firmowid.Checks.SystemActorRole
  alias Firmowid.Delegations.DelegationExpense
  alias Firmowid.Resource

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
    bypass [{SystemActorRole, roles: [:avatar_cleanup]}, action(:read)] do
      authorize_if expr(blob_id == ^actor(:blob_id))
    end

    policy action_type(:read) do
      authorize_if expr(delegation_expense.delegation.member_id == ^actor([:member, :id]))
    end

    # Only the expense's own action links a document, after storing the uploaded file.
    # A link to a file id given directly would expose a file the member cannot read.
    policy action_type(:create) do
      authorize_if accessing_from(DelegationExpense, :related_blobs_join_assoc)
    end

    policy action_type([:create, :destroy]) do
      authorize_if expr(
                     delegation_expense.delegation.status == :in_progress and
                       delegation_expense.delegation.member_id == ^actor([:member, :id])
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
    belongs_to :delegation_expense, DelegationExpense do
      allow_nil? false
      attribute_writable? true
    end

    belongs_to :blob, Firmowid.Blobs.Blob do
      allow_nil? false
      attribute_writable? true
    end
  end

  identities do
    identity :unique_expense_blob, [:delegation_expense_id, :blob_id]
  end
end
