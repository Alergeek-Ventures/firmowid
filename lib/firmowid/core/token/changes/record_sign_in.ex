defmodule Firmowid.Core.Token.Changes.RecordSignIn do
  @moduledoc """
  Records the account's last sign-in when a session token is stored for it.

  Every sign-in (password, Google, sign-in token, remember-me) stores a `"user"`
  token, so this is the one place that sees all of them. Password reset and email
  confirmation tokens are stored as `"user"` too, but carry the action they are for
  in an `"act"` claim and cannot be a session. A superuser's session as the account
  (see `Firmowid.Core.impersonation_claims/1`) is not its sign-in either, nor is a
  blocked account's (see the User `:access_block` calculation), which gets no session.
  """

  use Ash.Resource.Change

  alias Firmowid.Core
  alias Firmowid.Core.User
  alias Firmowid.SystemActor

  @doc false
  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn changeset, token ->
      %{ash_authentication: %{user: %User{} = user}} = changeset.context

      claims = token.extra_data || %{}

      with true <- is_nil(Core.impersonator_id(claims)) and not is_map_key(claims, "act"),
           {:ok, %User{access_block: nil}} <- Ash.load(user, :access_block, actor: user),
           actor = %SystemActor{org_id: nil, role: :sign_in_recorder, user_id: user.id},
           {:ok, _user} <- Core.record_user_sign_in(user, actor: actor) do
        {:ok, token}
      else
        {:error, error} -> {:error, error}
        _not_a_sign_in -> {:ok, token}
      end
    end)
  end
end
