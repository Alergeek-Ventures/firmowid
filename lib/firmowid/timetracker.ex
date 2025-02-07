defmodule Firmowid.Timetracker do
  @moduledoc """
  The Czasosledź (timetracker) context.
  """

  import Ecto.Query, warn: false

  @behaviour Bodyguard.Policy

  alias Firmowid.Accounts
  alias Firmowid.Timetracker.Project
  alias Firmowid.Timetracker.ProjectUser
  alias Firmowid.Timetracker.Session
  alias Firmowid.Repo

  def authorize(_, %{role: :admin}, _), do: true

  def authorize(:read_user_sessions, %{role: :employee}, _), do: true
  def authorize(:read_user_projects, %{role: :employee}, _), do: true
  def authorize(:update_session, %{role: :employee, id: user_id}, %{user_id: user_id}), do: true
  def authorize(:delete_session, %{role: :employee, id: user_id}, %{user_id: user_id}), do: true
  def authorize(:create_session, %{role: :employee}, _), do: true
  def authorize(_, _, _), do: false

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

  def update_project(%Project{} = project, attrs) do
    project
    |> Project.changeset(attrs)
    |> Repo.update()
  end

  def delete_project(%Project{} = project) do
    Repo.delete(project)
  end

  def get_project!(id), do: Repo.get!(Project, id)

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
    session = Repo.get(Session, session_id)

    Session.changeset(session, %{end_datetime: DateTime.utc_now()})
    |> Repo.update()
  end

  def end_session(session_id, date) do
    Session
    |> Repo.get(session_id)
    |> Repo.update(end: date)
  end

  def delete_session(session_id) do
    Session
    |> Repo.get(session_id)
    |> Repo.delete()
  end

  def get_session(id), do: Repo.get(Session, id)

  def get_session!(id), do: Repo.get!(Session, id)

  def list_user_sessions(user_id) do
    Session
    |> where([s], s.user_id == ^user_id)
    |> order_by([s], desc: s.start_datetime)
    |> Repo.all()
    |> Repo.preload(:project)
    |> Enum.map(&Session.put_duration/1)
  end

  def get_current_session(user_id) do
    Session
    |> where([s], s.user_id == ^user_id and is_nil(s.end_datetime))
    |> order_by([s], desc: s.start_datetime)
    |> limit(1)
    |> Repo.one()
    |> Repo.preload(:project)
    |> Session.put_duration()
  end

  def update_session(session_id, attrs) do
    Session
    |> Repo.get(session_id)
    |> Session.changeset(attrs)
    |> Repo.update()
  end
end
