defmodule FirmowidWeb.TimetrackerLive.Projects do
  alias Firmowid.Accounts
  alias Firmowid.Timetracker
  alias Firmowid.Timetracker.Project
  alias Firmowid.Timetracker.Session
  alias FirmowidWeb.Helpers.TimeFormatter
  use FirmowidWeb, :live_view

  def mount(_params, _session, socket) do
    Bodyguard.permit!(Timetracker, :read_projects, socket.assigns.current_user)
    Bodyguard.permit!(Timetracker, :read_hours_records, socket.assigns.current_user)

    current_date = Date.utc_today()

    {:ok,
     socket
     |> assign(
       users: fetch_users_with_avatars(),
       projects: Timetracker.list_projects_with_users(),
       hours_records: fetch_hours_records(),
       form: to_form(Project.form_changeset()),
       show_modal: false,
       editing_project: nil,
       selected_date: current_date,
       active_months: Timetracker.get_months_with_sessions(socket.assigns.current_user.id),
       selected_month_num: current_date.month,
       selected_project_id: nil,
       project_user_hours: []
     )}
  end

  defp fetch_users_with_avatars do
    Timetracker.list_users_with_projects()
    |> Enum.map(&Accounts.get_user_with_avatar/1)
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

    {:noreply,
     assign(socket,
       users: Timetracker.list_users_with_projects() |> Enum.map(&Accounts.get_user_with_avatar/1)
     )
     |> assign(
       :projects,
       Timetracker.list_projects_with_users()
     )}
  end

  def handle_event("new", _params, socket) do
    {:noreply,
     assign(socket,
       show_modal: true,
       editing_project: nil,
       form: to_form(Project.form_changeset())
     )}
  end

  def handle_event("edit", %{"id" => id}, socket) do
    project = Timetracker.get_project!(id)
    changeset = Project.form_changeset(project)

    {:noreply,
     assign(socket,
       show_modal: true,
       editing_project: project,
       form: to_form(changeset)
     )}
  end

  def handle_event("close", _params, socket) do
    {:noreply, assign(socket, show_modal: false)}
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

    {:noreply, assign(socket, projects: Timetracker.list_projects_with_users())}
  end

  def handle_event("close_modal", _, socket) do
    {:noreply, assign(socket, show_modal: false)}
  end

  def handle_event("select_project", %{"selected_project" => project_id}, socket)
      when project_id == "",
      do: {:noreply, assign(socket, selected_project_id: nil, project_user_hours: [])}

  def handle_event("select_project", %{"selected_project" => project_id}, socket) do
    {:noreply,
     socket
     |> assign(:selected_project_id, project_id)
     |> load_project_hours()}
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
        {:noreply,
         socket
         |> assign(show_modal: false)
         |> assign(:projects, Timetracker.list_projects_with_users())}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp handle_update(socket, project, params) do
    Bodyguard.permit!(Timetracker, :update_project, socket.assigns.current_user)

    case Timetracker.update_project(project, params) do
      {:ok, _project} ->
        {:noreply,
         socket
         |> assign(show_modal: false)
         |> assign(:projects, Timetracker.list_projects_with_users())}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp load_project_hours(%{assigns: %{selected_project_id: nil}} = socket), do: socket

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

    month_sessions = filter_sessions_by_month(sessions, target_month, target_year)
    month_seconds = sum_session_durations(month_sessions)

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

  defdelegate format_duration(seconds), to: TimeFormatter
  defdelegate format_duration_with_days(seconds), to: TimeFormatter

  def project_details(assigns) do
    ~H"""
    <div class="grid gap-6 md:grid-cols-6">
      <div class="space-y-2 w-full col-span-4">
        <%= for user_hours <- @user_hours do %>
          <div class="flex items-center bg-white rounded-md p-4 py-6 justify-between">
            <div class="flex items-center gap-4">
              <.avatar class="size-10 ring-1 ring-greyButtonBg/50">
                <.avatar_image src={user_hours.user.avatar_url} alt="Avatar" />
                <.avatar_fallback class="bg-blueBg text-blueText">
                  {String.slice(user_hours.user.email || "", 0, 1) |> String.upcase()}
                </.avatar_fallback>
              </.avatar>
              <span class="text-darkGrey">{user_hours.user.name || user_hours.user.email}</span>
            </div>
            <span class="font-medium">{trunc(user_hours.month_hours)} h</span>
          </div>
        <% end %>

        <%= if Enum.empty?(@user_hours) do %>
          <div class="py-8 bg-white rounded-md text-center text-darkGrey text-sm">
            Brak danych o czasie pracy dla tego projektu.
          </div>
        <% end %>
      </div>

      <div class="flex flex-col col-span-2 gap-4">
        <div class="space-y-2 border border-greyButtonBg p-4 rounded-md bg-white">
          <h3 class="font-bold text-lg">{@project.name}</h3>
          <p class="text-sm text-darkGrey">
            Projekt utworzony: {Calendar.strftime(@project.inserted_at, "%d.%m.%Y r.")}
          </p>
        </div>

        <div class="space-y-8 border border-greyButtonBg p-4 rounded-md bg-white">
          <div>
            <h3 class="font-bold mb-8">Podsumowanie:</h3>
            <div>
              <p class="mb-3">Przepracowane godziny w miesiącu:</p>
              <p class="text-xl font-bold">{format_duration(@total_seconds)}</p>
              <p class="text-sm text-darkGrey">{format_duration_with_days(@total_seconds)}</p>
            </div>
          </div>

          <%= if most_active = Enum.max_by(@user_hours, & &1.month_hours, fn -> nil end) do %>
            <div>
              <p class="mb-3">Najbardziej aktywny użytkownik:</p>
              <p class="text-xl font-bold">{format_duration(most_active.month_seconds)}</p>
              <p class="text-sm text-darkGrey">{most_active.user.name || most_active.user.email}</p>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end
end
