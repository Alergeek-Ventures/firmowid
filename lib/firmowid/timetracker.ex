defmodule Firmowid.Timetracker do
  @moduledoc """
  The Czasosledź (timetracker) context.
  """
  @behaviour Bodyguard.Policy

  import Ecto.Query, warn: false

  alias Firmowid.Accounts
  alias Firmowid.Blobs
  alias Firmowid.Repo
  alias Firmowid.Timetracker.HoursRecord
  alias Firmowid.Timetracker.Project
  alias Firmowid.Timetracker.ProjectUser
  alias Firmowid.Timetracker.Session
  alias Firmowid.Timetracker.UserSalary

  require Logger

  def authorize(:read_projects, %{role: :admin}, _), do: true
  def authorize(:create_project, %{role: :admin}, _), do: true
  def authorize(:read_hours_records, %{role: :admin}, _), do: true
  def authorize(:create_user_salary, %{role: :admin}, _), do: true

  def authorize(:update_project, %{role: :admin, organization_id: org_id}, %{organization_id: org_id}), do: true

  def authorize(action, %{role: role}, _)
      when role in [:employee, :admin] and
             action in [:create_hours_record, :read_user_hours_records, :read_user_projects, :read_user_sessions],
      do: true

  def authorize(:update_session, %{role: role, id: user_id}, %{user_id: user_id} = session)
      when role in [:employee, :admin] do
    # Ensure that user can end already running session
    session.end_datetime == nil or
      not submitted_hours_record?(user_id, session.start_datetime)
  end

  def authorize(action, %{role: role, id: user_id}, %{user_id: user_id} = session)
      when role in [:employee, :admin] and action in [:create_session, :delete_session],
      do: not submitted_hours_record?(user_id, session.start_datetime)

  def authorize(_, _, _), do: false

  def submitted_hours_record?(user_id, date) do
    query =
      from hr in HoursRecord,
        where: hr.user_id == ^user_id and hr.month == ^date.month and hr.year == ^date.year

    Repo.exists?(query)
  end

  def submitted_hours_records_multiple_dates?(user_id, dates) do
    existing =
      Repo.all(
        from(hr in HoursRecord,
          where: hr.user_id == ^user_id,
          select: {hr.month, hr.year}
        )
      )

    Enum.map(dates, fn date ->
      Enum.member?(existing, {date.month, date.year})
    end)
  end

  def list_user_projects(user_id) do
    query =
      from p in Project,
        join: pu in ProjectUser,
        on: p.id == pu.project_id,
        where: pu.user_id == ^user_id,
        select: p

    Repo.all(query)
  end

  def list_user_projects_with_duration(user_id, date) do
    user_id
    |> list_user_projects()
    |> Enum.map(fn project ->
      # wtf quering in loop
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

  def list_projects do
    Repo.all(Project)
  end

  def list_projects_with_users do
    Project
    |> Repo.all()
    |> Repo.preload(:users)
  end

  def list_users_with_projects do
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

  def get_project!(id), do: Project |> Repo.get!(id) |> Repo.preload(:users)

  def get_month_hours_records(month, year) do
    query =
      from u in Accounts.User,
        left_join: hr in HoursRecord,
        on: u.id == hr.user_id and hr.month == ^month and hr.year == ^year,
        order_by: [u.name, u.email],
        select: %{user: u, hours_record: hr}

    Repo.all(query)
  end

  def get_month_summary_by_project(project_id, month, year) do
    session_summary =
      from s in Session,
        where:
          s.project_id == ^project_id and
            fragment("extract(month from ?) = ?", s.start_datetime, ^month) and
            fragment("extract(year from ?) = ?", s.start_datetime, ^year),
        group_by: s.user_id,
        select: %{
          user_id: s.user_id,
          time_worked:
            "extract(epoch from coalesce(?, now()) - ?)"
            |> fragment(
              s.end_datetime,
              s.start_datetime
            )
            |> sum()
        }

    query =
      from u in Accounts.User,
        left_join: pu in ProjectUser,
        on: u.id == pu.user_id and pu.project_id == ^project_id,
        left_join: s in subquery(session_summary),
        on: u.id == s.user_id,
        # Include user if they are currently assigned to the project OR have sessions for this project in the given month/year
        where: not is_nil(pu.id) or not is_nil(s.user_id),
        order_by: [u.name, u.email],
        select: %{
          user: u,
          time_worked: s.time_worked |> coalesce(0) |> type(:integer),
          removed_from_project: is_nil(pu.id)
        }

    Repo.all(query)
  end

  defp query_months_with_sessions do
    Session
    |> select([s], "date_trunc('month', ?)" |> fragment(s.start_datetime) |> selected_as(:date))
    |> distinct([s], selected_as(:date))
    |> order_by([s], desc: selected_as(:date))
  end

  def get_months_with_sessions do
    Repo.all(query_months_with_sessions())
  end

  def get_months_with_sessions(user_id) do
    query_months_with_sessions()
    |> where([s], s.user_id == ^user_id)
    |> Repo.all()
  end

  def get_months_with_sessions_by_project(project_id) do
    query_months_with_sessions()
    |> where([s], s.project_id == ^project_id)
    |> Repo.all()
  end

  defp query_total_time_worked(month, year) do
    from s in Session,
      where:
        fragment("extract(month from ?) = ?", s.start_datetime, ^month) and
          fragment("extract(year from ?) = ?", s.start_datetime, ^year),
      limit: 1,
      select:
        "extract(epoch from coalesce(?, now()) - ?)"
        |> fragment(
          s.end_datetime,
          s.start_datetime
        )
        |> sum()
        |> coalesce(0)
        |> type(:integer)
        |> selected_as(:time_worked)
  end

  def get_sessions_duration_in_project(project_id, user_id, month, year) do
    month
    |> query_total_time_worked(year)
    |> where([s], s.project_id == ^project_id and s.user_id == ^user_id)
    |> Repo.one()
  end

  def get_sessions_duration_in_month(user_id, date) do
    date.month
    |> query_total_time_worked(date.year)
    |> where([s], s.user_id == ^user_id)
    |> Repo.one()
  end

  def get_total_time_worked(month, year) do
    month
    |> query_total_time_worked(year)
    |> Repo.one()
  end

  def get_most_demanding_project(month, year) do
    query =
      from s in Session,
        join: p in Project,
        on: s.project_id == p.id,
        where:
          fragment("extract(month from ?) = ?", s.start_datetime, ^month) and
            fragment("extract(year from ?) = ?", s.start_datetime, ^year),
        group_by: p.id,
        order_by: [desc: selected_as(:time_worked)],
        limit: 1,
        select: %{
          project: p,
          time_worked:
            "extract(epoch from coalesce(?, now()) - ?)"
            |> fragment(
              s.end_datetime,
              s.start_datetime
            )
            |> sum()
            |> type(:integer)
            |> selected_as(:time_worked)
        }

    Repo.one(query)
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
    |> case do
      {:ok, session} -> {:ok, Session.put_duration(session)}
      rest -> rest
    end
  rescue
    e in Postgrex.Error ->
      if e.postgres.message =~ "overlaps" do
        {:error, :overlap}
      else
        reraise e, __STACKTRACE__
      end
  end

  def end_session(%Session{} = session) do
    session
    |> Session.changeset(%{end_datetime: DateTime.utc_now()})
    |> Repo.update()
  end

  def end_session(session_id) do
    Session
    |> Repo.get(session_id)
    |> Session.changeset(%{end_datetime: DateTime.utc_now()})
    |> Repo.update()
  end

  def end_session(session_id, date) do
    Session
    |> Repo.get(session_id)
    |> Session.changeset(%{end_datetime: date})
    |> Repo.update()
  end

  def delete_session(%Session{} = session) do
    Repo.delete(session)
  end

  def delete_session(session_id) do
    Session
    |> Repo.get(session_id)
    |> Repo.delete()
  end

  def get_session(id), do: Repo.get(Session, id)

  def get_session!(id), do: Repo.get!(Session, id)

  def list_user_sessions(user_id, opts \\ []) do
    after_date = Keyword.get(opts, :after_date)

    session_query =
      Session
      |> where([s], s.user_id == ^user_id)
      |> order_by([s], desc: s.start_datetime)

    session_query =
      case after_date do
        nil ->
          session_query

        _ ->
          where(session_query, [s], s.start_datetime >= ^DateTime.new!(after_date, ~T[00:00:00]))
      end

    from(s in session_query,
      left_join: hr in HoursRecord,
      on:
        hr.user_id == s.user_id and
          hr.month == fragment("extract(month from ?)", s.start_datetime) and
          hr.year == fragment("extract(year from ?)", s.start_datetime),
      select: merge(s, %{lockdown: not is_nil(hr.id)})
    )
    |> Repo.all()
    |> Enum.map(&Session.put_duration/1)
  end

  def list_user_sessions_paginated(user_id, opts \\ []) do
    after_date = Keyword.get(opts, :after_date)
    limit = Keyword.get(opts, :limit, 20)

    session_query =
      Session
      |> where([s], s.user_id == ^user_id)
      |> order_by([s], desc: s.start_datetime)
      |> limit(^limit + 1)

    session_query =
      case after_date do
        nil ->
          session_query

        _ ->
          where(session_query, [s], s.start_datetime <= ^DateTime.new!(after_date, ~T[23:59:59]))
      end

    sessions =
      session_query
      |> Repo.all()
      |> Enum.map(&Session.put_duration/1)

    next_date =
      if length(sessions) > limit do
        DateTime.to_date(List.last(sessions).start_datetime)
      end

    {Enum.take(sessions, limit), next_date}
  end

  def count_user_sessions(user_id) do
    Session
    |> where([s], s.user_id == ^user_id)
    |> select([s], count(s.id))
    |> Repo.one()
  end

  def get_current_session(user_id) do
    Session
    |> where([s], s.user_id == ^user_id and is_nil(s.end_datetime))
    |> order_by([s], desc: s.start_datetime)
    |> limit(1)
    |> Repo.one()
    |> Session.put_duration()
  end

  def update_session(session_id, attrs) do
    Session
    |> Repo.get(session_id)
    |> Session.changeset(attrs)
    |> Repo.update()
  rescue
    e in Postgrex.Error ->
      if e.postgres.message =~ "overlaps" do
        {:error, :overlap}
      else
        reraise e, __STACKTRACE__
      end
  end

  def get_grouped_user_project_sessions(user_id, project_id, date) do
    Repo.all(
      from s in Session,
        where:
          s.user_id == ^user_id and s.project_id == ^project_id and
            fragment("extract(month from ?) = ?", s.start_datetime, ^date.month) and
            fragment("extract(year from ?) = ?", s.start_datetime, ^date.year),
        group_by: s.title,
        order_by: [desc: selected_as(:time_worked)],
        select: %{
          title: s.title,
          duration:
            "extract(epoch from coalesce(?, now()) - ?)"
            |> fragment(
              s.end_datetime,
              s.start_datetime
            )
            |> sum()
            |> type(:integer)
            |> selected_as(:time_worked)
        }
    )
  end

  def get_most_recent_session(user_id) do
    Repo.one(
      from s in Session,
        where: s.user_id == ^user_id,
        order_by: [desc: s.start_datetime],
        limit: 1
    )
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
  def get_hours_record!(id), do: HoursRecord |> Repo.get!(id) |> Repo.preload(:user)

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
             |> HoursRecord.changeset(Map.put(attrs, :blob_id, blob.id))
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

  def get_latest_user_salary(user_id) do
    UserSalary
    |> where([us], us.user_id == ^user_id and is_nil(us.deleted_at))
    |> Repo.one()
  end

  @doc """
  Gets the complete salary history for a user, sorted from most recent to oldest.

  For salaries on the same day, uses updated_at timestamp for precise ordering.
  This provides a complete audit trail of all salary changes.

  ## Examples

      iex> get_salary_history(user_id)
      [
        %UserSalary{hourly_rate: #Decimal<50.00>, deleted_at: nil, updated_at: ~U[2025-01-16 14:30:00Z]},
        %UserSalary{hourly_rate: #Decimal<45.00>, deleted_at: ~D[2025-01-16], updated_at: ~U[2025-01-16 14:25:00Z]},
        %UserSalary{hourly_rate: #Decimal<40.00>, deleted_at: ~D[2025-01-10], updated_at: ~U[2025-01-10 09:15:00Z]}
      ]
  """
  def get_salary_history(user_id) do
    UserSalary
    |> where([us], us.user_id == ^user_id)
    |> order_by([us],
      asc: fragment("CASE WHEN ? IS NULL THEN 0 ELSE 1 END", us.deleted_at),
      desc: us.deleted_at,
      desc: us.updated_at
    )
    |> Repo.all()
  end

  def create_user_salary(attrs \\ %{}) do
    user_id = Map.get(attrs, :user_id) || Map.get(attrs, "user_id")

    Repo.transaction(fn ->
      # First, mark the current active salary as deleted if it exists
      case get_latest_user_salary(user_id) do
        nil ->
          # no existing salary - proceed with creation
          :ok

        existing_salary ->
          # mark existing salary as deleted
          case update_user_salary(existing_salary, %{deleted_at: Date.utc_today()}) do
            {:ok, _} -> :ok
            {:error, changeset} -> Repo.rollback(changeset)
          end
      end

      # then create new salary record with deleted_at as NULL
      case %UserSalary{}
           |> UserSalary.changeset(attrs)
           |> Repo.insert() do
        {:ok, salary} -> salary
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  def update_user_salary(%UserSalary{} = user_salary, attrs) do
    user_salary
    |> UserSalary.changeset(attrs)
    |> Repo.update()
  end
end
