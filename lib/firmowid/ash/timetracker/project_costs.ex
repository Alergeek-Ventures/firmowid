defmodule Firmowid.Ash.Timetracker.ProjectCosts do
  @moduledoc """
  Raw-Ecto cost and reporting queries for projects.

  Extracted from `Firmowid.Ash.Timetracker.Project` to keep the resource
  module focused on Ash DSL declarations. These helpers use raw Ecto because
  the cross-domain joins (sessions × salaries × users) and temporal
  `DISTINCT ON` salary lookups have no Ash equivalent yet.

  All functions that touch the database scope by `organization_id` — either
  explicitly via `Repo.get_org_id()` or through `Repo.prepare_query/3`.
  """

  import Ecto.Query

  alias Firmowid.Ash.Core.User
  alias Firmowid.Ash.Payroll.UserSalary
  alias Firmowid.Ash.Timetracker.ProjectUser
  alias Firmowid.Ash.Timetracker.Session

  require Ash.Query

  @doc """
  Total cost of work for a project in a given month.

  Cross-joins session time (grouped by user) with the temporal salary
  subquery, rounds each user's hours up, and sums. Returns `nil` when no
  matching data exists.
  """
  @spec compute_project_total_cost(Ash.UUID.t(), Date.t()) :: Decimal.t() | nil
  def compute_project_total_cost(project_id, %Date{} = date) do
    organization_id = Firmowid.Repo.get_org_id()

    session_summary =
      from(s in Session,
        where:
          s.project_id == ^project_id and
            s.organization_id == ^organization_id and
            fragment("extract(month from ?) = ?", s.start_datetime, ^date.month) and
            fragment("extract(year from ?) = ?", s.start_datetime, ^date.year),
        group_by: s.user_id,
        select: %{
          user_id: s.user_id,
          time_worked:
            fragment(
              "SUM(EXTRACT(EPOCH FROM COALESCE(?, NOW()) - ?))::integer",
              s.end_datetime,
              s.start_datetime
            )
        }
      )

    # TODO: replace raw Ecto with Ash action when cross-domain aggregation
    # (sessions × salaries) and temporal DISTINCT ON salary lookups are supported.
    Firmowid.Repo.one(
      from(ss in subquery(session_summary),
        join: us in subquery(UserSalary.salary_as_of_subquery(date, organization_id)),
        on: us.user_id == ss.user_id,
        select: fragment("SUM(? * CEIL(? / 3600.0))::numeric", us.hourly_rate, ss.time_worked)
      ),
      skip_organization_id: true
    )
  end

  @doc """
  Total cost across all months for a project. Sums month-by-month costs.
  """
  @spec compute_project_total_cost_all_time(Ash.UUID.t(), map()) :: Decimal.t() | nil
  def compute_project_total_cost_all_time(project_id, context) do
    ash_opts = [actor: context.actor, tenant: context.tenant]

    project_id
    |> read_months_with_sessions_by_project(ash_opts)
    |> Enum.reduce(nil, fn month_date, acc ->
      month_cost = compute_project_total_cost(project_id, month_date)
      add_nullable_decimals(acc, month_cost)
    end)
  end

  @doc """
  Per-user time and cost for a project in a given month.

  Returns a list of user maps with `:time_worked`, `:hourly_rate`, `:cost`,
  `:salary`, `:hours_record`, `:removed_from_project`, and `:expanded` keys.
  """
  @spec compute_project_month_users_with_cost(Ash.UUID.t(), Date.t()) :: [map()]
  def compute_project_month_users_with_cost(project_id, %Date{} = date) do
    alias Firmowid.Accounts
    alias Firmowid.Helpers.TimeConverter

    as_of_date = Date.end_of_month(date)

    project_id
    |> query_month_summary_by_project(date.month, date.year)
    |> Enum.map(fn %{user: u, time_worked: t, removed_from_project: r, hours_record: hr} ->
      salary = query_user_salary_as_of(u.id, as_of_date)
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

  @doc """
  Per-user time and cost across all months for a project. Merges per-user totals.
  """
  @spec compute_project_users_with_cost_all_time(Ash.UUID.t(), map()) :: [map()]
  def compute_project_users_with_cost_all_time(project_id, context) do
    ash_opts = [actor: context.actor, tenant: context.tenant]

    project_id
    |> read_months_with_sessions_by_project(ash_opts)
    |> Enum.reduce(%{}, fn month_date, acc ->
      project_id
      |> compute_project_month_users_with_cost(month_date)
      |> merge_month_users(acc)
    end)
    |> Map.values()
    |> Enum.sort_by(&{&1.removed_from_project, &1.name, &1.email})
  end

  @doc """
  Users associated with a project, including users who have sessions but were
  removed from the project.
  """
  @spec query_project_users_with_removed(Ash.UUID.t()) :: [map()]
  def query_project_users_with_removed(project_id) do
    session_users_query =
      from(s in Session,
        where: s.project_id == ^project_id and s.user_id == parent_as(:user).id,
        select: 1
      )

    # TODO: replace raw Ecto with Ash action when Core.User has relationships
    # to sessions and project_users (requires migrating Accounts to Ash).
    Firmowid.Repo.all(
      from(u in User,
        as: :user,
        left_join: pu in ProjectUser,
        on: u.id == pu.user_id and pu.project_id == ^project_id,
        where: exists(session_users_query) or not is_nil(pu.id),
        order_by: [u.name, u.email],
        select: %{user: u, removed_from_project: is_nil(pu.id)}
      )
    )
  end

  @doc """
  A user's projects with per-project session duration in a given month.
  """
  @spec read_user_projects_with_duration(Ash.ActionInput.t(), map()) :: [map()]
  def read_user_projects_with_duration(input, context) do
    ash_opts = [actor: context.actor, tenant: context.tenant]
    user_id = input.arguments.user_id
    %Date{month: month, year: year} = input.arguments.date

    duration_filter =
      Ash.Query.filter(
        Session,
        user_id == ^user_id and fragment("extract(month from ?) = ?", start_datetime, ^month) and
          fragment("extract(year from ?) = ?", start_datetime, ^year)
      )

    Firmowid.Ash.Timetracker.Project
    |> Ash.Query.for_read(:for_user, %{user_id: user_id}, ash_opts)
    |> Ash.Query.aggregate(:duration, :sum, :sessions,
      field: :duration,
      default: 0,
      query: duration_filter
    )
    |> Ash.read!(ash_opts)
    |> Enum.map(fn project ->
      Map.put(project, :duration, project.aggregates[:duration] || 0)
    end)
    |> Enum.sort_by(& &1.duration, :desc)
  end

  # ── Private helpers ───────────────────────────────────────────────────

  defp read_months_with_sessions_by_project(project_id, ash_opts) do
    Session
    |> Ash.Query.filter(project_id == ^project_id)
    |> Ash.Query.distinct(:month_start)
    |> Ash.Query.distinct_sort(month_start: :desc)
    |> Ash.Query.sort(month_start: :desc)
    |> Ash.Query.load(:month_start)
    |> Ash.read!(ash_opts)
    |> Enum.map(fn session ->
      session.month_start
      |> NaiveDateTime.to_date()
      |> Date.beginning_of_month()
    end)
  end

  defp query_month_summary_by_project(project_id, month, year) do
    session_summary =
      from(s in Session,
        where:
          s.project_id == ^project_id and
            fragment("extract(month from ?) = ?", s.start_datetime, ^month) and
            fragment("extract(year from ?) = ?", s.start_datetime, ^year),
        group_by: s.user_id,
        select: %{
          user_id: s.user_id,
          time_worked:
            fragment(
              "SUM(EXTRACT(EPOCH FROM COALESCE(?, NOW()) - ?))::integer",
              s.end_datetime,
              s.start_datetime
            )
        }
      )

    # TODO: replace raw Ecto with Ash action when cross-domain joins
    # (User × ProjectUser × sessions × HoursRecord) are supported.
    Firmowid.Repo.all(
      from(u in User,
        left_join: pu in ProjectUser,
        on: u.id == pu.user_id and pu.project_id == ^project_id,
        left_join: s in subquery(session_summary),
        on: u.id == s.user_id,
        left_join: hr in Firmowid.Ash.Timetracker.HoursRecord,
        on: u.id == hr.user_id and hr.month == ^month and hr.year == ^year,
        where: not is_nil(pu.id) or not is_nil(s.user_id),
        order_by: [u.name, u.email],
        select: %{
          user: u,
          time_worked: s.time_worked |> coalesce(0) |> type(:integer),
          removed_from_project: is_nil(pu.id),
          hours_record: hr
        }
      )
    )
  end

  defp query_user_salary_as_of(user_id, %Date{} = date) do
    organization_id = Firmowid.Repo.get_org_id()

    date
    |> UserSalary.salary_as_of_subquery(organization_id)
    |> where([us], us.user_id == ^user_id)
    # TODO: replace raw Ecto with Ash.read_one when UserSalary has a date-based
    # lookup action that supports per-user filtering without temporal DISTINCT ON.
    |> Firmowid.Repo.one(skip_organization_id: true)
  end

  defp add_nullable_decimals(nil, nil), do: nil
  defp add_nullable_decimals(nil, b), do: b
  defp add_nullable_decimals(a, nil), do: a
  defp add_nullable_decimals(a, b), do: Decimal.add(a, b)

  defp merge_month_users(month_users, acc) do
    Enum.reduce(month_users, acc, fn user, users_acc ->
      Map.update(users_acc, user.id, all_time_user_from_month(user), fn existing ->
        merge_all_time_user(existing, user)
      end)
    end)
  end

  defp all_time_user_from_month(user) do
    user
    |> Map.put(:expanded, false)
    |> Map.put(:hourly_rate, nil)
    |> Map.put(:salary, nil)
    |> Map.put(:hours_record, nil)
  end

  defp merge_all_time_user(existing, month_user) do
    cost = add_nullable_decimals(existing.cost, month_user.cost)

    existing
    |> Map.put(:time_worked, existing.time_worked + month_user.time_worked)
    |> Map.put(:cost, cost)
    |> Map.put(:expanded, false)
  end
end
