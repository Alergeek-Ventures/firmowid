defmodule FirmowidWeb.TimetrackerLive.Projects do
  alias Firmowid.Accounts
  alias Firmowid.Timetracker
  use FirmowidWeb, :live_view

  def mount(_params, _session, socket) do
    project_list = Timetracker.list_users_with_projects()

    {:ok,
     assign(socket,
       users: project_list |> Enum.map(&Accounts.get_user_with_avatar/1),
       projects: Timetracker.list_projects_with_users()
     )}
  end

  def handle_event(
        "toggle_project",
        %{"_target" => ["project", project_id, user_id]},
        socket
      ) do
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
end
