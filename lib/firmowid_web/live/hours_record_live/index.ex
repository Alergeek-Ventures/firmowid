defmodule FirmowidWeb.HoursRecordLive.Index do
  use FirmowidWeb, :live_view

  alias Firmowid.Timetracker
  alias FirmowidWeb.Helpers.TimeFormatter

  @impl true
  def mount(_params, _session, socket) do
    current_user = socket.assigns.current_user
    Bodyguard.permit!(Firmowid.Timetracker, :read_user_hours_records, current_user)

    selected_date = Date.utc_today()
    active_months = Timetracker.get_months_with_sessions(current_user.id)

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
        nil -> Date.utc_today() |> Date.beginning_of_month()
        date_string -> Date.from_iso8601!(date_string)
      end

    {:noreply, socket |> assign(selected_date: month) |> refetch_data()}
  end

  @impl true
  def handle_event("toggle-project", %{"id" => project_id}, socket) do
    projects =
      socket.assigns.projects
      |> Enum.map(fn
        %{id: ^project_id} = project ->
          project
          |> Map.put(:expanded, !project.expanded)
          |> Map.put_new_lazy(
            :sessions,
            fn ->
              Timetracker.get_grouped_user_project_sessions(
                socket.assigns.current_user.id,
                project_id,
                socket.assigns.selected_date
              )
            end
          )

        project ->
          project
      end)

    {:noreply, socket |> assign(:projects, projects)}
  end

  def handle_event("change-month", %{"month" => month}, socket) do
    month = month |> Date.from_iso8601!()

    socket =
      socket
      |> assign(:selected_date, month)
      |> push_patch(to: ~p"/czasosledz/ewidencja?month=#{month |> Date.to_iso8601()}")

    {:noreply, socket}
  end

  @impl true
  def handle_info(:upload_complete, socket) do
    {:noreply, socket |> refetch_data()}
  end

  def refetch_data(socket) do
    selected_date = socket.assigns.selected_date

    projects =
      Timetracker.list_user_projects_with_duration(
        socket.assigns.current_user.id,
        selected_date
      )
      |> Enum.map(&Map.put(&1, :expanded, false))

    current_month_hours_record =
      Timetracker.get_hours_record_by_month(
        socket.assigns.current_user.id,
        selected_date
      )

    socket
    |> assign(:current_hours_record, current_month_hours_record)
    |> assign(:projects, projects)
    |> assign(
      :total_duration,
      Timetracker.get_sessions_duration_in_month(
        socket.assigns.current_user.id,
        selected_date
      )
    )
  end

  def error_to_string(:too_large), do: "Image too large"
  def error_to_string(:too_many_files), do: "Too many files"
  def error_to_string(:not_accepted), do: "Unacceptable file type"
end
