defmodule Firmowid.Core.User.Changes.RevokeAuthenticationOnPasswordChange do
  @moduledoc """
  Revokes browser sessions and OAuth grants when an update sets a new password.

  The password strategy hashes the new password in a `before_action` hook, so a
  `where: changing(:hashed_password)` condition is evaluated too early and never
  matches. This change checks the hash after the action has run instead.
  """

  use Ash.Resource.Change

  alias Ash.Resource.Change.Context
  alias Firmowid.Core.User.Changes.RevokeAuthentication

  @doc false
  @impl true
  @spec change(Ash.Changeset.t(), keyword(), Context.t()) :: Ash.Changeset.t()
  def change(changeset, _opts, context) do
    # Prepended so it runs before a password reset issues the new session token. The
    # reset token itself is left for the reset action, which revokes it afterwards.
    Ash.Changeset.after_action(
      changeset,
      fn changeset, user ->
        if Ash.Changeset.changing_attribute?(changeset, :hashed_password) do
          with :ok <- RevokeAuthentication.revoke(user, context, reset_token_jti(changeset)),
               do: {:ok, user}
        else
          {:ok, user}
        end
      end,
      prepend?: true
    )
  end

  defp reset_token_jti(changeset) do
    with token when is_binary(token) <- Ash.Changeset.get_argument(changeset, :reset_token),
         {:ok, %{"jti" => jti}} <- AshAuthentication.Jwt.peek(token) do
      jti
    else
      _ -> nil
    end
  end

  @doc false
  @impl true
  @spec atomic(Ash.Changeset.t(), keyword(), Context.t()) :: {:ok, Ash.Changeset.t()}
  def atomic(changeset, opts, context), do: {:ok, change(changeset, opts, context)}
end
