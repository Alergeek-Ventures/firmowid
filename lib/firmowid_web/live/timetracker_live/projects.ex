defmodule FirmowidWeb.TimetrackerLive.Projects do
  alias Firmowid.Accounts
  alias Firmowid.Timetracker
  alias Firmowid.Timetracker.Project
  alias Firmowid.Timetracker.Session
  alias FirmowidWeb.Helpers.TimeFormatter
  alias Firmowid.Repo
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
       is_editing_name: false,
       is_editing_users: false,
       selected_date: current_date,
       selected_month_num: current_date.month
     )}
  end

  @impl true
  def handle_params(%{"id" => project_id}, _, socket) do
    {:noreply,
     socket
     |> assign(:selected_project, Enum.find(socket.assigns.projects, &(&1.id == project_id)))
     |> assign(:active_months, Timetracker.get_months_with_sessions_by_project(project_id))
     |> load_project_hours()}
  end

  def handle_params(_params, _, socket) do
    {:noreply,
     socket
     |> assign(selected_project: nil)
     |> assign(active_months: Timetracker.get_months_with_sessions())
     |> assign(hours_records: fetch_hours_records())}
  end

  defp fetch_hours_records do
    Timetracker.list_hours_records()
    |> Enum.sort_by(fn record -> {record.year, record.month} end, :desc)
  end

  def handle_event("edit_name", _, %{assigns: %{selected_project: project}} = socket) do
    changeset = project |> Project.form_changeset()

    {:noreply, assign(socket, form: to_form(changeset), is_editing_name: true)}
  end

  def handle_event("edit_users", _, %{assigns: %{selected_project: project}} = socket) do
    # can i use repo here?
    project = Repo.preload(project, project_users: :user)

    {:noreply,
     socket
     |> assign(is_editing_users: true)
     |> assign(selected_project: project)
     |> assign_project_users(
       project.project_users
       |> Enum.map(& &1.user)
       |> Enum.map(&Accounts.get_user_with_avatar/1)
     )}
  end

  def handle_event("delete_user", %{"user_id" => user_id}, socket) do
    Bodyguard.permit!(Timetracker, :update_project, socket.assigns.current_user)

    project_users =
      socket.assigns.project_users
      |> Enum.reject(&(&1.id == user_id))

    {:noreply, assign_project_users(socket, project_users)}
  end

  def handle_event("add_user", %{"user_id" => user_id}, socket) do
    Bodyguard.permit!(Timetracker, :update_project, socket.assigns.current_user)

    project_users =
      socket.assigns.project_users ++
        [Enum.find(socket.assigns.users, &(&1.id == user_id))]

    {:noreply, assign_project_users(socket, project_users)}
  end

  def handle_event("save_users", _, socket) do
    Bodyguard.permit!(Timetracker, :update_project, socket.assigns.current_user)
    project = socket.assigns.selected_project
    project_users = socket.assigns.project_users |> Enum.map(& &1.id)

    case Timetracker.set_users_to_project(project, project_users) do
      {:ok, project} ->
        {:noreply,
         socket
         |> load_project_hours()
         |> assign(
           is_editing_users: false,
           selected_project: project,
           users: nil,
           project_users: nil
         )}

      {:error, _changeset} ->
        # todo: handle error
        {:noreply, socket}
    end
  end

  def handle_event("cancel", _, socket) do
    {:noreply, assign(socket, is_editing_name: false, is_editing_users: false, form: nil)}
  end

  def handle_event("validate", %{"project" => params}, socket) do
    changeset =
      socket.assigns.selected_project
      |> Project.form_changeset(params)

    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"project" => params}, socket) do
    Bodyguard.permit!(Timetracker, :update_project, socket.assigns.current_user)
    project = socket.assigns.selected_project

    case Timetracker.update_project(project, params) do
      {:ok, project} ->
        {:noreply,
         assign(socket,
           is_editing_name: false,
           is_editing_users: false,
           projects: Timetracker.list_projects(),
           selected_project: project
         )}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
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

  def assign_project_users(socket, project_users) do
    assign(socket,
      users:
        Timetracker.list_users_with_projects()
        |> Enum.map(&Accounts.get_user_with_avatar/1)
        |> Enum.reject(fn user ->
          Enum.any?(project_users, &(&1.id == user.id))
        end),
      project_users: project_users
    )
  end

  defp load_project_hours(%{assigns: %{selected_project: nil}} = socket) do
    socket
    |> assign(:project_user_hours, [])
    |> assign(:total_project_seconds, 0)
  end

  defp load_project_hours(socket) do
    selected_month = socket.assigns.selected_month_num
    current_year = socket.assigns.selected_date.year

    project_id = socket.assigns.selected_project.id
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

  attr :project_user_hours, :list, required: true

  def render_project_user_hours(assigns) do
    ~H"""
    <%= for user_hours <- @project_user_hours do %>
      <div class="flex items-center bg-white rounded-md p-4 justify-between col-span-full">
        <div class="flex items-center gap-6">
          <.avatar class="size-8 ring-1 ring-greyButtonBg/50">
            <.avatar_image src={user_hours.user.avatar_url} alt="Avatar" />
            <.avatar_fallback class="bg-blueBg text-blueText">
              {String.slice(user_hours.user.email || "", 0, 1) |> String.upcase()}
            </.avatar_fallback>
          </.avatar>
          <span class="text-darkGrey">
            {user_hours.user.name || user_hours.user.email}
          </span>
        </div>
        <span>{trunc(user_hours.month_hours)} h</span>
      </div>
    <% end %>

    <div
      :if={Enum.empty?(@project_user_hours)}
      class="py-8 bg-white rounded-md text-center text-darkGrey text-sm col-span-full"
    >
      Brak danych o czasie pracy dla tego projektu.
    </div>
    """
  end

  attr :project_users, :list, required: true
  attr :users, :list, required: true

  def render_project_edit(assigns) do
    ~H"""
    <%= for user <- @project_users do %>
      <div class="flex items-center bg-white rounded-md p-4 justify-between col-span-full">
        <div class="flex items-center gap-6">
          <.avatar class="size-8 ring-1 ring-greyButtonBg/50">
            <.avatar_image src={user.avatar_url} alt="Avatar" />
            <.avatar_fallback class="bg-blueBg text-blueText">
              {String.slice(user.email || "", 0, 1) |> String.upcase()}
            </.avatar_fallback>
          </.avatar>
          <span class="text-darkGrey">
            {user.name || user.email}
          </span>
        </div>
        <button
          phx-click="delete_user"
          phx-value-user_id={user.id}
          class="h-6 w-8 rounded-md hover:bg-greyButtonBg text-darkGrey disabled:text-orangeText inline-flex items-center justify-center ml-1"
        >
          <.icon name="hero-trash-micro" />
        </button>
      </div>
    <% end %>
    <form phx-change="add_user" class="relative col-span-full">
      <.icon
        name="hero-plus-mini"
        class="text-darkGrey absolute top-1/2 transform -translate-y-1/2 left-2"
      />
      <.input
        type="select"
        name="user_id"
        id="user"
        prompt="Dodaj współpracownika"
        value={nil}
        options={Enum.map(@users, &{&1.name || &1.email, &1.id})}
        class="pl-9"
      />
    </form>
    """
  end

  attr :hours_records, :list, required: true

  def render_hours_records(assigns) do
    ~H"""
    <div :for={record <- @hours_records} class="grid grid-cols-subgrid col-span-full">
      <div class="flex items-center bg-white rounded-md p-4 justify-between">
        <div class="flex items-center gap-6">
          <.avatar class="size-8 ring-1 ring-greyButtonBg/50">
            <.avatar_image src={record.user.avatar_url} alt="Avatar" />
            <.avatar_fallback class="bg-blueBg text-blueText">
              {String.slice(record.user.email || "", 0, 1) |> String.upcase()}
            </.avatar_fallback>
          </.avatar>
          <span class="text-darkGrey">
            {record.user.name || record.user.email}
          </span>
        </div>
        <span>{trunc(record.number_of_hours)} h</span>
      </div>
      <div class="bg-white rounded-md p-4 justify-between items-center flex">
        <div class="text-greenText bg-greenBg px-2 py-[5px] rounded-md flex items-center justify-center gap-1">
          <span class="text-[11px] font-semibold">
            EWIDENCJA
          </span>
          <.icon name="hero-check-micro" />
        </div>
        <a
          href={~p"/czasosledz/ewidencja/#{record.id}"}
          download={"Ewidencja_#{record.year}_#{record.month}_#{record.user.name}.pdf"}
          class="py-1 px-2 transition hover:bg-greyButtonBg rounded-md inline-flex items-center justify-center"
        >
          <.icon name="hero-arrow-down-tray-micro" class="text-darkGrey" />
        </a>
      </div>
    </div>
    """
  end
end
