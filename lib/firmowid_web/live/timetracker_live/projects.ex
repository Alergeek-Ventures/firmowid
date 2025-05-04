defmodule FirmowidWeb.TimetrackerLive.Projects do
  alias Firmowid.Accounts
  alias Firmowid.Timetracker
  alias Firmowid.Timetracker.Project
  alias Firmowid.Timetracker.Session
  alias FirmowidWeb.Helpers.TimeFormatter
  use FirmowidWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    Bodyguard.permit!(Timetracker, :read_projects, socket.assigns.current_user)
    Bodyguard.permit!(Timetracker, :read_hours_records, socket.assigns.current_user)

    current_date = Date.utc_today()

    {:ok,
     socket
     |> assign(
       projects: Timetracker.list_projects(),
       hours_records: fetch_hours_records(),
       form: to_form(Project.form_changeset()),
       editing_project: nil,
       active_months: Timetracker.get_months_with_sessions(socket.assigns.current_user.id),
       selected_date: current_date,
       selected_month_num: current_date.month
     )}
  end

  @impl true
  def handle_params(params, _, socket) do
    {:noreply,
     socket
     |> assign(:selected_project_id, Map.get(params, "id"))
     |> load_project_hours()}
  end

  defp fetch_hours_records do
    Timetracker.list_hours_records()
    |> Enum.sort_by(fn record -> {record.year, record.month} end, :desc)
  end

  def handle_event(
        "toggle_project",
        %{"_target" => ["project", project_id, user_id]},
        socket
      ) do
    Bodyguard.permit!(Timetracker, :update_project, socket.assigns.current_user)

    projects = Timetracker.list_user_projects(user_id)
    has_project = Enum.any?(projects, &(&1.id == project_id))

    if has_project do
      Timetracker.remove_user_from_project(user_id, project_id)
    else
      Timetracker.add_user_to_project(user_id, project_id)
    end

    {:noreply, assign(socket, :projects, Timetracker.list_projects())}
  end

  def handle_event("new", _params, socket) do
    {:noreply,
     assign(socket,
       editing_project: nil,
       form: to_form(Project.form_changeset())
     )}
  end

  def handle_event("edit", %{"id" => id}, socket) do
    project = Timetracker.get_project!(id)
    changeset = Project.form_changeset(project)

    {:noreply,
     assign(socket,
       editing_project: project,
       form: to_form(changeset)
     )}
  end

  def handle_event("validate", %{"project" => params}, socket) do
    changeset =
      case socket.assigns.editing_project do
        nil -> Project.form_changeset(%Project{}, params)
        project -> Project.form_changeset(project, params)
      end
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset))}
  end

  def handle_event("save", %{"project" => params}, socket) do
    case socket.assigns.editing_project do
      nil -> handle_create(socket, params)
      project -> handle_update(socket, project, params)
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    Bodyguard.permit!(Timetracker, :delete_project, socket.assigns.current_user)
    project = Timetracker.get_project!(id)
    {:ok, _} = Timetracker.delete_project(project)

    {:noreply, assign(socket, projects: Timetracker.list_projects())}
  end

  def handle_event("select_project", %{"_target" => ["reset"]}, socket) do
    {:noreply, push_patch(socket, to: ~p"/czasosledz/projekty")}
  end

  def handle_event("select_project", %{"selected_project" => ""}, socket) do
    {:noreply, push_patch(socket, to: ~p"/czasosledz/projekty")}
  end

  def handle_event("select_project", %{"selected_project" => project_id}, socket) do
    {:noreply, push_patch(socket, to: ~p"/czasosledz/projekty/#{project_id}")}
  end

  @impl true
  def handle_event("change-month", %{"month" => month_string}, socket) do
    date = Date.from_iso8601!(month_string)

    {:noreply,
     socket
     |> assign(:selected_date, date)
     |> assign(:selected_month_num, date.month)
     |> load_project_hours()}
  end

  defp handle_create(socket, params) do
    Bodyguard.permit!(Timetracker, :create_project, socket.assigns.current_user)

    case Timetracker.create_project(params) do
      {:ok, _project} ->
        {:noreply, assign(socket, :projects, Timetracker.list_projects())}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp handle_update(socket, project, params) do
    Bodyguard.permit!(Timetracker, :update_project, socket.assigns.current_user)

    case Timetracker.update_project(project, params) do
      {:ok, _project} ->
        {:noreply, assign(socket, :projects, Timetracker.list_projects())}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp load_project_hours(%{assigns: %{selected_project_id: nil}} = socket) do
    socket
    |> assign(:project_user_hours, [])
    |> assign(:total_project_seconds, 0)
  end

  defp load_project_hours(socket) do
    project_id = socket.assigns.selected_project_id
    selected_month = socket.assigns.selected_month_num
    current_year = socket.assigns.selected_date.year

    project = Timetracker.get_project_with_users!(project_id)

    project_user_hours =
      calculate_project_user_hours(project, project_id, selected_month, current_year)

    total_project_seconds = sum_user_month_seconds(project_user_hours)

    socket
    |> assign(:project_user_hours, project_user_hours)
    |> assign(:total_project_seconds, total_project_seconds)
  end

  defp calculate_project_user_hours(project, project_id, month, year) do
    Enum.map(project.users, fn user ->
      # wtf quering in loop
      total_sessions = Timetracker.get_user_project_sessions(user.id, project_id)

      {total_seconds, month_seconds} = calculate_session_durations(total_sessions, month, year)

      %{
        user: Accounts.get_user_with_avatar(user),
        total_hours: total_seconds / 3600,
        month_hours: month_seconds / 3600,
        total_seconds: total_seconds,
        month_seconds: month_seconds
      }
    end)
  end

  defp calculate_session_durations(sessions, target_month, target_year) do
    total_seconds = sum_session_durations(sessions)

    month_seconds =
      filter_sessions_by_month(sessions, target_month, target_year)
      |> sum_session_durations()

    {total_seconds, month_seconds}
  end

  defp filter_sessions_by_month(sessions, month, year) do
    Enum.filter(sessions, fn session ->
      session_datetime = session.start_datetime
      session_datetime.month == month && session_datetime.year == year
    end)
  end

  defp sum_session_durations(sessions) do
    sessions
    |> Enum.map(&Session.calculate_session_duration/1)
    |> Enum.sum()
  end

  defp sum_user_month_seconds(project_user_hours) do
    project_user_hours
    |> Enum.map(& &1.month_seconds)
    |> Enum.sum()
  end

  def format_duration(0), do: "0 h 0 min"
  def format_duration_with_days(0), do: "0 d 0 h 0 min"
  defdelegate format_duration(seconds), to: TimeFormatter
  defdelegate format_duration_with_days(seconds), to: TimeFormatter
end
