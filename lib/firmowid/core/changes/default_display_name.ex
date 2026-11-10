defmodule Firmowid.Core.Changes.DefaultDisplayName do
  @moduledoc """
  Falls back to the full `name` when an organization has no `display_name`, so
  the app always has a name to show while invoices keep the full one.
  """
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    case Ash.Changeset.get_attribute(changeset, :display_name) do
      nil ->
        Ash.Changeset.force_change_attribute(
          changeset,
          :display_name,
          Ash.Changeset.get_attribute(changeset, :name)
        )

      _display_name ->
        changeset
    end
  end
end
