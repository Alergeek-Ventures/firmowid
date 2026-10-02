defmodule Firmowid.Ash.Timetracker.Changes.CleanupProjectTag do
  @moduledoc """
  After-action change that deletes the orphaned tag definition when a project is destroyed.

  Checks for remaining projects in the current tenant, including archived projects,
  before reading and destroying the orphaned tag definition. The tag definition's
  ON DELETE CASCADE handles entity_tags cleanup in all 3 polymorphic tables.
  """
  use Ash.Resource.Change

  alias Firmowid.Ash.Analysis.TagDefinition
  alias Firmowid.Ash.Scope
  alias Firmowid.Ash.SystemActor
  alias Firmowid.Ash.Timetracker.Project

  @impl true
  def init(opts), do: {:ok, opts}

  @impl true
  def change(changeset, _opts, context) do
    Ash.Changeset.after_action(changeset, fn _changeset, project ->
      with :ok <- delete_orphaned_tag_definition(project.tag_definition_id, context) do
        {:ok, project}
      end
    end)
  end

  defp delete_orphaned_tag_definition(nil, _context), do: :ok

  defp delete_orphaned_tag_definition(tag_definition_id, context) do
    scope = %Scope{
      actor: %SystemActor{org_id: context.tenant, role: :project_tag_manager},
      tenant: context.tenant
    }

    case Project.list(%{tag_definition_id: tag_definition_id},
           scope: scope,
           query: [limit: 1, select: [:id]]
         ) do
      {:ok, []} -> delete_tag_definition(tag_definition_id, scope)
      {:ok, [_ | _]} -> :ok
      {:error, error} -> {:error, error}
    end
  end

  defp delete_tag_definition(tag_definition_id, scope) do
    opts = [scope: scope]

    case TagDefinition.get_tag_definition(tag_definition_id, opts) do
      {:ok, nil} ->
        :ok

      {:ok, tag_def} ->
        TagDefinition.destroy(tag_def, opts)

      {:error, %Ash.Error.Query.NotFound{}} ->
        :ok

      {:error, error} ->
        {:error, error}
    end
  end
end
