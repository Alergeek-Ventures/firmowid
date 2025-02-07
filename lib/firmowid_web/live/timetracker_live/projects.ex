defmodule FirmowidWeb.TimetrackerLive.Projects do
  alias Firmowid.Accounts
  alias Firmowid.Timetracker
  alias Firmowid.Timetracker.Project
  use FirmowidWeb, :live_view

  def mount(_params, _session, socket) do
    Bodyguard.permit!(Timetracker, :read_projects, socket.assigns.current_user)

    {:ok,
     assign(socket,
       users:
         Timetracker.list_users_with_projects() |> Enum.map(&Accounts.get_user_with_avatar/1),
       projects: Timetracker.list_projects_with_users(),
       show_modal: false,
       form: to_form(Project.form_changeset()),
       editing_project: nil
     )}
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
end
