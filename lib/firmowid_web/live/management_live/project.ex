defmodule FirmowidWeb.ManagementLive.Project do
  @moduledoc false
  use FirmowidWeb, :live_view

  alias Firmowid.Accounts
  alias Firmowid.SalesInvoices.Counterparty
  alias Firmowid.Timetracker
  alias FirmowidWeb.Helpers.TimeFormatter

  @impl true
  def mount(%{"id" => project_id}, _session, socket) do
    Bodyguard.permit!(Timetracker, :read_projects, socket.assigns.current_user)

    socket =
      socket
      |> assign(:project, load_project!(project_id))
      |> assign(:active_months, Timetracker.get_months_with_sessions_by_project(project_id))

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    selected_date =
      case params do
        %{"month" => month} -> Date.from_iso8601!(month)
        _ -> Date.utc_today()
      end

    socket =
      socket
      |> assign(:selected_date, selected_date)
      |> assign_project_users()
      |> assign_project_month_comparison()

    {:noreply, socket}
  end

  @impl true
  def handle_event("change-month", %{"month" => month}, socket) do
    {:noreply, push_patch(socket, to: ~p"/zarzadzanie/projekty/#{socket.assigns.project.id}?month=#{month}")}
  end

  def handle_event("toggle-user", %{"id" => user_id}, socket) do
    users =
      Enum.map(socket.assigns.users, fn
        %{id: ^user_id} = user ->
          user
          |> Map.put(:expanded, !user.expanded)
          |> Map.put_new_lazy(:sessions_with_duration, fn ->
            Timetracker.get_grouped_user_project_sessions(
              user.id,
              socket.assigns.project.id,
              socket.assigns.selected_date
            )
          end)

        user ->
          user
      end)

    {:noreply, assign(socket, :users, users)}
  end

  def handle_event("archive_project", _, socket) do
    project = socket.assigns.project
    Bodyguard.permit!(Timetracker, :update_project, socket.assigns.current_user, project)

    {:ok, project} = Timetracker.archive_project(project)
    {:noreply, assign(socket, :project, project)}
  end

  def handle_event("unarchive_project", _, socket) do
    project = socket.assigns.project
    Bodyguard.permit!(Timetracker, :update_project, socket.assigns.current_user, project)

    {:ok, project} = Timetracker.unarchive_project(project)
    {:noreply, assign(socket, :project, project)}
  end

  defp assign_project_users(socket) do
    date = socket.assigns.selected_date

    project_id = socket.assigns.project.id

    {project_user_hours, total_project_seconds, total_cost} =
      if socket.assigns.project.archived_at do
        {
          Timetracker.get_project_users_with_cost_all_time(project_id),
          Timetracker.get_project_total_time_worked_all_time(project_id),
          Timetracker.get_project_total_cost_all_time(project_id)
        }
      else
        {
          Timetracker.get_project_month_users_with_cost(project_id, date),
          Timetracker.get_project_total_time_worked(project_id, date),
          Timetracker.get_project_total_cost(project_id, date)
        }
      end

    socket
    |> assign(:users, project_user_hours)
    |> assign(:total_time_worked, total_project_seconds)
    |> assign(:total_cost, total_cost)
  end

  defp assign_project_month_comparison(socket) do
    if socket.assigns.project.archived_at do
      socket
      |> assign(:previous_month_label, nil)
      |> assign(:hours_delta, nil)
      |> assign(:cost_delta, nil)
    else
      date = socket.assigns.selected_date
      project_id = socket.assigns.project.id

      previous_month = date |> Date.shift(month: -1) |> Date.beginning_of_month()
      previous_month_label = Cldr.Date.to_string!(previous_month, Firmowid.Cldr, format: "MMMM", locale: "pl")

      previous_total_time_worked = Timetracker.get_project_total_time_worked(project_id, previous_month)
      previous_total_cost = Timetracker.get_project_total_cost(project_id, previous_month)

      hours_delta = percent_delta(socket.assigns.total_time_worked, previous_total_time_worked)
      cost_delta = percent_delta(socket.assigns.total_cost, previous_total_cost)

      socket
      |> assign(:previous_month_label, previous_month_label)
      |> assign(:hours_delta, hours_delta)
      |> assign(:cost_delta, cost_delta)
    end
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

  defp load_project!(id) do
    project = Timetracker.get_project!(id)
    %{project | users: Enum.map(project.users, &Accounts.get_user_with_avatar/1)}
  end
end
