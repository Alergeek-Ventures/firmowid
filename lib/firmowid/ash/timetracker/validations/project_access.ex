defmodule Firmowid.Ash.Timetracker.Validations.ProjectAccess do
  @moduledoc """
  Validates that the actor (or explicit user_id) has access to the session's project.

  Access means: the user is in `projects_users` for that project, and the
  project is not archived (`archived_at IS NULL`).
  """
  use Ash.Resource.Validation

  import Ecto.Query, warn: false

  alias Ash.Error.Changes.InvalidAttribute
  alias Firmowid.Repo

  @impl true
  def init(opts), do: {:ok, opts}

  @impl true
  def validate(changeset, _opts, _context) do
    project_id = Ash.Changeset.get_attribute(changeset, :project_id)
    user_id = Ash.Changeset.get_attribute(changeset, :user_id)

    cond do
      is_nil(project_id) ->
        :ok

      is_nil(user_id) ->
        :ok

      true ->
        check_access(user_id, project_id)
    end
  end

  defp check_access(user_id, project_id) do
    query =
      from pu in "projects_users",
        where:
          pu.user_id == type(^user_id, Ecto.UUID) and
            pu.project_id == type(^project_id, Ecto.UUID),
        join: p in "projects",
        on: p.id == pu.project_id and is_nil(p.archived_at),
        select: 1

    if Repo.exists?(query, skip_organization_id: true) do
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
