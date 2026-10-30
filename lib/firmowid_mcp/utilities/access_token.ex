defmodule FirmowidMcp.Utilities.AccessToken do
  @moduledoc "Registers native OAuth JWTs for account-wide authentication revocation."

  alias Firmowid.Core.Token
  alias Firmowid.Core.User
  alias Firmowid.Oauth2Server

  @auth_context %{private: %{ash_authentication?: true}}

  @doc "Stores a native JWT under the subject used by RevokeAuthentication."
  @spec store!(String.t(), User.t()) :: Token.t()
  def store!(token, user) do
    changeset =
      Token.changeset_to_store_token(%{token: token, purpose: "oauth_access"},
        context: @auth_context
      )

    # Keep registration through the verifier's leeway when expired tokens are purged.
    expires_at =
      changeset
      |> Ash.Changeset.get_attribute(:expires_at)
      |> DateTime.shift(second: Oauth2Server.clock_skew_seconds())

    changeset
    # Native OAuth sub is a raw user ID, unlike AshAuthentication's subject URI.
    |> Ash.Changeset.force_change_attribute(:subject, AshAuthentication.user_to_subject(user))
    |> Ash.Changeset.force_change_attribute(:expires_at, expires_at)
    |> Ash.create!()
  end

  @doc "Checks active registration and its account, retaining native JWT clock skew."
  @spec active?(String.t() | nil, User.t()) :: boolean()
  def active?(jti, user) when is_binary(jti) and jti != "" do
    case Token.get_token!(%{jti: jti, purpose: "oauth_access"},
           context: @auth_context,
           not_found_error?: false
         ) do
      %Token{purpose: "oauth_access", subject: subject} ->
        subject == AshAuthentication.user_to_subject(user)

      _ ->
        false
    end
  end

  def active?(_, _), do: false
end
