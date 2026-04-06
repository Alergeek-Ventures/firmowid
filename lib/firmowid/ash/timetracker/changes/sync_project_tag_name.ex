defmodule Firmowid.Ash.Timetracker.Changes.SyncProjectTagName do
  @moduledoc """
  After-action change that syncs the project's tag definition name on update.

  Reads the tag definition via Ash, then updates it if the name differs.
  Only runs when the project name has actually changed (via `where: [changing(:name)]`
  on the resource).
  """
  use Ash.Resource.Change

  alias Firmowid.Ash.Analysis.TagDefinition

  @impl true
  def init(opts), do: {:ok, opts}

  @impl true
  def change(changeset, _opts, context) do
    Ash.Changeset.after_action(changeset, fn _changeset, project ->
      case sync_tag_name(project.tag_definition_id, project.name, context) do
        {:ok, _} -> {:ok, project}
        {:error, reason} -> {:error, reason}
      end
    end)
  end

  defp sync_tag_name(nil, _name, _context), do: {:ok, :synced}

  defp sync_tag_name(tag_definition_id, name, context) do
    scope = %Firmowid.Ash.Scope{
      actor: context.actor,
      tenant: context.tenant
    }

    # authorize?: false because this is an internal system operation —
    # the parent project action already verified the actor's permissions.
    opts = [scope: scope, authorize?: false]

    case TagDefinition.get_tag_definition(tag_definition_id, opts) do
      {:ok, nil} ->
        {:ok, :synced}

      {:ok, %{name: ^name}} ->
        {:ok, :synced}

      {:ok, tag_def} ->
        case TagDefinition.update_tag_definition(tag_def, %{name: name}, opts) do
          {:ok, _} -> {:ok, :synced}
          {:error, changeset} -> {:error, changeset}
        end

      {:error, %Ash.Error.Query.NotFound{}} ->
        {:ok, :synced}
    end
  end
end
