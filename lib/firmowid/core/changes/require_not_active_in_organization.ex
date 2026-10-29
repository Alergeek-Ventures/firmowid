defmodule Firmowid.Core.Changes.RequireNotActiveInOrganization do
  @moduledoc """
  Rejects redeeming an invitation to an organization the account is already
  active in: joining again would change its role there.

  The account row is locked first, so concurrent redemptions by the same account
  (for example of two invitations to one organization) are serialized and the
  second one sees the member created by the first.
  """
  use Ash.Resource.Change
  use Gettext, backend: Firmowid.Gettext

  alias Ash.Error.Changes.InvalidChanges
  alias Firmowid.Core
  alias Firmowid.Core.User

  @doc false
  @impl true
  @spec change(Ash.Changeset.t(), keyword(), Ash.Resource.Change.Context.t()) :: Ash.Changeset.t()
  def change(changeset, _opts, context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      organization_id = changeset.data.organization_id

      # An authentication read: it only locks the row and grants nothing else.
      with {:ok, user} <-
             Core.get_user(context.actor.id,
               query: Ash.Query.lock(User, :for_update),
               context: %{private: %{ash_authentication?: true}}
             ),
           false <-
             Enum.any?(Core.list_active_members(user), &(&1.organization_id == organization_id)) do
        changeset
      else
        true ->
          Ash.Changeset.add_error(
            changeset,
            InvalidChanges.exception(
              fields: [:organization_id],
              message: gettext("You already belong to this organization.")
            )
          )

        {:error, error} ->
          Ash.Changeset.add_error(changeset, error)
      end
    end)
  end
end
