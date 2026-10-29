defmodule Firmowid.Core.Validations.NotSelfArchive do
  @moduledoc """
  Validation preventing a member from archiving themselves.
  """
  use Ash.Resource.Validation
  use Gettext, backend: Firmowid.Gettext

  alias Ash.Error.Changes.InvalidAttribute

  @impl true
  def validate(changeset, _opts, context) do
    actor_id = context.actor && context.actor.id
    user_id = changeset.data.user_id

    if actor_id && user_id && actor_id == user_id do
      {:error,
       InvalidAttribute.exception(
         field: :id,
         message: gettext("You cannot archive your own account.")
       )}
    else
      :ok
    end
  end

  @impl true
  def atomic(changeset, _opts, context) do
    actor_id = context.actor && context.actor.id
    user_id = changeset.data.user_id

    if actor_id && user_id && actor_id == user_id do
      {:error,
       InvalidAttribute.exception(
         field: :id,
         message: gettext("You cannot archive your own account.")
       )}
    else
      :ok
    end
  end
end
