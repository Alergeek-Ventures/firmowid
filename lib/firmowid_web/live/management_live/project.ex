defmodule FirmowidWeb.ManagementLive.Project do
  @moduledoc false
  use FirmowidWeb, :live_view

  alias Firmowid.Ash.Timetracker.Project, as: AshProject
  alias Firmowid.Ash.Timetracker.Session, as: AshSession
  alias Firmowid.SalesInvoices.Counterparty
  alias FirmowidWeb.Helpers.TimeFormatter

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

    {:ok, active_months} =
      AshSession.months_with_sessions(%{project_id: project_id}, scope: scope)

    socket =
      socket
      |> assign(:selected_date, selected_date)
      |> assign(:active_months, active_months)
      |> assign(:project, load_project!(project_id, scope))
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

    users =
      Enum.map(socket.assigns.users, fn
        %{id: ^user_id} = user ->
          user
          |> Map.put(:expanded, !user.expanded)
          |> Map.put_new_lazy(:sessions_with_duration, fn ->
            date = socket.assigns.selected_date

            {:ok, sessions} =
              AshSession.grouped_user_project_sessions(
                user.id,
                socket.assigns.project.id,
                date.month,
                date.year,
                scope: scope
              )

            sessions
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

    {:ok, project} = AshProject.unarchive(project, scope: scope)

    socket =
      socket
      |> assign(:project, project)
      |> assign_project_data()

    {:noreply, socket}
  end

  def handle_event("delete_project", _, socket) do
    scope = socket.assigns.ash_scope
    project = socket.assigns.project

    :ok = AshProject.destroy(project, scope: scope)

    {:noreply,
     socket
     |> put_flash(:info, "Projekt został usunięty.")
     |> push_navigate(to: ~p"/zarzadzanie/projekty")}
  end

  defp assign_project_data(%{assigns: %{selected_date: _date, project: project}} = socket)
       when not is_nil(project.archived_at) do
    scope = socket.assigns.ash_scope

    {:ok, users} = AshProject.project_users_with_cost_all_time(project.id, scope: scope)

    {:ok, total_time_worked} =
      AshSession.total_time_worked(%{project_id: project.id}, scope: scope)

    {:ok, total_cost} = AshProject.project_total_cost_all_time(project.id, scope: scope)

    socket
    |> assign(:users, users)
    |> assign(:total_time_worked, total_time_worked)
    |> assign(:total_cost, total_cost)
    |> assign(:previous_month_label, nil)
    |> assign(:hours_delta, nil)
    |> assign(:cost_delta, nil)
  end

  defp assign_project_data(%{assigns: %{selected_date: date, project: project}} = socket)
       when is_nil(project.archived_at) do
    scope = socket.assigns.ash_scope
    previous_month = date |> Date.shift(month: -1) |> Date.beginning_of_month()

    {:ok, current_month_total_time_worked} =
      AshSession.total_time_worked(
        %{month: date.month, year: date.year, project_id: project.id},
        scope: scope
      )

    {:ok, previous_month_total_time_worked} =
      AshSession.total_time_worked(
        %{month: previous_month.month, year: previous_month.year, project_id: project.id},
        scope: scope
      )

    {:ok, current_month_total_cost} =
      AshProject.project_total_cost(project.id, date, scope: scope)

    {:ok, previous_month_total_cost} =
      AshProject.project_total_cost(project.id, previous_month, scope: scope)

    previous_month_label =
      Cldr.Date.to_string!(previous_month, Firmowid.Cldr, format: "MMMM", locale: "pl")

    {:ok, users} =
      AshProject.project_month_users_with_cost(project.id, date, scope: scope)

    socket
    |> assign(:users, users)
    |> assign(:total_time_worked, current_month_total_time_worked)
    |> assign(:total_cost, current_month_total_cost)
    |> assign(:previous_month_label, previous_month_label)
    |> assign(
      :hours_delta,
      percent_delta(current_month_total_time_worked, previous_month_total_time_worked)
    )
    |> assign(:cost_delta, percent_delta(current_month_total_cost, previous_month_total_cost))
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

  defp load_project!(id, scope) do
    project = AshProject.get!(id, scope: scope)
    users = Enum.map(project.users, &resolve_avatar/1)
    %{project | users: users}
  end

  defp resolve_avatar(user) do
    avatar_url =
      case Map.get(user, :avatar_blob_id) do
        nil -> nil
        blob_id -> Firmowid.Blobs.get_blob_url(blob_id)
      end

    Map.put(user, :avatar_url, avatar_url)
  end
end
