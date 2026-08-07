defmodule Firmowid.Ash.Core.OauthRefreshToken do
  @moduledoc false
  use Ash.Resource,
    otp_app: :firmowid,
    domain: Firmowid.Ash.Core,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAuthentication.Oauth2Server.RefreshTokenResource],
    authorizers: [Ash.Policy.Authorizer]

  alias Firmowid.Ash.Resource

  require Resource

  postgres do
    table "oauth_refresh_tokens"
    repo Firmowid.Repo
  end

  code_interface do
    define :read, action: :read
    define :destroy, action: :destroy
    define :issue, action: :issue
    define :rotate, action: :rotate
    define :revoke, action: :revoke
    define :expunge_expired, action: :expunge_expired
  end

  actions do
    defaults [:read, :destroy]

    create :issue do
      description "Persist a newly issued OAuth refresh token."

      accept [
        :id,
        :chain_id,
        :generation,
        :token_hash,
        :client_id,
        :user_id,
        :scope,
        :resource_uri,
        :expires_at
      ]
    end

    update :rotate do
      description "Rotate a refresh token onto a successor and mark the predecessor used."
      primary? true
      argument :rotated_to_id, :uuid_v7, allow_nil?: false
      accept []

      change AshAuthentication.Oauth2Server.Changes.RotateRefreshToken
    end

    update :revoke do
      description "Revoke a refresh token so it can no longer be exchanged."
      accept []
      change atomic_update(:revoked_at, expr(now()))
    end
  end

  policies do
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if always()
    end
  end

  attributes do
    attribute :id, :uuid_v7 do
      primary_key? true
      allow_nil? false
      default &Ash.UUIDv7.generate/0
      writable? true
      public? true
    end

    attribute :token_hash, :string do
      allow_nil? false
      public? true
    end

    attribute :client_id, :uuid_v7 do
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

    attribute :chain_id, :uuid_v7 do
      allow_nil? false
      public? true
    end

    attribute :rotated_to_id, :uuid_v7 do
      public? true
    end

    attribute :rotated_at, :utc_datetime_usec do
      public? true
    end

    attribute :revoked_at, :utc_datetime_usec do
      public? true
    end

    attribute :generation, :integer do
      allow_nil? false
      default 0
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
    identity :by_token_hash, [:token_hash]
  end
end
