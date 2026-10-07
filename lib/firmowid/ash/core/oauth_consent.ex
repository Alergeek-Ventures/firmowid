defmodule Firmowid.Ash.Core.OauthConsent do
  @moduledoc "OAuth consent grants, including account-bound deletion cleanup."
  use Ash.Resource,
    otp_app: :firmowid,
    domain: Firmowid.Ash.Core,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias Firmowid.Ash.Checks.AccountCleanup
  alias Firmowid.Ash.Resource

  require Resource

  postgres do
    table "oauth_consents"
    repo Firmowid.Repo
  end

  code_interface do
    define :read, action: :read
    define :destroy, action: :destroy
    define :grant, action: :grant
  end

  actions do
    defaults [:destroy]

    read :read do
      description "List OAuth consents, optionally filtered by user."
      primary? true
      argument :user_id, :uuid

      prepare build(filter: expr(user_id == ^arg(:user_id))) do
        where present(:user_id)
      end
    end

    create :grant do
      description "Record or refresh a user's granted OAuth scopes for a client."
      upsert? true
      upsert_identity :by_user_client
      accept [:user_id, :client_id, :scope]
      change set_attribute(:granted_at, &DateTime.utc_now/0)
    end
  end

  policies do
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if always()
    end

    policy action([:read, :destroy]) do
      authorize_if AccountCleanup
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :client_id, :uuid_v7 do
      allow_nil? false
      public? true
    end

    attribute :scope, :string do
      allow_nil? false
      public? true
    end

    attribute :granted_at, :utc_datetime_usec do
      allow_nil? false
      public? true
    end

    Resource.firmowid_timestamps()
  end

  relationships do
    belongs_to :user, Firmowid.Ash.Core.User do
      allow_nil? false
      attribute_public? true
      attribute_writable? true
    end
  end

  identities do
    identity :by_user_client, [:user_id, :client_id]
  end
end
