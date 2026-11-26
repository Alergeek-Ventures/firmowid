# The primary read serves relationship loads and the revocation of a person's keys.
# credo:disable-for-this-file AshCredo.Check.Design.MissingCodeInterface
defmodule Firmowid.Core.ApiKey do
  @moduledoc """
  A key a program, such as an online store or a script, uses to call the API of an
  organization without anyone signing in. It works only in the organization it was created in.

  - A personal key (`firmowid_…`) acts as the member who created it, with their role at the time
    of the request. Leaving the organization, a password change and deleting the account revoke
    it (see `Firmowid.Core.User.Changes.RevokeAuthentication`).
  - A company key (`firmowid_org_…`) acts as its own `Firmowid.Core.ServiceAccount`, with the role
    an admin chose, and does not depend on any person.

  Only the hash is stored: the key itself is shown once, in the `plaintext_api_key` metadata of
  the created record (see `Changes.GenerateKey`). Deleting a key revokes it.
  """
  use Ash.Resource,
    domain: Firmowid.Core,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias Firmowid.Checks.ActorRole
  alias Firmowid.Checks.AtLeastRole
  alias Firmowid.Core.ApiKey.Changes.DestroyServiceAccount
  alias Firmowid.Core.ApiKey.Changes.GenerateKey
  alias Firmowid.Core.ApiKey.Changes.SetExpiry
  alias Firmowid.Core.Organization
  alias Firmowid.Core.ServiceAccount
  alias Firmowid.Core.User
  alias Firmowid.Resource

  require Ash.Query
  require Resource

  @expires_on_description "The last day the key works; nil for a key that works until revoked."

  postgres do
    table "api_keys"
    repo Firmowid.Repo

    references do
      reference :organization, on_delete: :delete
      reference :user, on_delete: :delete
      reference :service_account, on_delete: :delete
    end

    check_constraints do
      check_constraint :user_id, "personal_or_company_key",
        check: "(user_id IS NULL) <> (service_account_id IS NULL)",
        message: "a key belongs either to a person or to the company"
    end
  end

  actions do
    defaults [:read]

    read :list do
      description "List the keys the actor sees in the organization, newest first."
      prepare build(sort: [inserted_at: :desc], load: [:service_account])
    end

    read :sign_in do
      description "Find the valid key with this secret, of an organization with a billing plan."
      get? true
      argument :api_key, :string, allow_nil?: false, sensitive?: true
      filter expr(valid and organization.billing_plan != :no_plan)

      prepare fn query, _context ->
        hash = query |> Ash.Query.get_argument(:api_key) |> GenerateKey.hash()
        Ash.Query.filter(query, api_key_hash == ^hash)
      end
    end

    create :create do
      primary? true
      description "Create a personal key acting as the actor in the organization."
      accept [:name]
      argument :expires_on, :date, description: @expires_on_description

      change relate_actor(:user)
      change SetExpiry
      change {GenerateKey, prefix: "firmowid"}
    end

    create :create_for_company do
      description "Create a company key acting with the role, independent of any person."
      accept [:name]
      argument :expires_on, :date, description: @expires_on_description

      argument :role, :atom do
        allow_nil? false
        constraints one_of: Firmowid.Core.UserRole.roles()
      end

      change manage_relationship(:role, :service_account, type: :create, value_is_key: :role)
      change SetExpiry
      change {GenerateKey, prefix: "firmowid_org"}
    end

    destroy :destroy do
      description "Revoke a key, with the account of a company key."
      primary? true
      change DestroyServiceAccount
    end
  end

  policies do
    # Revoking a person's access deletes their keys.
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if always()
    end

    # A key cannot manage keys, so it cannot outlive its own revocation.
    policy AshAuthentication.Checks.UsingApiKey do
      forbid_if always()
    end

    policy action(:create) do
      authorize_if {AtLeastRole, role: :employee}
    end

    policy action(:create_for_company) do
      authorize_if {ActorRole, role: :admin}
    end

    policy action_type([:read, :destroy]) do
      description "Members manage their own keys, admins also the company's."
      authorize_if expr(user_id == ^actor(:id))
      forbid_unless {ActorRole, role: :admin}
      authorize_if expr(not is_nil(service_account_id))
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

    attribute :name, :string do
      allow_nil? false
      public? true
      constraints max_length: 100
      description "What the key is for, such as the program that uses it."
    end

    attribute :api_key_hash, :binary do
      allow_nil? false
      sensitive? true
    end

    attribute :expires_at, :utc_datetime_usec do
      public? true
      description "When the key stops working; nil for a key that works until revoked."
    end

    Resource.firmowid_timestamps()
  end

  relationships do
    belongs_to :organization, Organization do
      allow_nil? false
    end

    belongs_to :user, User do
      allow_nil? true
      public? true
      description "The person a personal key acts as."
    end

    belongs_to :service_account, ServiceAccount do
      allow_nil? true
      public? true
      description "The account a company key acts as."
    end
  end

  calculations do
    calculate :valid, :boolean, expr(is_nil(expires_at) or expires_at > now()) do
      description "Whether the key has not expired yet."
    end
  end

  identities do
    identity :unique_api_key_hash, [:api_key_hash], all_tenants?: true
  end
end
