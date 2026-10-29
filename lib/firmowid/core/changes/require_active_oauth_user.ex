defmodule Firmowid.Core.Changes.RequireActiveOauthUser do
  @moduledoc """
  Serializes OAuth issuance with leaving the organization by locking the user's row.

  A grant for an organization (the tenant) requires the user's usable member there;
  one without an organization (issued before it was chosen on the consent screen)
  requires any.
  """

  use Ash.Resource.Change

  alias Ash.Error.Query.NotFound
  alias Firmowid.Core
  alias Firmowid.Core.User

  @doc false
  @impl true
  @spec change(Ash.Changeset.t(), keyword(), Ash.Resource.Change.Context.t()) :: Ash.Changeset.t()
  def change(changeset, _opts, context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      # The lock stays held until the issuing action commits, so leaving the
      # organization cannot revoke grants before a concurrent code, consent, or
      # refresh token is saved. The membership is checked by a separate query
      # once the lock is held: a statement that waited for the lock still reads
      # the rows from before the archival committed.
      query = Ash.Query.lock(User, :for_update)

      with {:ok, %User{} = user} <-
             Core.get_user(Ash.Changeset.get_attribute(changeset, :user_id),
               query: query,
               actor: context.actor,
               tenant: context.tenant,
               context: %{private: %{ash_authentication?: true}}
             ),
           grant_organization_id =
             Ash.Changeset.get_attribute(changeset, :organization_id) || changeset.tenant,
           %User{member: %{organization_id: organization_id}}
           when is_nil(grant_organization_id) or organization_id == grant_organization_id <-
             Core.load_member(user, grant_organization_id) do
        changeset
      else
        %User{} = user ->
          Ash.Changeset.add_error(
            changeset,
            NotFound.exception(resource: User, primary_key: user.id)
          )

        {:error, error} ->
          Ash.Changeset.add_error(changeset, error)
      end
    end)
  end
end
