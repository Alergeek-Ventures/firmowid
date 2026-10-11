defmodule Firmowid.Ash.Core.Changes.RequireActiveOauthUser do
  @moduledoc "Serializes OAuth issuance with archiving by locking the active user's row."

  use Ash.Resource.Change

  alias Firmowid.Ash.Core
  alias Firmowid.Ash.Core.User

  require Ash.Query

  @doc false
  @impl true
  @spec change(Ash.Changeset.t(), keyword(), Ash.Resource.Change.Context.t()) :: Ash.Changeset.t()
  def change(changeset, _opts, context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      # The lock stays held until the issuing action commits, so archive cleanup
      # cannot run before a concurrent code, consent, or refresh token is saved.
      query =
        User
        |> Ash.Query.filter(is_nil(archived_at))
        |> Ash.Query.lock(:for_update)

      case Core.get_user(Ash.Changeset.get_attribute(changeset, :user_id),
             query: query,
             actor: context.actor,
             tenant: context.tenant,
             context: %{private: %{ash_authentication?: true}}
           ) do
        {:ok, %User{}} -> changeset
        {:error, error} -> Ash.Changeset.add_error(changeset, error)
      end
    end)
  end
end
