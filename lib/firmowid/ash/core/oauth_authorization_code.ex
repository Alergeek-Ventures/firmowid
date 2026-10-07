defmodule Firmowid.Ash.Core.OauthAuthorizationCode do
  @moduledoc "OAuth authorization codes, including account-bound deletion cleanup."
  use Ash.Resource,
    otp_app: :firmowid,
    domain: Firmowid.Ash.Core,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAuthentication.Oauth2Server.AuthorizationCodeResource],
    authorizers: [Ash.Policy.Authorizer]

  alias Firmowid.Ash.Checks.AccountCleanup
  alias Firmowid.Ash.Resource

  require Resource

  postgres do
    table "oauth_authorization_codes"
    repo Firmowid.Repo
  end

  code_interface do
    define :read, action: :read
    define :destroy, action: :destroy
    define :create, action: :create
    define :consume, action: :consume
    define :expunge_expired, action: :expunge_expired
  end

  actions do
    defaults [:destroy]

    read :read do
      description "List authorization codes, optionally filtered by user."
      primary? true
      argument :user_id, :uuid

      prepare build(filter: expr(user_id == ^arg(:user_id))) do
        where present(:user_id)
      end
    end

    create :create do
      description "Issue a PKCE authorization code for an OAuth client and user."

      accept [
        :client_id,
        :user_id,
        :redirect_uri,
        :code_challenge,
        :scope,
        :resource_uri,
        :expires_at
      ]
    end

    update :consume do
      description "Mark an authorization code as used after a successful token exchange."
      accept []

      validate absent(:consumed_at) do
        message "code already used"
      end

      change atomic_update(:consumed_at, expr(now()))
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

    attribute :redirect_uri, :string do
      allow_nil? false
      public? true
    end

    attribute :code_challenge, :string do
      allow_nil? false
      public? true
    end

    attribute :scope, :string do
      allow_nil? false
      public? true
    end

    attribute :resource_uri, :string do
      allow_nil? false
      public? true
    end

    attribute :expires_at, :utc_datetime_usec do
      allow_nil? false
      public? true
    end

    attribute :consumed_at, :utc_datetime_usec do
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
end
