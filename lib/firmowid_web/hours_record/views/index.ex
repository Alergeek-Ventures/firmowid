defmodule FirmowidWeb.HoursRecord.Views.Index do
  @moduledoc "Shows monthly hours and allows submission and change requests for signed records."
  use FirmowidWeb, :live_view

  import FirmowidWeb.DesignSystem.Components.Button
  import FirmowidWeb.DesignSystem.Components.CoreComponents, except: [button: 1]
  import FirmowidWeb.DesignSystem.Components.Link
  import FirmowidWeb.DesignSystem.Components.MonthPicker
  import FirmowidWeb.HoursRecord.Components.ChangeRequest
  import Phoenix.Component, except: [link: 1]

  alias Firmowid.Ash.Timetracker
  alias Firmowid.Ash.Timetracker.HoursRecord, as: AshHoursRecord
  alias FirmowidWeb.Infrastructure.Utilities.QueryParams
  alias FirmowidWeb.Infrastructure.Utilities.TimeFormatter
  alias FirmowidWeb.Timetracker.Utilities.Navigation

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
    month = QueryParams.parse_date(params, "miesiac", Date.beginning_of_month(Date.utc_today()))

    {:noreply,
     socket
     |> assign(selected_date: month, change_request_error: nil)
     |> assign(:change_request_form, to_form(%{}, as: :change_request))
     |> refetch_data()}
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
      |> push_patch(to: Navigation.hours_record_index_path(month))

    {:noreply, socket}
  end

  def handle_event("request-change", %{"change_request" => params}, socket) do
    scope = socket.assigns.ash_scope
    date = socket.assigns.selected_date

    with {:ok, record} <-
           AshHoursRecord.by_month(socket.assigns.current_user.id, date.month, date.year, scope: scope),
         {:ok, _record} <-
           AshHoursRecord.request_change(
             record,
             Map.take(params, ["change_request_kind", "change_request_reason"]),
             scope: scope
           ) do
      {:noreply,
       socket
       |> assign(:change_request_error, nil)
       |> refetch_data()
       |> push_event("js-exec", %{to: "#hours-record-change-request", attr: "data-cancel"})}
    else
      {:error, _error} ->
        {:noreply,
         socket
         |> assign(:change_request_form, to_form(params, as: :change_request))
         |> assign(
           :change_request_error,
           gettext(
             "Could not submit the request. Enter a reason (up to 2000 characters). If a request already exists, refresh the page."
           )
         )}
    end
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
      %{user_id: user_id}
      |> Timetracker.query_to_list_projects(scope: scope)
      |> Ash.Query.aggregate(:duration, :sum, :sessions,
        field: :duration,
        default: 0,
        query:
          Timetracker.query_to_list_sessions(%{user_id: user_id, month: month, year: year},
            scope: scope
          )
      )
      |> Ash.read!(scope: scope)
      |> Enum.map(fn project ->
        seconds = project.aggregates[:duration] || 0

        # Eagerly fetch sessions grouped by title for this user+project+month
        grouped_sessions =
          %{user_id: user_id, project_id: project.id, month: month, year: year}
          |> Timetracker.query_to_list_sessions(scope: scope)
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
    total_query =
      Timetracker.query_to_list_sessions(%{user_id: user_id, month: month, year: year},
        scope: scope
      )

    %{total: total_duration} =
      Ash.aggregate!(total_query, {:total, :sum, field: :duration, default: 0}, scope: scope)

    {:ok, current_month_hours_record} =
      AshHoursRecord.by_month(user_id, month, year,
        scope: scope,
        not_found_error?: false
      )

    period_records =
      Timetracker.list_hours_records!(
        %{user_id: user_id, month: month, year: year, submission_status: nil},
        scope: scope
      )

    socket
    |> assign(:current_hours_record, current_month_hours_record)
    |> assign(
      :change_requests,
      Enum.filter(period_records, &(&1.change_requested_at && &1.submission_status == :submitted))
    )
    |> assign(
      :previous_hours_records,
      Enum.filter(period_records, &(&1.submission_status == :withdrawn))
    )
    |> assign(:projects, projects)
    |> assign(:total_duration, total_duration)
  end

  def error_to_string(:too_large), do: "Image too large"
  def error_to_string(:too_many_files), do: "Too many files"
  def error_to_string(:not_accepted), do: "Unacceptable file type"

  # Distinct months (as naive_datetime) that have sessions, newest first.
  defp months_with_sessions(filters, scope), do: Timetracker.months_with_sessions(filters, scope)
end
