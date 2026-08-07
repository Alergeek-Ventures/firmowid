defmodule Firmowid.Ash.Core.OauthClient do
  @moduledoc false
  use Ash.Resource,
    otp_app: :firmowid,
    domain: Firmowid.Ash.Core,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias Firmowid.Ash.Resource

  require Resource

  postgres do
    table "oauth_clients"
    repo Firmowid.Repo
  end

  code_interface do
    define :read, action: :read
    define :destroy, action: :destroy
    define :register, action: :register
    define :register_cimd, action: :register_cimd
    define :touch, action: :touch
  end

  actions do
    defaults [:read, :destroy]

    create :register do
      description "Register a public OAuth client via dynamic client registration."
      primary? true

      accept [
        :client_name,
        :redirect_uris,
        :grant_types,
        :response_types,
        :token_endpoint_auth_method,
        :scope
      ]
    end

    create :register_cimd do
      description "Upsert an OAuth client from a Client ID Metadata Document URL."
      upsert? true
      upsert_identity :by_cimd_url

      accept [
        :cimd_url,
        :client_name,
        :redirect_uris,
        :grant_types,
        :response_types,
        :token_endpoint_auth_method,
        :scope
      ]
    end

    update :touch do
      description "Record the last time this OAuth client was used."
      accept []
      change atomic_update(:last_used_at, expr(now()))
    end
  end

  policies do
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if always()
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :client_name, :string do
      allow_nil? false
      public? true
    end

    attribute :redirect_uris, {:array, :string} do
      allow_nil? false
      public? true
    end

    attribute :grant_types, {:array, :string} do
      public? true
    end

    attribute :response_types, {:array, :string} do
      public? true
    end

    attribute :token_endpoint_auth_method, :string do
      public? true
    end

    attribute :scope, :string do
      public? true
    end

    attribute :cimd_url, :string do
      public? true
    end

    attribute :last_used_at, :utc_datetime_usec do
      public? true
    end

    Resource.firmowid_timestamps()
  end

  identities do
    identity :by_cimd_url, [:cimd_url]
  end
end
