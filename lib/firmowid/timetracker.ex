defmodule Firmowid.Timetracker do
  @moduledoc """
  The Czasosledź (timetracker) context.
  """
  @behaviour Bodyguard.Policy

  import Ecto.Query, warn: false
  import Paradex, only: [~>: 2]

  alias Ecto.Multi
  alias Firmowid.Accounts
  alias Firmowid.Analysis
  alias Firmowid.Blobs
  alias Firmowid.Helpers.TimeConverter
  alias Firmowid.Repo
  alias Firmowid.Timetracker.HoursRecord
  alias Firmowid.Timetracker.Project
  alias Firmowid.Timetracker.ProjectUser
  alias Firmowid.Timetracker.Session
  alias Firmowid.Timetracker.UserSalary
  alias Timex.Duration

  require Logger

  def authorize(:read_projects, %{role: :admin}, _), do: true
  def authorize(:create_project, %{role: :admin}, _), do: true
  def authorize(:read_hours_records, %{role: :admin}, _), do: true
  def authorize(:create_user_salary, %{role: :admin}, _), do: true
  def authorize(:delete_project, %{role: :admin}, _), do: true

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

  def list_user_active_projects(user_id) do
    query =
      from p in Project,
        join: pu in ProjectUser,
        on: p.id == pu.project_id,
        where: pu.user_id == ^user_id,
        where: is_nil(p.archived_at),
        order_by: p.name,
        select: p

    Repo.all(query)
  end

  def list_projects_by_ids(ids) when is_list(ids) do
    ids = ids |> Enum.uniq() |> Enum.reject(&is_nil/1)

    if ids == [] do
      []
    else
      Project
      |> where([p], p.id in ^ids)
      |> Repo.all()
    end
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
    Project
    |> preload(:counterparty)
    |> Repo.all()
  end

  def list_active_projects(%Date{} = date), do: list_active_projects(date, "")
  def list_active_projects(%Date{} = date, nil), do: list_active_projects(date, "")

  def list_active_projects(%Date{} = date, "") do
    session_duration_query =
      from s in Session,
        where:
          fragment("extract(month from ?) = ?", s.start_datetime, ^date.month) and
            fragment("extract(year from ?) = ?", s.start_datetime, ^date.year),
        group_by: s.project_id,
        select: %{
          project_id: s.project_id,
          duration:
            "extract(epoch from coalesce(?, now()) - ?)"
            |> fragment(s.end_datetime, s.start_datetime)
            |> sum()
            |> coalesce(0)
            |> type(:integer)
        }

    query =
      from p in Project,
        where: is_nil(p.archived_at),
        left_join: sd in subquery(session_duration_query),
        on: p.id == sd.project_id,
        select: %{p | hours: sd.duration |> coalesce(0) |> type(:integer)},
        order_by: p.name

    query
    |> Repo.all()
    |> Enum.map(fn project ->
      hours = (project.hours / 3600) |> Float.ceil() |> trunc()
      %{project | hours: hours}
    end)
  end

  def list_active_projects(%Date{} = date, search) when is_binary(search) do
    session_duration_query =
      from s in Session,
        where:
          fragment("extract(month from ?) = ?", s.start_datetime, ^date.month) and
            fragment("extract(year from ?) = ?", s.start_datetime, ^date.year),
        group_by: s.project_id,
        select: %{
          project_id: s.project_id,
          duration:
            "extract(epoch from coalesce(?, now()) - ?)"
            |> fragment(s.end_datetime, s.start_datetime)
            |> sum()
            |> coalesce(0)
            |> type(:integer)
        }

    query =
      from p in Project,
        where: is_nil(p.archived_at),
        left_join: sd in subquery(session_duration_query),
        on: p.id == sd.project_id,
        where: p.name ~> ^search,
        select: %{p | hours: sd.duration |> coalesce(0) |> type(:integer)},
        order_by: fragment("paradedb.score(?) DESC", p.id)

    query
    |> Repo.all(prepare: :unnamed)
    |> Enum.map(fn project ->
      hours = (project.hours / 3600) |> Float.ceil() |> trunc()
      %{project | hours: hours}
    end)
  end

  def list_archived_projects(%Date{} = date), do: list_archived_projects(date, "")
  def list_archived_projects(%Date{} = date, nil), do: list_archived_projects(date, "")

  def list_archived_projects(%Date{} = date, "") do
    session_duration_query =
      from s in Session,
        where:
          fragment("extract(month from ?) = ?", s.start_datetime, ^date.month) and
            fragment("extract(year from ?) = ?", s.start_datetime, ^date.year),
        group_by: s.project_id,
        select: %{
          project_id: s.project_id,
          duration:
            "extract(epoch from coalesce(?, now()) - ?)"
            |> fragment(s.end_datetime, s.start_datetime)
            |> sum()
            |> coalesce(0)
            |> type(:integer)
        }

    query =
      from p in Project,
        where: not is_nil(p.archived_at),
        left_join: sd in subquery(session_duration_query),
        on: p.id == sd.project_id,
        select: %{p | hours: sd.duration |> coalesce(0) |> type(:integer)},
        order_by: p.name

    query
    |> Repo.all()
    |> Enum.map(fn project ->
      hours = (project.hours / 3600) |> Float.ceil() |> trunc()
      %{project | hours: hours}
    end)
  end

  def list_archived_projects(%Date{} = date, search) when is_binary(search) do
    session_duration_query =
      from s in Session,
        where:
          fragment("extract(month from ?) = ?", s.start_datetime, ^date.month) and
            fragment("extract(year from ?) = ?", s.start_datetime, ^date.year),
        group_by: s.project_id,
        select: %{
          project_id: s.project_id,
          duration:
            "extract(epoch from coalesce(?, now()) - ?)"
            |> fragment(s.end_datetime, s.start_datetime)
            |> sum()
            |> coalesce(0)
            |> type(:integer)
        }

    query =
      from p in Project,
        where: not is_nil(p.archived_at),
        left_join: sd in subquery(session_duration_query),
        on: p.id == sd.project_id,
        where: p.name ~> ^search,
        select: %{p | hours: sd.duration |> coalesce(0) |> type(:integer)},
        order_by: fragment("paradedb.score(?) DESC", p.id)

    query
    |> Repo.all(prepare: :unnamed)
    |> Enum.map(fn project ->
      hours = (project.hours / 3600) |> Float.ceil() |> trunc()
      %{project | hours: hours}
    end)
  end

  def list_archived_projects_total, do: list_archived_projects_total("")
  def list_archived_projects_total(nil), do: list_archived_projects_total("")

  def list_archived_projects_total("") do
    session_duration_query =
      from s in Session,
        group_by: s.project_id,
        select: %{
          project_id: s.project_id,
          duration:
            "extract(epoch from coalesce(?, now()) - ?)"
            |> fragment(s.end_datetime, s.start_datetime)
            |> sum()
            |> coalesce(0)
            |> type(:integer)
        }

    query =
      from p in Project,
        where: not is_nil(p.archived_at),
        left_join: sd in subquery(session_duration_query),
        on: p.id == sd.project_id,
        select: %{p | hours: sd.duration |> coalesce(0) |> type(:integer)},
        order_by: p.name

    query
    |> Repo.all()
    |> Enum.map(fn project ->
      hours = (project.hours / 3600) |> Float.ceil() |> trunc()
      %{project | hours: hours}
    end)
  end

  def list_archived_projects_total(search) when is_binary(search) do
    session_duration_query =
      from s in Session,
        group_by: s.project_id,
        select: %{
          project_id: s.project_id,
          duration:
            "extract(epoch from coalesce(?, now()) - ?)"
            |> fragment(s.end_datetime, s.start_datetime)
            |> sum()
            |> coalesce(0)
            |> type(:integer)
        }

    query =
      from p in Project,
        where: not is_nil(p.archived_at),
        left_join: sd in subquery(session_duration_query),
        on: p.id == sd.project_id,
        where: p.name ~> ^search,
        select: %{p | hours: sd.duration |> coalesce(0) |> type(:integer)},
        order_by: fragment("paradedb.score(?) DESC", p.id)

    query
    |> Repo.all(prepare: :unnamed)
    |> Enum.map(fn project ->
      hours = (project.hours / 3600) |> Float.ceil() |> trunc()
      %{project | hours: hours}
    end)
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

  @doc """
  Creates a project together with its analysis tag definition.

  A `TagDefinition` is automatically created via `Analysis.create_project_tag/1`
  with a rotating color, then linked to the project via `tag_definition_id`.
  """
  def create_project(attrs \\ %{}) do
    name = attrs["name"] || attrs[:name] || ""

    Multi.new()
    |> Multi.run(:tag_definition, fn _repo, _changes ->
      Analysis.create_project_tag(name)
    end)
    |> Multi.insert(:project, fn %{tag_definition: tag_def} ->
      attrs = Map.new(attrs, fn {k, v} -> {to_string(k), v} end)
      Project.changeset(%Project{}, Map.put(attrs, "tag_definition_id", tag_def.id))
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{project: project}} -> {:ok, project}
      {:error, :project, changeset, _changes} -> {:error, changeset}
      {:error, :tag_definition, changeset, _changes} -> {:error, changeset}
    end
  end

  @doc """
  Updates a project and atomically syncs the associated tag definition name.
  """
  def update_project(%Project{} = project, attrs) do
    Multi.new()
    |> Multi.update(:project, Project.changeset(project, attrs))
    |> Multi.run(:sync_tag_name, fn _repo, %{project: updated} ->
      Analysis.sync_project_tag_name(updated.tag_definition_id, updated.name)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{project: project}} -> {:ok, project}
      {:error, :project, changeset, _changes} -> {:error, changeset}
      {:error, :sync_tag_name, reason, _changes} -> {:error, reason}
    end
  end

  @doc """
  Deletes a project and atomically cleans up its orphaned tag definition.
  """
  def delete_project(%Project{} = project) do
    Multi.new()
    |> Multi.delete(:project, project)
    |> Multi.run(:cleanup_tag, fn _repo, _changes ->
      Analysis.delete_tag_definition_by_id(project.tag_definition_id)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{project: project}} -> {:ok, project}
      {:error, :project, changeset, _changes} -> {:error, changeset}
      {:error, :cleanup_tag, reason, _changes} -> {:error, reason}
    end
  end

  def archive_project(%Project{} = project) do
    project
    |> Ecto.Changeset.change(archived_at: Date.utc_today())
    |> Repo.update()
  end

  def unarchive_project(%Project{} = project) do
    project
    |> Ecto.Changeset.change(archived_at: nil)
    |> Repo.update()
  end

  def get_project(id), do: Project |> Repo.get(id) |> Repo.preload([:users, :counterparty])

  def get_project!(id), do: Project |> Repo.get!(id) |> Repo.preload([:users, :counterparty])

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
        left_join: hr in HoursRecord,
        on:
          u.id == hr.user_id and
            hr.month == ^month and
            hr.year == ^year,
        # Include user if they are currently assigned to the project OR have sessions for this project in the given month/year
        where: not is_nil(pu.id) or not is_nil(s.user_id),
        order_by: [u.name, u.email],
        select: %{
          user: u,
          time_worked: s.time_worked |> coalesce(0) |> type(:integer),
          removed_from_project: is_nil(pu.id),
          hours_record: hr
        }

    Repo.all(query)
  end

  @doc """
  Returns per-user time and cost (based on hourly rate active at month end)
  for a project's selected month.
  """
  @spec get_project_month_users_with_cost(String.t(), Date.t()) :: list(map())
  def get_project_month_users_with_cost(project_id, %Date{} = date) do
    as_of_date = Date.end_of_month(date)

    project_id
    |> get_month_summary_by_project(date.month, date.year)
    |> Enum.map(fn %{user: u, time_worked: t, removed_from_project: r, hours_record: hr} ->
      salary = get_user_salary_as_of(u.id, as_of_date)
      hourly_rate = salary && salary.hourly_rate
      hours = TimeConverter.time_worked_in_seconds_to_hours(t)
      cost = hourly_rate && Decimal.mult(hourly_rate, Decimal.new(hours))

      u
      |> Accounts.get_user_with_avatar()
      |> Map.put(:time_worked, t)
      |> Map.put(:removed_from_project, r)
      |> Map.put(:expanded, false)
      |> Map.put(:hours_record, hr)
      |> Map.put(:salary, salary)
      |> Map.put(:hourly_rate, hourly_rate)
      |> Map.put(:cost, cost)
    end)
    |> Enum.sort_by(&{&1.removed_from_project, &1.name, &1.email})
  end

  defp project_total_time_worked_query(project_id) do
    Session
    |> where([s], s.project_id == ^project_id)
    |> select(
      [s],
      "extract(epoch from coalesce(?, now()) - ?)"
      |> fragment(s.end_datetime, s.start_datetime)
      |> sum()
      |> coalesce(0)
      |> type(:integer)
    )
  end

  @doc """
  Returns total worked seconds for a project in a given month.
  """
  @spec get_project_total_time_worked(String.t(), Date.t()) :: non_neg_integer()
  def get_project_total_time_worked(project_id, %Date{} = date) do
    project_id
    |> project_total_time_worked_query()
    |> where(
      [s],
      fragment("extract(month from ?) = ?", s.start_datetime, ^date.month) and
        fragment("extract(year from ?) = ?", s.start_datetime, ^date.year)
    )
    |> Repo.one()
  end

  @doc """
  Returns total worked seconds for a project across all time.
  """
  @spec get_project_total_time_worked_all_time(String.t()) :: non_neg_integer()
  def get_project_total_time_worked_all_time(project_id) do
    project_id
    |> project_total_time_worked_query()
    |> Repo.one()
  end

  @doc """
  Returns total cost of work for a project in a given month.

  Uses hourly rates active at month end and rounds worked time per-user up to full hours.
  Returns nil when no active hourly rates exist for the month.
  """
  @spec get_project_total_cost(String.t(), Date.t()) :: Decimal.t() | nil
  def get_project_total_cost(project_id, %Date{} = date) do
    organization_id = Repo.get_org_id()

    latest_salary_as_of_query =
      date
      |> user_salaries_as_of_query()
      |> select([us], %{user_id: us.user_id, hourly_rate: us.hourly_rate})

    session_summary =
      from s in Session,
        where:
          s.project_id == ^project_id and
            s.organization_id == ^organization_id and
            fragment("extract(month from ?) = ?", s.start_datetime, ^date.month) and
            fragment("extract(year from ?) = ?", s.start_datetime, ^date.year),
        group_by: s.user_id,
        select: %{
          user_id: s.user_id,
          time_worked:
            "extract(epoch from coalesce(?, now()) - ?)"
            |> fragment(s.end_datetime, s.start_datetime)
            |> sum()
            |> coalesce(0)
            |> type(:integer)
        }

    query =
      from ss in subquery(session_summary),
        join: us in subquery(latest_salary_as_of_query),
        on: us.user_id == ss.user_id,
        select:
          "? * ceil(? / 3600.0)"
          |> fragment(us.hourly_rate, ss.time_worked)
          |> sum()
          |> type(:decimal)

    # Repo enforces tenant scoping by injecting `where: organization_id == ^...`.
    # For queries selecting from a subquery, that injected where cannot be applied.
    # We scope the underlying tables explicitly and opt out of repo-level scoping here.
    Repo.one(query, skip_organization_id: true)
  end

  @doc """
  Returns total cost of work for a project across all time.

  The total is calculated month-by-month using hourly rates active at each
  month end and rounds worked time per-user up to full hours.

  Returns nil when no active hourly rates exist for any month.
  """
  @spec get_project_total_cost_all_time(String.t()) :: Decimal.t() | nil
  def get_project_total_cost_all_time(project_id) do
    project_id
    |> get_months_with_sessions_by_project()
    |> Enum.map(&month_value_to_date/1)
    |> Enum.reduce(nil, fn month_date, acc ->
      month_cost = get_project_total_cost(project_id, month_date)

      case {acc, month_cost} do
        {nil, nil} -> nil
        {nil, month_cost} -> month_cost
        {acc, nil} -> acc
        {acc, month_cost} -> Decimal.add(acc, month_cost)
      end
    end)
  end

  @doc """
  Returns per-user time and cost across all time for a project.

  Cost is calculated month-by-month using hourly rates active at each month end
  and rounds worked time per-user up to full hours (same semantics as the
  monthly totals).
  """
  @spec get_project_users_with_cost_all_time(String.t()) :: list(map())
  def get_project_users_with_cost_all_time(project_id) do
    project_id
    |> get_months_with_sessions_by_project()
    |> Enum.map(&month_value_to_date/1)
    |> Enum.reduce(%{}, fn month_date, acc ->
      project_id
      |> get_project_month_users_with_cost(month_date)
      |> Enum.reduce(acc, fn user, users_acc ->
        Map.update(users_acc, user.id, all_time_user_from_month(user), fn existing ->
          merge_all_time_user(existing, user)
        end)
      end)
    end)
    |> Map.values()
    |> Enum.sort_by(&{&1.removed_from_project, &1.name, &1.email})
  end

  defp all_time_user_from_month(user) do
    user
    |> Map.put(:expanded, false)
    |> Map.put(:hourly_rate, nil)
    |> Map.put(:salary, nil)
    |> Map.put(:hours_record, nil)
  end

  defp merge_all_time_user(existing, month_user) do
    cost =
      case {existing.cost, month_user.cost} do
        {nil, nil} -> nil
        {nil, month_cost} -> month_cost
        {existing_cost, nil} -> existing_cost
        {existing_cost, month_cost} -> Decimal.add(existing_cost, month_cost)
      end

    existing
    |> Map.put(:time_worked, existing.time_worked + month_user.time_worked)
    |> Map.put(:cost, cost)
    |> Map.put(:expanded, false)
  end

  defp month_value_to_date(%Date{} = date), do: Date.beginning_of_month(date)

  defp month_value_to_date(%NaiveDateTime{} = dt), do: dt |> NaiveDateTime.to_date() |> Date.beginning_of_month()

  defp month_value_to_date(%DateTime{} = dt), do: dt |> DateTime.to_date() |> Date.beginning_of_month()

  def get_project_users_with_removed(project_id) do
    session_users_query =
      from s in Session,
        where: s.project_id == ^project_id and s.user_id == parent_as(:user).id,
        select: 1

    query =
      from u in Accounts.User,
        as: :user,
        left_join: pu in ProjectUser,
        on: u.id == pu.user_id and pu.project_id == ^project_id,
        where: exists(session_users_query) or not is_nil(pu.id),
        order_by: [u.name, u.email],
        select: merge(u, %{removed_from_project: is_nil(pu.id)})

    Repo.all(query)
  end

  def get_project_users_with_sessions(project_id) do
    users = get_project_users_with_removed(project_id)
    user_ids = Enum.map(users, & &1.id)

    sessions_grouped =
      from(s in Session,
        where: s.project_id == ^project_id and s.user_id in ^user_ids
      )
      |> Repo.all()
      |> Enum.map(&Session.put_duration/1)
      |> Enum.group_by(& &1.user_id)

    Enum.map(users, fn user ->
      time_worked =
        sessions_grouped
        |> Map.get(user.id, [])
        |> Enum.reduce(0, fn s, acc -> acc + (s.duration || 0) end)

      %{
        user: user,
        removed_from_project: user.removed_from_project,
        time_worked: time_worked,
        sessions: Map.get(sessions_grouped, user.id, [])
      }
    end)
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

  def get_salaries_csv(month, year) do
    as_of_date =
      year
      |> Date.new!(month, 1)
      |> Date.end_of_month()

    as_of_end_dt = DateTime.new!(as_of_date, ~T[23:59:59], "Etc/UTC")

    latest_salary_as_of_query =
      UserSalary
      |> where([us], us.updated_at <= ^as_of_end_dt)
      |> where([us], is_nil(us.deleted_at) or us.deleted_at > ^as_of_date)
      |> order_by([us], asc: us.user_id, desc: us.updated_at)
      |> distinct([us], us.user_id)
      |> select([us], %{user_id: us.user_id, hourly_rate: us.hourly_rate})

    from(u in Accounts.User,
      left_join: us in subquery(latest_salary_as_of_query),
      on: us.user_id == u.id,
      join: hr in HoursRecord,
      on: hr.user_id == u.id and hr.month == ^month and hr.year == ^year,
      order_by: u.name,
      select: %{
        name: u.name,
        hourly_rate: us.hourly_rate,
        number_of_hours: hr.number_of_hours,
        salary:
          "? * ?"
          |> fragment(us.hourly_rate, hr.number_of_hours)
          |> coalesce(0)
          |> type(:decimal)
          |> selected_as(:salary)
      }
    )
    |> Repo.all()
    |> CSV.encode(
      headers: [
        name: "Imie i Nazwisko",
        hourly_rate: "Stawka godzinowa",
        number_of_hours: "Liczba godzin",
        salary: "Wynagrodzenie"
      ]
    )
    |> Enum.join()
  end

  def get_project_tasks_csv(project_id, month, year) do
    from(s in Session,
      where:
        s.project_id == ^project_id and
          fragment("extract(month from ?) = ?", s.start_datetime, ^month) and
          fragment("extract(year from ?) = ?", s.start_datetime, ^year),
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
    |> Repo.all()
    |> Enum.map(fn task ->
      duration =
        task.duration
        |> Duration.from_seconds()
        |> Duration.to_hours()
        |> ceil()

      %{task | duration: duration}
    end)
    |> CSV.encode(headers: [title: "Zadanie", duration: "Czas trwania (godziny)"])
    |> Enum.join()
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

  def weeks_with_user_sessions(user_id, opts \\ []) do
    after_date = Keyword.get(opts, :after_date)
    limit = Keyword.get(opts, :limit)
    timezone = Keyword.get(opts, :timezone, "Etc/UTC")

    query =
      Session
      |> where([s], s.user_id == ^user_id)
      |> select([s], fragment("date_trunc('week', ?)", s.start_datetime))
      |> distinct([s], true)
      |> order_by([s], desc: fragment("date_trunc('week', ?)", s.start_datetime))

    query =
      case after_date do
        nil -> query
        _ -> where(query, [s], s.start_datetime < ^DateTime.new!(after_date, ~T[00:00:00]))
      end

    query =
      case limit do
        nil -> query
        _ -> limit(query, ^limit)
      end

    query
    |> Repo.all()
    |> Enum.map(fn date ->
      date
      |> DateTime.from_naive!("Etc/UTC")
      |> DateTime.shift_zone!(timezone)
      |> DateTime.to_date()
    end)
  end

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

  def get_current_session(user_id) do
    Session
    |> where([s], s.user_id == ^user_id and is_nil(s.end_datetime))
    |> order_by([s], desc: s.start_datetime)
    |> limit(1)
    |> Repo.one()
    |> Session.put_duration()
  end

  def list_sessions_by_ids(ids) do
    Session
    |> where([s], s.id in ^ids)
    |> Repo.all()
    |> Enum.map(&Session.put_duration/1)
  end

  def update_session(session, attrs) do
    session
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

  def update_sessions(changesets) do
    changesets
    |> Enum.reduce(Multi.new(), fn changeset, multi ->
      Multi.update(multi, changeset.data.id, changeset)
    end)
    |> Repo.transact()
  rescue
    e in Postgrex.Error ->
      if e.postgres.message =~ "overlaps" do
        {:error, :overlap}
      else
        reraise e, __STACKTRACE__
      end
  end

  def get_user_project_sessions(user_id, project_id) do
    Repo.all(
      from s in Session,
        where: s.user_id == ^user_id and s.project_id == ^project_id
    )
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
  Returns the user salary that was active on the given date.

  The lookup uses the salary update timestamp to find the latest change
  on or before the end of the month and ensures the salary was not deleted yet.
  """
  @spec get_user_salary_as_of(String.t() | integer(), Date.t()) :: UserSalary.t() | nil
  def get_user_salary_as_of(user_id, date) do
    org_id = Repo.get_org_id()

    date
    |> user_salaries_as_of_query()
    |> where([us], us.user_id == ^user_id and us.organization_id == ^org_id)
    |> Repo.one()
  end

  def user_salaries_as_of_query(%Date{} = date) do
    # lookup salaries as of last day of a month
    as_of_date = Date.end_of_month(date)
    as_of_end_dt = DateTime.new!(as_of_date, ~T[23:59:59], "Etc/UTC")

    UserSalary
    |> where([us], us.updated_at <= ^as_of_end_dt)
    |> where([us], is_nil(us.deleted_at) or us.deleted_at > ^as_of_date)
    |> order_by([us], asc: us.user_id, desc_nulls_first: us.deleted_at)
    |> distinct([us], us.user_id)
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
