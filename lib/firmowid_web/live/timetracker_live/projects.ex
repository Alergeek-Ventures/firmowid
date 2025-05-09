defmodule FirmowidWeb.TimetrackerLive.Projects do
  alias Firmowid.Accounts
  alias Firmowid.Timetracker
  alias Firmowid.Timetracker.Project
  alias FirmowidWeb.Helpers.TimeFormatter
  alias Firmowid.Repo
  use FirmowidWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    Bodyguard.permit!(Timetracker, :read_projects, socket.assigns.current_user)
    Bodyguard.permit!(Timetracker, :read_hours_records, socket.assigns.current_user)

    {:ok,
     socket
     |> assign(
       projects: Timetracker.list_projects(),
       is_editing_name: false,
       is_editing_users: false
     )}
  end

  @impl true
  def handle_params(%{"id" => project_id} = params, _, socket) do
    {:noreply,
     socket
     |> assign(:selected_project, Enum.find(socket.assigns.projects, &(&1.id == project_id)))
     |> assign(:active_months, Timetracker.get_months_with_sessions_by_project(project_id))
     |> assign_selected_date(params)
     |> load_project_hours()}
  end

  def handle_params(params, _, socket) do
    {:noreply,
     socket
     |> assign(selected_project: nil)
     |> assign(active_months: Timetracker.get_months_with_sessions())
     |> assign_selected_date(params)
     |> assign_hours_records()}
  end

  def handle_event("edit_name", _, %{assigns: %{selected_project: project}} = socket) do
    changeset = project |> Project.form_changeset()

    {:noreply, assign(socket, form: to_form(changeset), is_editing_name: true)}
  end

  def handle_event("edit_users", _, %{assigns: %{selected_project: project}} = socket) do
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

    {:ok, project} = Timetracker.set_users_to_project(project, project_users)

    {:noreply,
     socket
     |> load_project_hours()
     |> assign(
       is_editing_users: false,
       selected_project: project,
       users: nil,
       project_users: nil
     )}
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
    params = %{"month" => Date.to_iso8601(socket.assigns.selected_date)}
    {:noreply, push_patch(socket, to: ~p"/czasosledz/projekty?#{params}")}
  end

  def handle_event("select_project", %{"selected_project" => ""}, socket) do
    params = %{"month" => Date.to_iso8601(socket.assigns.selected_date)}
    {:noreply, push_patch(socket, to: ~p"/czasosledz/projekty?#{params}")}
  end

  def handle_event("select_project", %{"selected_project" => project_id}, socket) do
    params = %{"month" => Date.to_iso8601(socket.assigns.selected_date)}
    {:noreply, push_patch(socket, to: ~p"/czasosledz/projekty/#{project_id}?#{params}")}
  end

  @impl true
  def handle_event("change-month", %{"month" => month_string}, socket) do
    params = %{"month" => month_string}
    project = socket.assigns.selected_project

    path =
      if project do
        ~p"/czasosledz/projekty/#{project.id}?#{params}"
      else
        ~p"/czasosledz/projekty?#{params}"
      end

    {:noreply, push_patch(socket, to: path)}
  end

  defp assign_project_users(socket, project_users) do
    assign(socket,
      users:
        Timetracker.list_users_with_projects()
        |> Enum.map(&Accounts.get_user_with_avatar/1)
        |> Enum.reject(fn user ->
          Enum.any?(project_users, &(&1.id == user.id))
        end)
        |> Enum.sort_by(& &1.name),
      project_users: project_users
    )
  end

  defp assign_selected_date(socket, params) do
    date =
      case Map.get(params, "month") do
        nil -> Date.utc_today()
        month -> Date.from_iso8601!(month)
      end

    assign(socket, selected_date: date)
  end

  defp assign_hours_records(socket) do
    date = socket.assigns.selected_date

    socket
    |> assign(
      total_time_worked: Timetracker.get_total_time_worked(date.month, date.year),
      most_demanding_project: Timetracker.get_most_demanding_project(date.month, date.year)
    )
    |> stream(
      :hours_records,
      Timetracker.get_month_hours_records(date.month, date.year)
      |> Enum.map(&Map.put(&1, :id, &1.user.id))
      |> Enum.map(&Map.put(&1, :user, Accounts.get_user_with_avatar(&1.user))),
      reset: true
    )
  end

  defp load_project_hours(%{assigns: %{selected_project: nil}} = socket) do
    socket
    |> stream(:project_user_hours, [])
    |> assign(:total_time_worked, 0)
  end

  defp load_project_hours(socket) do
    date = socket.assigns.selected_date
    project_id = socket.assigns.selected_project.id

    project_user_hours =
      Timetracker.get_month_summary_by_project(project_id, date.month, date.year)
      |> Enum.map(fn %{user: u, time_worked: t, removed_from_project: r} ->
        Accounts.get_user_with_avatar(u)
        |> Map.put(:time_worked, t)
        |> Map.put(:removed_from_project, r)
      end)

    total_project_seconds = Enum.sum_by(project_user_hours, & &1.time_worked)

    most_active_user =
      project_user_hours
      |> Enum.max_by(& &1.time_worked, fn -> nil end)

    socket
    |> stream(:project_user_hours, project_user_hours, reset: true)
    |> assign(:total_time_worked, total_project_seconds)
    |> assign(:most_active_user, most_active_user)
  end

  def format_duration(0), do: "0 h 0 min"

  def format_duration(seconds) when seconds < 60 do
    "#{seconds} s"
  end

  def format_duration_with_days(0), do: "0 d 0 h 0 min"

  def format_duration_with_days(seconds) when seconds < 60 do
    "#{seconds} s"
  end

  defdelegate format_duration(seconds), to: TimeFormatter
  defdelegate format_duration_with_days(seconds), to: TimeFormatter

  attr :project_user_hours, :list, required: true

  defp render_project_user_hours(assigns) do
    ~H"""
    <%= for {id, user} <- @project_user_hours do %>
      <div
        id={id}
        class={
          classes([
            "flex items-center bg-white rounded-md p-4 justify-between col-span-full",
            user.removed_from_project && "bg-white/50 border border-greyButtonBg/50"
          ])
        }
      >
        <.render_profile user={user} />
        <span>{trunc(user.time_worked / 60 / 60)} h</span>
      </div>
    <% end %>

    <div class="hidden only:block py-8 bg-white rounded-md text-center text-darkGrey text-sm col-span-full">
      Brak danych o czasie pracy dla tego projektu.
    </div>
    """
  end

  attr :project_users, :list, required: true
  attr :users, :list, required: true

  defp render_project_edit(assigns) do
    ~H"""
    <%= for user <- @project_users do %>
      <div class="flex items-center bg-white rounded-md p-4 justify-between col-span-full">
        <.render_profile user={user} />
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

  defp render_hours_records(assigns) do
    ~H"""
    <div
      :for={{id, %{user: user, hours_record: record}} <- @hours_records}
      class="grid grid-cols-subgrid col-span-full"
    >
      <div id={id} class="flex items-center bg-white rounded-md p-4 justify-between">
        <.render_profile user={user} />
        <span :if={record}>{trunc(record.number_of_hours)} h</span>
      </div>
      <div class="bg-white rounded-md p-4 justify-between items-center flex gap-5">
        <%= if record do %>
          <div class="text-greenText bg-greenBg pl-2 pr-1 py-[5px] rounded-md flex items-center justify-center gap-1">
            <span class="text-[11px] font-semibold">
              EWIDENCJA
            </span>
            <.icon name="hero-check-micro" />
          </div>
          <a
            href={~p"/czasosledz/ewidencja/#{record.id}"}
            download={"Ewidencja_#{record.year}_#{record.month}_#{user.name || user.email}.pdf"}
            class="py-1 px-2 transition hover:bg-greyButtonBg rounded-md inline-flex items-center justify-center"
          >
            <.icon name="hero-arrow-down-tray-micro" class="text-darkGrey" />
          </a>
        <% else %>
          <div class="text-greenText bg-greyButtonBg px-2 py-[5px] rounded-md flex items-center justify-between gap-1 flex-1">
            <span class="text-[11px] font-semibold">
              BRAK
            </span>
            <.icon name="hero-x-mark-micro" />
          </div>
          <div class="py-1 px-2 invisible">
            <.icon name="hero-arrow-down-tray-micro" class="text-darkGrey" />
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  attr :user, :map, required: true

  defp render_profile(assigns) do
    ~H"""
    <div class="flex items-center gap-6">
      <.avatar class="size-8 ring-1 ring-greyButtonBg/50">
        <.avatar_image src={@user.avatar_url} alt="Avatar" />
        <.avatar_fallback class="bg-blueBg text-blueText">
          {String.slice(@user.name || @user.email || "", 0, 1) |> String.upcase()}
        </.avatar_fallback>
      </.avatar>
      <span class="text-darkGrey">
        {@user.name || @user.email}
      </span>
    </div>
    """
  end
end
