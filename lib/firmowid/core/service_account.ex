# Created only through its company key (`ApiKey.create_for_company` manages the relationship).
# credo:disable-for-this-file AshCredo.Check.Design.MissingCodeInterface
defmodule Firmowid.Core.ServiceAccount do
  @moduledoc """
  The organization itself acting through a company API key: an actor with a member role but
  no person behind it, so the key keeps working when the admin who created it leaves.

  Policies see its role like a member's (see `Firmowid.Checks.ActorRole`). It is created with
  its company key and destroyed when the key is revoked (see `Firmowid.Core.ApiKey`).
  """
  use Ash.Resource,
    domain: Firmowid.Core,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias Firmowid.Checks.ActorRole
  alias Firmowid.Core.Organization
  alias Firmowid.Core.UserRole
  alias Firmowid.Resource

  require Resource

  postgres do
    table "service_accounts"
    repo Firmowid.Repo

    references do
      reference :organization, on_delete: :delete
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      description "Create the account of a new company key, with its role."
      primary? true
      accept [:role]
    end
  end

  policies do
    # Signing a company key in loads its account.
    bypass [AshAuthentication.Checks.AshAuthenticationInteraction, action_type(:read)] do
      authorize_if always()
    end

    policy AshAuthentication.Checks.UsingApiKey do
      forbid_if always()
    end

    policy always() do
      authorize_if {ActorRole, role: :admin}
    end
  end

  multitenancy do
    strategy :attribute
    attribute :organization_id
    # A key is signed in before its organization is known.
    global? true
  end

  attributes do
    uuid_primary_key :id

    attribute :role, :atom do
      allow_nil? false
      public? true
      constraints one_of: UserRole.roles()
      description "The member role whose permissions the account has."
    end

    Resource.firmowid_timestamps()
  end

  relationships do
    belongs_to :organization, Organization do
      allow_nil? false
    end
  end
end
