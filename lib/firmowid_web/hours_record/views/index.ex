defmodule FirmowidWeb.HoursRecord.Views.Index do
  @moduledoc false
  use FirmowidWeb, :live_view

  alias Firmowid.Ash.Timetracker.HoursRecord, as: AshHoursRecord
  alias Firmowid.Ash.Timetracker.Session
  alias FirmowidWeb.Infrastructure.Utilities.TimeFormatter

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.ash_scope
    current_user = socket.assigns.current_user

    selected_date = Date.utc_today()
    active_months = months_with_sessions(%{user_id: current_user.id}, scope)

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
    month = selected_date.month
    year = selected_date.year

    # User's projects with month duration, sorted by time descending
    projects =
      Firmowid.Ash.Timetracker.Project
      |> Ash.Query.for_read(:list, %{user_id: user_id}, scope: scope)
      |> Ash.Query.aggregate(:duration, :sum, :sessions,
        field: :duration,
        default: 0,
        query: Ash.Query.for_read(Session, :list, %{user_id: user_id, month: month, year: year}, scope: scope)
      )
      |> Ash.read!(scope: scope)
      |> Enum.map(fn project ->
        seconds = project.aggregates[:duration] || 0

        # Eagerly fetch sessions grouped by title for this user+project+month
        grouped_sessions =
          Session
          |> Ash.Query.for_read(
            :list,
            %{user_id: user_id, project_id: project.id, month: month, year: year},
            scope: scope
          )
          |> Ash.Query.load(:duration)
          |> Ash.read!(scope: scope)
          |> Enum.group_by(& &1.title)
          |> Enum.map(fn {title, ss} ->
            %{title: title, duration: ss |> Enum.map(& &1.duration) |> Enum.sum()}
          end)
          |> Enum.sort_by(& &1.duration, :desc)

        project
        |> Map.put(:duration, seconds)
        |> Map.put(:expanded, false)
        |> Map.put(:sessions, grouped_sessions)
      end)
      |> Enum.sort_by(& &1.duration, :desc)

    # Total duration for this user this month
    total_query = Ash.Query.for_read(Session, :list, %{user_id: user_id, month: month, year: year})

    %{total: total_duration} =
      Ash.aggregate!(total_query, {:total, :sum, field: :duration, default: 0}, scope: scope)

    {:ok, current_month_hours_record} =
      AshHoursRecord.by_month(user_id, month, year,
        scope: scope,
        not_found_error?: false
      )

    socket
    |> assign(:current_hours_record, current_month_hours_record)
    |> assign(:projects, projects)
    |> assign(:total_duration, total_duration)
  end

  def error_to_string(:too_large), do: "Image too large"
  def error_to_string(:too_many_files), do: "Too many files"
  def error_to_string(:not_accepted), do: "Unacceptable file type"

  # Distinct months (as naive_datetime) that have sessions, newest first.
  defp months_with_sessions(filters, scope) do
    Session
    |> Ash.Query.for_read(:list, filters, scope: scope)
    |> Ash.Query.distinct(:month_start)
    |> Ash.Query.distinct_sort(month_start: :desc)
    |> Ash.Query.sort(month_start: :desc)
    |> Ash.Query.load(:month_start)
    |> Ash.read!(scope: scope)
    |> Enum.map(& &1.month_start)
  end
end
