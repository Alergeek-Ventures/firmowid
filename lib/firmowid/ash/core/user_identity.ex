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
    extensions: [AshAuthentication.UserIdentity]

  postgres do
    table "user_identities"
    repo Firmowid.Repo
    migrate? false
  end

  user_identity do
    user_resource Firmowid.Ash.Core.User
  end
end
