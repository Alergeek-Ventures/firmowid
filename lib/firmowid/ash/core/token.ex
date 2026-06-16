# credo:disable-for-this-file AshCredo.Check.Design.MissingPrimaryAction
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
    extensions: [AshAuthentication.TokenResource],
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "tokens"
    repo Firmowid.Repo
  end

  token do
    created_at_attribute_name :inserted_at
  end

  policies do
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if always()
    end
  end

  attributes do
    attribute :jti, :string,
      primary_key?: true,
      allow_nil?: false,
      sensitive?: true,
      writable?: true,
      public?: true

    create_timestamp :inserted_at, type: :utc_datetime_usec, public?: false
    update_timestamp :updated_at, type: :utc_datetime_usec, public?: false
  end
end
