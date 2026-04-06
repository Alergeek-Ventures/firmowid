defmodule Firmowid.Ash.Timetracker.Changes.CleanupProjectTag do
  @moduledoc """
  After-action change that deletes the orphaned tag definition when a project is destroyed.

  Reads the tag definition via Ash, then destroys it. The tag definition's
  ON DELETE CASCADE handles entity_tags cleanup in all 3 polymorphic tables.
  """
  use Ash.Resource.Change

  alias Firmowid.Ash.Analysis.TagDefinition

  @impl true
  def init(opts), do: {:ok, opts}

  @impl true
  def change(changeset, _opts, context) do
    Ash.Changeset.after_action(changeset, fn _changeset, project ->
      delete_tag_definition(project.tag_definition_id, context)
      {:ok, project}
    end)
  end

  defp delete_tag_definition(nil, _context), do: :ok

  defp delete_tag_definition(tag_definition_id, context) do
    scope = %Firmowid.Ash.Scope{
      actor: context.actor,
      tenant: context.tenant
    }

    # authorize?: false because this is an internal system operation —
    # the parent project action already verified the actor's permissions.
    opts = [scope: scope, authorize?: false]

    case TagDefinition.get_tag_definition(tag_definition_id, opts) do
      {:ok, nil} ->
        :ok

      {:ok, tag_def} ->
        TagDefinition.destroy_tag_definition(tag_def, opts)

      {:error, %Ash.Error.Query.NotFound{}} ->
        :ok
    end
  end
end
