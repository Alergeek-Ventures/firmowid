defmodule Firmowid.Timetracker do
  @moduledoc """
  The Czasosledź (timetracker) context.
  """
  require Logger
  import Ecto.Query, warn: false

  @behaviour Bodyguard.Policy

  alias Firmowid.Blobs
  alias Firmowid.Accounts
  alias Firmowid.Timetracker.Project
  alias Firmowid.Timetracker.ProjectUser
  alias Firmowid.Timetracker.Session
  alias Firmowid.Repo

  def authorize(_, %{role: :admin}, _), do: true

  def authorize(:read_user_sessions, %{role: :employee}, _), do: true
  def authorize(:read_user_projects, %{role: :employee}, _), do: true
  def authorize(:read_user_hours_records, %{role: :employee}, _), do: true
  def authorize(:create_hours_record, %{role: :employee}, _), do: true
  def authorize(:update_session, %{role: :employee, id: user_id}, %{user_id: user_id}), do: true
  def authorize(:delete_session, %{role: :employee, id: user_id}, %{user_id: user_id}), do: true
  def authorize(:create_session, %{role: :employee}, _), do: true
  def authorize(_, _, _), do: false

  def list_user_projects(user_id) do
    Accounts.get_user!(user_id) |> Repo.preload(:projects) |> Map.get(:projects)
  end

  def list_user_projects_with_duration(user_id, date) do
    list_user_projects(user_id)
    |> Enum.map(fn project ->
      Map.put(
        project,
        :duration,
        get_sessions_duration_in_project(
          project.id,
          user_id,
          date.month,
          date.year
        )
      )
    end)
    |> Enum.sort_by(& &1.duration, :desc)
  end

  def list_projects() do
    Repo.all(Project)
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

  def get_project!(id), do: Repo.get!(Project, id) |> Repo.preload(:users)

  def get_project_with_users!(id), do: Repo.get!(Project, id) |> Repo.preload(:users)

  def get_month_summary_by_project(project_id, month, year) do
    summed_sessions =
      from s in Session,
        where:
          s.project_id == ^project_id and
            (is_nil(s.start_datetime) or
               (fragment("extract(month from ?) = ?", s.start_datetime, ^month) and
                  fragment("extract(year from ?) = ?", s.start_datetime, ^year))),
        group_by: [s.user_id],
        select: %{
          user_id: s.user_id,
          time_worked:
            fragment(
              "extract(epoch from coalesce(?, now()) - ?)",
              s.end_datetime,
              s.start_datetime
            )
            |> sum()
        }

    query =
      from u in Accounts.User,
        left_join: pu in ProjectUser,
        on: u.id == pu.user_id and pu.project_id == ^project_id,
        left_join: s_summary in subquery(summed_sessions),
        on: u.id == s_summary.user_id,
        # Include user if they are currently assigned to the project OR have sessions for this project in the given month/year
        where: not is_nil(pu.id) or not is_nil(s_summary.user_id),
        order_by: [desc: u.name, desc: u.email],
        select: {
          u,
          coalesce(s_summary.time_worked, 0)
          |> type(:integer)
        }

    Repo.all(query)
  end

  def get_sessions_duration_in_project(project_id, user_id, month, year) do
    sessions =
      Session
      |> where([s], s.project_id == ^project_id and s.user_id == ^user_id)
      |> where([s], fragment("extract(month from ?) = ?", s.start_datetime, ^month))
      |> where([s], fragment("extract(year from ?) = ?", s.start_datetime, ^year))
      |> Repo.all()
      |> Enum.map(&Session.put_duration/1)

    Enum.reduce(sessions, 0, fn s, acc -> acc + s.duration end)
  end

  def query_months_with_sessions() do
    Session
    |> select([s], %{
      date: fragment("date_trunc('month', ?)", s.start_datetime)
    })
    |> distinct([s], [
      fragment("date_trunc('month', ?)", s.start_datetime)
    ])
    |> order_by([s],
      desc: fragment("date_trunc('month', ?)", s.start_datetime)
    )
  end

  def get_months_with_sessions do
    query_months_with_sessions()
    |> Repo.all()
    |> Enum.map(& &1.date)
  end

  def get_months_with_sessions(user_id) do
    query_months_with_sessions()
    |> where([s], s.user_id == ^user_id)
    |> Repo.all()
    |> Enum.map(& &1.date)
  end

  def get_months_with_sessions_by_project(project_id) do
    query_months_with_sessions()
    |> where([s], s.project_id == ^project_id)
    |> Repo.all()
    |> Enum.map(& &1.date)
  end

  def get_sessions_duration_in_month(user_id, date) do
    sessions =
      Session
      |> where([s], s.user_id == ^user_id)
      |> where([s], fragment("extract(month from ?) = ?", s.start_datetime, ^date.month))
      |> where([s], fragment("extract(year from ?) = ?", s.start_datetime, ^date.year))
      |> Repo.all()
      |> Enum.map(&Session.put_duration/1)

    Enum.reduce(sessions, 0, fn s, acc -> acc + s.duration end)
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

  @doc """
  Sets users to project. If user isn't in `user_ids` list, it will be removed from project.
  """
  def set_users_to_project(project, user_ids) do
    project = Repo.preload(project, :project_users)

    users_to_add =
      user_ids
      # removes users that are already in project
      |> Enum.reject(fn user_id ->
        Enum.any?(project.project_users, fn pu ->
          pu.user_id == user_id
        end)
      end)
      |> Enum.map(&%ProjectUser{user_id: &1, project_id: project.id})
      |> Enum.map(&ProjectUser.changeset/1)

    project_users =
      project.project_users
      |> Enum.filter(fn pu -> pu.user_id in user_ids end)
      |> Enum.map(&Ecto.Changeset.change/1)
      |> Kernel.++(users_to_add)

    project
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.put_assoc(:project_users, project_users)
    |> Repo.update()
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

  @doc """
  Gets all sessions for a specific user in a specific project.
  """
  def get_user_project_sessions(user_id, project_id) do
    Repo.all(
      from s in Session,
        where: s.user_id == ^user_id and s.project_id == ^project_id
    )
  end

  alias Firmowid.Timetracker.HoursRecord

  @doc """
  Returns the list of hours_records.

  ## Examples

      iex> list_hours_records()
      [%HoursRecord{}, ...]

  """
  def list_hours_records do
    Repo.all(HoursRecord) |> Repo.preload(:user)
  end

  @doc """
  Gets a single hours_record.

  Raises `Ecto.NoResultsError` if the Hours record does not exist.

  ## Examples

      iex> get_hours_record!(123)
      %HoursRecord{}

      iex> get_hours_record!(456)
      ** (Ecto.NoResultsError)

  """
  def get_hours_record!(id), do: Repo.get!(HoursRecord, id) |> Repo.preload(:user)

  @doc """
  Creates a hours_record.

  ## Examples

      iex> create_hours_record(%{field: value})
      {:ok, %HoursRecord{}}

      iex> create_hours_record(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_hours_record(attrs, path, filename) do
    Repo.transaction(fn ->
      with {:ok, blob} <- Blobs.create_blob(path, "binary/octet-stream", filename),
           {:ok, hours_record} <-
             %HoursRecord{}
             |> HoursRecord.changeset(
               Map.merge(attrs, %{
                 blob_id: blob.id
               })
             )
             |> Repo.insert() do
        hours_record
      else
        {:error, reason} ->
          Logger.error("Failed to upload hours record: #{inspect(reason)}")
          Repo.rollback(reason)
      end
    end)
  end

  def get_hours_record_by_month(user_id, date) do
    HoursRecord
    |> where([hr], hr.user_id == ^user_id)
    |> where([hr], hr.month == ^date.month and hr.year == ^date.year)
    |> Repo.one()
  end

  @doc """
  Updates a hours_record.

  ## Examples

      iex> update_hours_record(hours_record, %{field: new_value})
      {:ok, %HoursRecord{}}

      iex> update_hours_record(hours_record, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_hours_record(%HoursRecord{} = hours_record, attrs) do
    hours_record
    |> HoursRecord.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a hours_record.

  ## Examples

      iex> delete_hours_record(hours_record)
      {:ok, %HoursRecord{}}

      iex> delete_hours_record(hours_record)
      {:error, %Ecto.Changeset{}}

  """
  def delete_hours_record(%HoursRecord{} = hours_record) do
    Repo.delete(hours_record)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking hours_record changes.

  ## Examples

      iex> change_hours_record(hours_record)
      %Ecto.Changeset{data: %HoursRecord{}}

  """
  def change_hours_record(%HoursRecord{} = hours_record, attrs \\ %{}) do
    HoursRecord.changeset(hours_record, attrs)
  end
end
