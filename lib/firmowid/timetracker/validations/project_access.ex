defmodule Firmowid.Timetracker.Validations.ProjectAccess do
  @moduledoc """
  Validates that the session's member has access to the session's project.

  Access means: the member is in `projects_users` for that project, and the
  project is not archived (`archived_at IS NULL`).
  """
  use Ash.Resource.Validation

  alias Ash.Error.Changes.InvalidAttribute
  alias Firmowid.Timetracker.ProjectUser

  require Ash.Query

  @impl true
  def init(opts), do: {:ok, opts}

  @impl true
  def validate(changeset, _opts, context) do
    project_id = Ash.Changeset.get_attribute(changeset, :project_id)
    member_id = Ash.Changeset.get_attribute(changeset, :member_id)

    cond do
      is_nil(project_id) ->
        :ok

      is_nil(member_id) ->
        :ok

      true ->
        check_access(changeset, context, member_id, project_id)
    end
  end

  defp check_access(changeset, context, member_id, project_id) do
    has_access? =
      ProjectUser
      |> Ash.Query.filter(
        expr(
          member_id == ^member_id and
            project_id == ^project_id and
            exists(project, is_nil(archived_at))
        )
      )
      |> Ash.exists?(actor: context.actor, tenant: changeset.tenant)

    if has_access? do
      :ok
    else
      {:error,
       InvalidAttribute.exception(
         field: :project_id,
         message: "user does not have access to this project"
       )}
    end
  end
end
