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

  code_interface do
    define :get_token, action: :get_token
    define :store_token, action: :store_token
    define :store_confirmation_changes, action: :store_confirmation_changes
    define :get_confirmation_changes, action: :get_confirmation_changes
    define :revoked?, action: :revoked?
    define :revoke_all_stored_for_subject, action: :revoke_all_stored_for_subject
    define :revoke_jti, action: :revoke_jti
    define :revoke_token, action: :revoke_token
    define :read_expired, action: :read_expired
    define :expunge_expired, action: :expunge_expired
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
