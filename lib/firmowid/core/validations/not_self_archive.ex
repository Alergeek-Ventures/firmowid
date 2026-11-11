defmodule Firmowid.Core.Validations.NotSelfArchive do
  @moduledoc """
  Validation preventing a member from archiving themselves.
  """
  use Ash.Resource.Validation
  use Gettext, backend: Firmowid.Gettext

  alias Ash.Error.Changes.InvalidAttribute
  alias Firmowid.Core.User

  @impl true
  def validate(changeset, _opts, context), do: check(context.actor, changeset.data)

  @impl true
  def atomic(changeset, _opts, context), do: check(context.actor, changeset.data)

  # Only a person archives themselves; system actors (e.g. the plan limits) are not members.
  # `is_struct/2` rather than a `%User{}` pattern keeps resources using this
  # validation from recompiling whenever `User` changes (see `Firmowid.Checks.ActorRole`).
  defp check(%{id: user_id} = actor, %{user_id: user_id}) when is_struct(actor, User) and not is_nil(user_id) do
    {:error,
     InvalidAttribute.exception(
       field: :id,
       message: gettext_noop("You cannot archive your own account.")
     )}
  end

  defp check(_actor, _member), do: :ok
end
