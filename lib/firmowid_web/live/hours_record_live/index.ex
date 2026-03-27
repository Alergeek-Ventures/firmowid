defmodule FirmowidWeb.HoursRecordLive.Index do
  @moduledoc false
  use FirmowidWeb, :live_view

  alias Firmowid.Ash.Timetracker.HoursRecord, as: AshHoursRecord
  alias Firmowid.Ash.Timetracker.Project, as: AshProject
  alias Firmowid.Ash.Timetracker.Session, as: AshSession
  alias FirmowidWeb.Helpers.TimeFormatter

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.ash_scope
    current_user = socket.assigns.current_user

    selected_date = Date.utc_today()

    {:ok, active_months} =
      AshSession.months_with_sessions(%{user_id: current_user.id}, scope: scope)

    can_use_hours_records = current_user.name && current_user.employment_date

    socket =
      socket
      |> assign(:selected_date, selected_date)
      |> assign(:active_months, active_months)
      |> assign(:can_use_hours_records, can_use_hours_records)

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    month =
      case Map.get(params, "month") do
        nil -> Date.beginning_of_month(Date.utc_today())
        date_string -> Date.from_iso8601!(date_string)
      end

    {:noreply, socket |> assign(selected_date: month) |> refetch_data()}
  end

  @impl true
  def handle_event("toggle-project", %{"id" => project_id}, socket) do
    projects =
      Enum.map(socket.assigns.projects, fn
        %{id: ^project_id} = project ->
          Map.put(project, :expanded, !project.expanded)

        project ->
          project
      end)

    {:noreply, assign(socket, :projects, projects)}
  end

  def handle_event("change-month", %{"month" => month}, socket) do
    month = Date.from_iso8601!(month)

    socket =
      socket
      |> assign(:selected_date, month)
      |> push_patch(to: ~p"/czasosledz/ewidencja?month=#{Date.to_iso8601(month)}")

    {:noreply, socket}
  end

  @impl true
  def handle_info(:upload_complete, socket) do
    {:noreply, refetch_data(socket)}
  end

  def refetch_data(socket) do
    scope = socket.assigns.ash_scope
    selected_date = socket.assigns.selected_date
    user_id = socket.assigns.current_user.id

    {:ok, projects_with_duration} =
      AshProject.user_projects_with_duration(user_id, selected_date, scope: scope)

    projects =
      Enum.map(projects_with_duration, fn project ->
        {:ok, sessions} =
          AshSession.grouped_user_project_sessions(
            user_id,
            project.id,
            selected_date.month,
            selected_date.year,
            scope: scope
          )

        project
        |> Map.put(:expanded, false)
        |> Map.put(:sessions, sessions)
      end)

    {:ok, current_month_hours_record} =
      AshHoursRecord.by_month(user_id, selected_date.month, selected_date.year,
        scope: scope,
        not_found_error?: false
      )

    {:ok, total_duration} =
      AshSession.total_time_worked(
        %{month: selected_date.month, year: selected_date.year, user_id: user_id},
        scope: scope
      )

    socket
    |> assign(:current_hours_record, current_month_hours_record)
    |> assign(:projects, projects)
    |> assign(:total_duration, total_duration)
  end

  def error_to_string(:too_large), do: "Image too large"
  def error_to_string(:too_many_files), do: "Too many files"
  def error_to_string(:not_accepted), do: "Unacceptable file type"
end
