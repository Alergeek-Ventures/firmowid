# credo:disable-for-this-file ExDNA.Credo
# Project detail view intentionally has parallel archived/current-month aggregation flows;
# de-duplication requires cross-function redesign of cost/time computation helpers.
defmodule FirmowidWeb.Management.Views.Project do
  @moduledoc false
  use FirmowidWeb, :live_view

  alias Firmowid.Ash.Core
  alias Firmowid.Ash.Payroll.UserSalary, as: AshUserSalary
  alias Firmowid.Ash.Timetracker
  alias Firmowid.Ash.Timetracker.Project, as: AshProject
  alias Firmowid.Ash.Timetracker.Session
  alias FirmowidWeb.Infrastructure.Utilities.TimeFormatter

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(%{"id" => project_id} = params, _url, socket) do
    scope = socket.assigns.ash_scope

    selected_date =
      case params do
        %{"month" => month} -> Date.from_iso8601!(month)
        _ -> Date.utc_today()
      end

    active_months = months_with_sessions(%{project_id: project_id}, scope)

    socket =
      socket
      |> assign(:selected_date, selected_date)
      |> assign(:active_months, active_months)
      |> assign(:project, AshProject.get!(project_id, scope: scope))
      |> assign(:can_delete_project, socket.assigns.current_user.role == :admin)
      |> assign_project_data()

    {:noreply, socket}
  end

  @impl true
  def handle_event("change-month", %{"month" => month}, %{assigns: %{project: project}} = socket) do
    {:noreply, push_patch(socket, to: ~p"/zarzadzanie/projekty/#{project.id}?month=#{month}")}
  end

  def handle_event("toggle-user", %{"id" => user_id}, socket) do
    scope = socket.assigns.ash_scope
    project = socket.assigns.project
    date = socket.assigns.selected_date

    users =
      Enum.map(socket.assigns.users, fn
        %{id: ^user_id} = user ->
          user
          |> Map.put(:expanded, !user.expanded)
          |> Map.put_new_lazy(:sessions_with_duration, fn ->
            Session
            |> Ash.Query.for_read(
              :list,
              %{user_id: user_id, project_id: project.id, month: date.month, year: date.year},
              scope: scope
            )
            |> Ash.Query.load(:duration)
            |> Ash.read!(scope: scope)
            |> group_sessions_by_title()
          end)

        user ->
          user
      end)

    {:noreply, assign(socket, :users, users)}
  end

  def handle_event("archive_project", _, socket) do
    scope = socket.assigns.ash_scope
    project = socket.assigns.project

    {:ok, project} = AshProject.archive(project, scope: scope)

    socket =
      socket
      |> assign(:project, project)
      |> assign_project_data()

    {:noreply, socket}
  end

  def handle_event("unarchive_project", _, socket) do
    scope = socket.assigns.ash_scope
    project = socket.assigns.project

    case AshProject.unarchive(project, scope: scope) do
      {:ok, updated_project} ->
        socket =
          socket
          |> assign(:project, updated_project)
          |> assign_project_data()

        {:noreply, socket}

      {:error, _error} ->
        {:noreply, put_flash(socket, :error, "Nie udało się przywrócić projektu")}
    end
  end

  def handle_event("delete_project", _, socket) do
    scope = socket.assigns.ash_scope
    project = socket.assigns.project

    :ok = AshProject.destroy(project, scope: scope)

    {:noreply,
     socket
     |> put_flash(:info, "Projekt został usunięty.")
     |> push_navigate(to: ~p"/zarzadzanie/projekty?#{%{month: socket.assigns.selected_date}}")}
  end

  # ── Archived project: all-time totals ─────────────────────────────────

  defp assign_project_data(%{assigns: %{project: %{archived_at: archived_at} = project}} = socket)
       when not is_nil(archived_at) do
    scope = socket.assigns.ash_scope

    sessions =
      Session
      |> Ash.Query.for_read(:list, %{project_id: project.id}, scope: scope)
      |> Ash.Query.load(:duration)
      |> Ash.read!(scope: scope)

    total_time_worked = sessions |> Enum.map(& &1.duration) |> Enum.sum()

    # All salaries for cost computation — use most recent salary per user (as_of today)
    salaries = AshUserSalary.as_of!(Date.utc_today(), scope: scope)
    salary_by_user = Map.new(salaries, &{&1.user_id, &1.hourly_rate})

    users = build_users_with_cost(project, sessions, salary_by_user, %{}, scope)

    total_cost =
      users
      |> Enum.map(& &1.cost)
      |> Enum.reject(&is_nil/1)
      |> Enum.reduce(Decimal.new(0), &Decimal.add/2)

    socket
    |> assign(:users, users)
    |> assign(:total_time_worked, total_time_worked)
    |> assign(:total_cost, total_cost)
    |> assign(:previous_month_label, nil)
    |> assign(:hours_delta, nil)
    |> assign(:cost_delta, nil)
  end

  # ── Active project: current month + previous month delta ──────────────

  defp assign_project_data(%{assigns: %{selected_date: date, project: project}} = socket) do
    scope = socket.assigns.ash_scope
    previous_month = date |> Date.shift(month: -1) |> Date.beginning_of_month()

    # Current month sessions
    current_sessions =
      Session
      |> Ash.Query.for_read(:list, %{project_id: project.id, month: date.month, year: date.year}, scope: scope)
      |> Ash.Query.load(:duration)
      |> Ash.read!(scope: scope)

    current_total_time = current_sessions |> Enum.map(& &1.duration) |> Enum.sum()

    # Previous month sessions (for delta)
    prev_sessions =
      Session
      |> Ash.Query.for_read(
        :list,
        %{project_id: project.id, month: previous_month.month, year: previous_month.year},
        scope: scope
      )
      |> Ash.Query.load(:duration)
      |> Ash.read!(scope: scope)

    prev_total_time = prev_sessions |> Enum.map(& &1.duration) |> Enum.sum()

    # Salaries as of each month
    current_salaries = AshUserSalary.as_of!(date, scope: scope)
    current_salary_by_user = Map.new(current_salaries, &{&1.user_id, &1.hourly_rate})

    prev_salaries = AshUserSalary.as_of!(previous_month, scope: scope)
    prev_salary_by_user = Map.new(prev_salaries, &{&1.user_id, &1.hourly_rate})

    # Hours records for current month (for lockdown display)
    hours_records =
      Timetracker.list_hours_records!(%{month: date.month, year: date.year}, scope: scope)

    hr_by_user = Map.new(hours_records, &{&1.user_id, &1})

    # Current month cost
    current_total_cost = compute_total_cost(current_sessions, current_salary_by_user)
    prev_total_cost = compute_total_cost(prev_sessions, prev_salary_by_user)

    previous_month_label =
      Cldr.Date.to_string!(previous_month, Firmowid.Cldr, format: "MMMM", locale: "pl")

    users = build_users_with_cost(project, current_sessions, current_salary_by_user, hr_by_user, scope)

    socket
    |> assign(:users, users)
    |> assign(:total_time_worked, current_total_time)
    |> assign(:total_cost, current_total_cost)
    |> assign(:previous_month_label, previous_month_label)
    |> assign(:hours_delta, percent_delta(current_total_time, prev_total_time))
    |> assign(:cost_delta, percent_delta(current_total_cost, prev_total_cost))
  end

  # TODO: add unit tests for cost calculation helpers (build_users_with_cost/5,
  # compute_total_cost/2) — they encode business rules (ceiling hours, salary
  # lookups, removed-from-project flag) that were previously covered by the
  # now-deleted ProjectCosts generic action tests.

  # Build per-user cost maps. `project.users` gives current members; sessions
  # may include users no longer in the project.
  defp build_users_with_cost(project, sessions, salary_by_user, hr_by_user, scope) do
    time_by_user =
      sessions
      |> Enum.group_by(& &1.user_id)
      |> Map.new(fn {uid, ss} -> {uid, ss |> Enum.map(& &1.duration) |> Enum.sum()} end)

    member_ids = MapSet.new(project.users, & &1.id)
    session_user_ids = MapSet.new(Map.keys(time_by_user))
    all_user_ids = MapSet.union(member_ids, session_user_ids)

    users_by_id = Map.new(project.users, &{&1.id, &1})

    all_user_ids
    |> Enum.map(fn uid ->
      user = resolve_user(uid, users_by_id, scope)

      user = Ash.load!(user, [avatar_blob: [:url]], scope: scope)
      time = Map.get(time_by_user, uid, 0)
      rate = Map.get(salary_by_user, uid)
      hours = Timetracker.seconds_to_hours(time)
      cost = rate && Decimal.mult(rate, Decimal.new(hours))

      user
      |> Map.put(:time_worked, time)
      |> Map.put(:hourly_rate, rate)
      |> Map.put(:cost, cost)
      |> Map.put(:hours_record, Map.get(hr_by_user, uid))
      |> Map.put(:removed_from_project, not MapSet.member?(member_ids, uid))
      |> Map.put(:expanded, false)
    end)
    |> Enum.sort_by(&{&1.removed_from_project, &1.name, &1.email})
  end

  defp compute_total_cost(sessions, salary_by_user) do
    sessions
    |> Enum.group_by(& &1.user_id)
    |> Enum.map(fn {uid, ss} ->
      time = ss |> Enum.map(& &1.duration) |> Enum.sum()
      rate = Map.get(salary_by_user, uid)
      hours = Timetracker.seconds_to_hours(time)
      rate && Decimal.mult(rate, Decimal.new(hours))
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.reduce(Decimal.new(0), &Decimal.add/2)
  end

  defp percent_delta(_current, prev) when prev in [nil, 0], do: nil

  defp percent_delta(current, prev) when is_integer(current) and is_integer(prev) do
    delta = current - prev

    percent =
      delta
      |> Kernel./(prev)
      |> Kernel.*(100)
      |> round()

    direction =
      cond do
        percent > 0 -> :increase
        percent < 0 -> :decrease
        true -> :same
      end

    %{percent: abs(percent), direction: direction}
  end

  defp percent_delta(%Decimal{} = current, %Decimal{} = prev) do
    if Decimal.equal?(prev, Decimal.new("0")) do
      nil
    else
      delta = Decimal.sub(current, prev)

      percent =
        delta
        |> Decimal.div(prev)
        |> Decimal.mult(Decimal.new("100"))
        |> Decimal.round(0)
        |> Decimal.to_integer()

      direction =
        cond do
          percent > 0 -> :increase
          percent < 0 -> :decrease
          true -> :same
        end

      %{percent: abs(percent), direction: direction}
    end
  end

  def comparison_text(%{percent: percent, direction: direction}, previous_month_label) do
    case direction do
      :same -> "0% względem #{previous_month_label}"
      :increase -> "+#{percent}% względem #{previous_month_label}"
      :decrease -> "-#{percent}% względem #{previous_month_label}"
    end
  end

  defp format_hours(seconds) do
    hours = div(seconds, 60 * 60)

    cond do
      seconds == 0 -> "—"
      hours > 0 -> "#{hours} h"
      true -> TimeFormatter.format_duration(seconds)
    end
  end

  # Group raw sessions (with :duration loaded) by title, summing durations.
  defp group_sessions_by_title(sessions) do
    sessions
    |> Enum.group_by(& &1.title)
    |> Enum.map(fn {title, ss} ->
      %{title: title, duration: ss |> Enum.map(& &1.duration) |> Enum.sum()}
    end)
    |> Enum.sort_by(& &1.duration, :desc)
  end

  # Resolve a user by ID: prefer already-loaded project members, fall back to Core.
  defp resolve_user(uid, users_by_id, scope) do
    case Map.get(users_by_id, uid) do
      nil -> Core.get_org_user!(%{id: uid}, scope: scope)
      u -> u
    end
  end

  # Distinct months (as naive_datetime) that have sessions, newest first.
  defp months_with_sessions(filters, scope), do: Timetracker.months_with_sessions(filters, scope)
end
