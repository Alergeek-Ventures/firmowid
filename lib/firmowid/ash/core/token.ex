defmodule Firmowid.Ash.Core.Token do
  @moduledoc """
  Token resource for `ash_authentication`.

  Stores JWTs (session tokens, password reset tokens, confirmation tokens)
  in the database for revocation and validation. The `jti` (JWT ID) is the
  primary key — there is no surrogate UUID.

  The `AshAuthentication.TokenResource` extension auto-generates all
  attributes, actions, and internal plumbing.
  """
  use Ash.Resource,
    domain: Firmowid.Ash.Core,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAuthentication.TokenResource]

  postgres do
    table "tokens"
    repo Firmowid.Repo
    migrate? false
  end

  token do
    created_at_attribute_name :inserted_at
  end
end
