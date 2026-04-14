defmodule Firmowid.Ash.Core.Validations.NotSelfArchive do
  @moduledoc """
  Validation preventing a user from archiving themselves.
  """
  use Ash.Resource.Validation

  alias Ash.Error.Changes.InvalidAttribute

  @impl true
  def validate(changeset, _opts, context) do
    actor_id = context.actor && context.actor.id
    user_id = changeset.data.id

    if actor_id && user_id && actor_id == user_id do
      {:error,
       InvalidAttribute.exception(
         field: :id,
         message: "Nie możesz zarchiwizować własnego konta."
       )}
    else
      :ok
    end
  end

  @impl true
  def atomic(changeset, _opts, context) do
    actor_id = context.actor && context.actor.id
    user_id = changeset.data.id

    if actor_id && user_id && actor_id == user_id do
      {:error,
       InvalidAttribute.exception(
         field: :id,
         message: "Nie możesz zarchiwizować własnego konta."
       )}
    else
      :ok
    end
  end
end
