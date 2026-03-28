defmodule Firmowid.Ash.Timetracker.Checks.OwnsResource do
  @moduledoc """
  Simple check: the actor's ID matches the resource's ownership attribute.

  Works for create actions (where filter checks like `relates_to_actor_via`
  cannot be used), by inspecting the changeset attribute.

  ## Options

    * `:attribute` — the attribute to compare against `actor.id`.
      Defaults to `:user_id`.

  ## Usage

      authorize_if {OwnsResource, attribute: :user_id}

  Or with the default attribute:

      authorize_if OwnsResource
  """
  use Ash.Policy.SimpleCheck

  @impl true
  def describe(opts) do
    attr = Keyword.get(opts, :attribute, :user_id)
    "actor owns the resource (#{attr} == actor.id)"
  end

  @impl true
  def match?(nil, _context, _opts), do: false

  def match?(actor, %{subject: %Ash.Changeset{} = changeset}, opts) do
    attr = Keyword.get(opts, :attribute, :user_id)
    Ash.Changeset.get_attribute(changeset, attr) == actor.id
  end

  def match?(_actor, _context, _opts), do: false
end
