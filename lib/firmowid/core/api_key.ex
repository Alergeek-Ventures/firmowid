defmodule Firmowid.Core.ApiKey do
  @moduledoc """
  A key a server uses to call the API of an organization without anyone signing in.

  It acts as the admin who created it, in the organization it was created in (see the
  User `api_key` strategy). Only its hash is stored: the key itself is shown once, in the
  `plaintext_api_key` metadata of the created record. Deleting it revokes it. Leaving the
  organization, a password change and deleting the account revoke the person's keys (see
  `Firmowid.Core.User.Changes.RevokeAuthentication`).
  """
  use Ash.Resource,
    domain: Firmowid.Core,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias Firmowid.Checks.ActorRole
  alias Firmowid.Core.Organization
  alias Firmowid.Core.User
  alias Firmowid.Resource

  require Resource

  @scopes [:sales_invoices]

  postgres do
    table "api_keys"
    repo Firmowid.Repo

    references do
      reference :organization, on_delete: :delete
      reference :user, on_delete: :delete
    end
  end

  actions do
    defaults [:read]

    read :list do
      description "List the organization's API keys, newest first."
      prepare build(sort: [inserted_at: :desc])
    end

    create :create do
      description "Create an API key acting as the actor in the organization."
      accept [:name, :scopes, :expires_at]

      change relate_actor(:user)

      change {AshAuthentication.Strategy.ApiKey.GenerateApiKey, prefix: :firmowid, hash: :api_key_hash}
    end

    destroy :destroy do
      description "Revoke an API key."
      primary? true
    end
  end

  policies do
    # Signing in with a key reads it, and revoking a person's access deletes their keys.
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if always()
    end

    # A key cannot manage keys, so it cannot outlive its own revocation.
    policy AshAuthentication.Checks.UsingApiKey do
      forbid_if always()
    end

    policy action([:read, :list, :create, :destroy]) do
      authorize_if {ActorRole, role: :admin}
    end
  end

  multitenancy do
    strategy :attribute
    attribute :organization_id
    # Signing in finds the key before its organization is known.
    global? true
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
      constraints max_length: 100
      description "What the key is for, such as the server that uses it."
    end

    attribute :scopes, {:array, :atom} do
      allow_nil? false
      public? true
      constraints min_length: 1, items: [one_of: @scopes]

      description "The parts of the API the key opens; `:sales_invoices` issues and reads sales invoices."
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
      allow_nil? false
      public? true
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

  @doc "The scopes a key can have."
  @spec scopes() :: [atom()]
  def scopes, do: @scopes
end
