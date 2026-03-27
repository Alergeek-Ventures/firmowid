defmodule Firmowid.Ash.Timetracker.Changes.CreateProjectTag do
  @moduledoc """
  After-action change that creates an Analysis `TagDefinition` for a new project.

  Delegates to `Firmowid.Analysis.create_project_tag/1` (old context, not yet migrated)
  and links the resulting tag definition back to the project via an Ash update.
  Runs inside the same transaction as the create action.
  """
  use Ash.Resource.Change

  @impl true
  def init(opts), do: {:ok, opts}

  @impl true
  def change(changeset, _opts, context) do
    Ash.Changeset.after_action(changeset, fn _changeset, project ->
      name = project.name

      with {:ok, tag_def} <- Firmowid.Analysis.create_project_tag(name) do
        link_tag_definition(project, tag_def.id, context)
      end
    end)
  end

  defp link_tag_definition(project, tag_def_id, context) do
    project
    |> Ash.Changeset.for_update(:link_tag, %{tag_definition_id: tag_def_id},
      actor: context.actor,
      tenant: context.tenant,
      # TODO: migrate away from authorize?: false — the :link_tag action is
      # internal (sets tag_definition_id after tag creation). Replace when
      # change modules can run actions in a privileged context.
      authorize?: false
    )
    |> Ash.update()
  end
end
