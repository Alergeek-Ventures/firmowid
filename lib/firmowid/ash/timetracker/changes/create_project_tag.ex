defmodule Firmowid.Ash.Timetracker.Changes.CreateProjectTag do
  @moduledoc """
  After-action change that creates an Analysis `TagDefinition` for a new project.

  Delegates to `Firmowid.Analysis.create_project_tag/1` (old context, not yet migrated)
  and links the resulting tag definition back to the project via an Ecto update.
  Runs inside the same transaction as the create action.
  """
  use Ash.Resource.Change

  @impl true
  def init(opts), do: {:ok, opts}

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, project ->
      name = project.name

      with {:ok, tag_def} <- Firmowid.Analysis.create_project_tag(name),
           {1, _} <- link_tag_definition(project, tag_def.id) do
        {:ok, %{project | tag_definition_id: tag_def.id}}
      else
        {:error, reason} -> {:error, reason}
        _ -> {:error, "Failed to link tag definition to project"}
      end
    end)
  end

  defp link_tag_definition(project, tag_def_id) do
    import Ecto.Query

    Firmowid.Repo.update_all(
      from(p in Firmowid.Ash.Timetracker.Project, where: p.id == ^project.id),
      set: [tag_definition_id: tag_def_id]
    )
  end
end
