defmodule Firmowid.Ash.Timetracker.Changes.CleanupProjectTag do
  @moduledoc """
  After-action change that deletes the orphaned tag definition when a project is destroyed.

  Delegates to `Firmowid.Analysis.delete_tag_definition_by_id/1` (old context, not
  yet migrated). The tag definition's ON DELETE CASCADE handles entity_tags cleanup.
  """
  use Ash.Resource.Change

  @impl true
  def init(opts), do: {:ok, opts}

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, project ->
      # delete_tag_definition_by_id/1 always returns {:ok, :deleted} — it handles
      # nil tag_definition_id gracefully. If Repo.delete_all raises (DB error),
      # the exception propagates and rolls back the entire destroy transaction,
      # which is the desired behaviour (no partial deletes).
      {:ok, _} = Firmowid.Analysis.delete_tag_definition_by_id(project.tag_definition_id)
      {:ok, project}
    end)
  end
end
