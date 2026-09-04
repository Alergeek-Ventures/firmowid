defmodule Firmowid.Ash.Core.UserIdentity do
  @moduledoc """
  OAuth identity resource for `ash_authentication`.

  Stores the link between a user and an external OAuth provider (e.g. Google).
  Replaces the legacy `google_provider_id` column on the users table with a
  proper relational model that supports multiple providers.

  The `AshAuthentication.UserIdentity` extension auto-generates all attributes,
  actions, and internal plumbing.
  """
  use Ash.Resource,
    domain: Firmowid.Ash.Core,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshAuthentication.UserIdentity]

  alias Firmowid.Ash.Resource

  require Resource

  postgres do
    table "user_identities"
    repo Firmowid.Repo
  end

  user_identity do
    user_resource Firmowid.Ash.Core.User
  end

  code_interface do
    define :read, action: :read
    define :destroy, action: :destroy
    define :upsert, action: :upsert
  end

  actions do
    defaults [:read]

    read :read_for_user_and_strategy do
      description "Fetch a user identity for a specific user and auth strategy."
      argument :user_id, :uuid, allow_nil?: false
      argument :strategy, :string, allow_nil?: false

      filter expr(user_id == ^arg(:user_id) and strategy == ^arg(:strategy))
    end
  end

  policies do
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if expr(user_id == ^actor(:id))
    end

    policy action_type(:destroy) do
      authorize_if expr(user_id == ^actor(:id))
    end

    policy action(:upsert) do
      forbid_if always()
    end
  end

  attributes do
    uuid_primary_key :id
    Resource.firmowid_timestamps()
  end
end
