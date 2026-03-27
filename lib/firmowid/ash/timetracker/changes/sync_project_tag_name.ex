defmodule Firmowid.Ash.Timetracker.Changes.SyncProjectTagName do
  @moduledoc """
  After-action change that syncs the project's tag definition name on update.

  Delegates to `Firmowid.Analysis.sync_project_tag_name/2` (old context, not yet
  migrated). Only runs when the project name has actually changed.
  """
  use Ash.Resource.Change

  @impl true
  def init(opts), do: {:ok, opts}

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, project ->
      case Firmowid.Analysis.sync_project_tag_name(project.tag_definition_id, project.name) do
        {:ok, _} -> {:ok, project}
        {:error, reason} -> {:error, reason}
      end
    end)
  end
end
