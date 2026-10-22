defmodule Firmowid.Ash.Core.Changes.RequireNoActiveMember do
  @moduledoc """
  Rejects joining or restoring an organization when the account already has an
  active member: an account works in one organization at a time.

  The account row is locked first, so concurrent joins of the same account (for
  example from two onboarding tabs) are serialized and the second one sees the
  member created by the first.

  Options:
  - `user_id` — the changeset data field holding the account ID (`:id` on the
    user, `:user_id` on a member)
  """
  use Ash.Resource.Change

  alias Ash.Error.Changes.InvalidChanges
  alias Firmowid.Ash.Core
  alias Firmowid.Ash.Core.User

  @doc false
  @impl true
  @spec change(Ash.Changeset.t(), keyword(), Ash.Resource.Change.Context.t()) :: Ash.Changeset.t()
  def change(changeset, opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      user_id = Map.fetch!(changeset.data, Keyword.fetch!(opts, :user_id))

      # An authentication read: it only locks the row and grants nothing else.
      with {:ok, user} <-
             Core.get_user(user_id,
               query: Ash.Query.lock(User, :for_update),
               context: %{private: %{ash_authentication?: true}}
             ),
           %User{member: nil} <- Core.load_member(user) do
        changeset
      else
        %User{} ->
          Ash.Changeset.add_error(
            changeset,
            InvalidChanges.exception(message: "Konto należy już do innej organizacji.")
          )

        {:error, error} ->
          Ash.Changeset.add_error(changeset, error)
      end
    end)
  end
end
