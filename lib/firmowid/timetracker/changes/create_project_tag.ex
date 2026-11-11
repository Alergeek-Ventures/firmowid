defmodule Firmowid.Timetracker.Changes.CreateProjectTag do
  @moduledoc """
  After-action change that creates an Analysis `TagDefinition` for a new project.

  Calls `Analysis.TagDefinition.create_for_project/2` via the Ash code interface
  and links the resulting tag definition back to the project via an Ash update.
  Runs inside the same transaction as the create action.
  """
  use Ash.Resource.Change

  alias Firmowid.Analysis.TagDefinition
  alias Firmowid.Scope
  alias Firmowid.SystemActor
  alias Firmowid.Timetracker.Project

  @impl true
  def change(changeset, _opts, context) do
    Ash.Changeset.after_action(changeset, fn _changeset, project ->
      scope = %Scope{
        actor: %SystemActor{org_id: context.tenant, role: :project_tag_manager},
        tenant: context.tenant
      }

      with {:ok, tag_def} <- TagDefinition.create_for_project(project.name, scope: scope) do
        Project.link_tag(project, %{tag_definition_id: tag_def.id}, scope: scope)
      end
    end)
  end
end
