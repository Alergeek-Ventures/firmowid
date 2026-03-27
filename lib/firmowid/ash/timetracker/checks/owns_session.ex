defmodule Firmowid.Ash.Timetracker.Checks.OwnsSession do
  @moduledoc """
  Simple check: the actor's ID matches the session's `user_id`.

  Works for create actions (where filter checks like `relates_to_actor_via`
  cannot be used), by inspecting the changeset attribute.
  """
  use Ash.Policy.SimpleCheck

  @impl true
  def describe(_opts), do: "actor owns the session"

  @impl true
  def match?(nil, _context, _opts), do: false

  def match?(actor, %{subject: %Ash.Changeset{} = changeset}, _opts) do
    Ash.Changeset.get_attribute(changeset, :user_id) == actor.id
  end

  def match?(_actor, _context, _opts), do: false
end
