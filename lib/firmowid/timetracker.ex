defmodule Firmowid.Timetracker do
  @moduledoc """
  The Czasosledź (timetracker) context.
  """

  import Ecto.Query, warn: false

  alias Firmowid.Accounts
  alias Firmowid.Timetracker.Project
  alias Firmowid.Timetracker.ProjectUser
  alias Firmowid.Timetracker.Session
  alias Firmowid.Repo

  def list_user_projects(user_id) do
    Accounts.get_user!(user_id) |> Repo.preload(:projects) |> Map.get(:projects)
  end

  def list_projects_with_users() do
    Project
    |> Repo.all()
    |> Repo.preload(:users)
  end

  def list_users_with_projects() do
    Accounts.User
    |> Repo.all()
    |> Repo.preload(:projects)
  end

  def create_project(attrs \\ %{}) do
    %Project{}
    |> Project.changeset(attrs)
    |> Repo.insert()
  end

  def add_user_to_project(user_id, project_id) do
    organization_id = Repo.get_org_id()

    %ProjectUser{}
    |> ProjectUser.changeset(%{
      project_id: project_id,
      user_id: user_id,
      organization_id: organization_id
    })
    |> Repo.insert()
  end

  def remove_user_from_project(user_id, project_id) do
    ProjectUser
    |> where([pu], pu.user_id == ^user_id and pu.project_id == ^project_id)
    |> Repo.delete_all()
  end

  def start_session(attrs \\ %{}) do
    %Session{}
    |> Session.changeset(attrs)
    |> Repo.insert()
  end

  def end_session(session_id) do
    end_session(session_id, Date.utc_today())
  end

  def end_session(session_id, date) do
    Session
    |> Repo.get(session_id)
    |> Repo.update(end: date)
  end

  def list_user_sessions(user_id) do
    Session
    |> where([s], s.user_id == ^user_id)
    |> Repo.all()
    |> Repo.preload(:project)
  end

  def list_user_sessions_grouped_by_day(user_id) do
    list_user_sessions(user_id) |> Enum.group_by(& &1.start)
  end

  def get_current_session(user_id) do
    Session
    |> where([s], s.user_id == ^user_id and is_nil(s.end_time))
    |> order_by([s], desc: s.start_time)
    |> limit(1)
    |> Repo.one()
    |> Repo.preload(:project)
  end
end
