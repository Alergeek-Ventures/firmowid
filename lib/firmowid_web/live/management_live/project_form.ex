defmodule FirmowidWeb.ManagementLive.ProjectForm do
  @moduledoc false
  use FirmowidWeb, :live_view

  alias Firmowid.Accounts
  alias Firmowid.Timetracker
  alias Firmowid.Timetracker.Project

  @impl true
  def mount(_params, _session, %{assigns: %{live_action: :new}} = socket) do
    Bodyguard.permit!(Timetracker, :create_project, socket.assigns.current_user)
    {:ok, assign_form_view(socket, %Project{})}
  end

  def mount(%{"id" => id}, _session, %{assigns: %{live_action: :edit}} = socket) do
    case Timetracker.get_project(id) do
      nil ->
        {:ok, push_navigate(socket, to: ~p"/zarzadzanie/projekty")}

      project ->
        Bodyguard.permit!(Timetracker, :update_project, socket.assigns.current_user, project)
        {:ok, assign_form_view(socket, project)}
    end
  end

  @impl true
  def handle_event("validate", %{"project" => params}, socket) do
    changeset = Project.changeset(socket.assigns.project, params)
    {:noreply, assign(socket, :form, to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"project" => params}, %{assigns: %{live_action: :new}} = socket) do
    Bodyguard.permit!(Timetracker, :create_project, socket.assigns.current_user)

    case Timetracker.create_project(params) do
      {:ok, project} ->
        case set_project_users(project, socket.assigns.project_users) do
          :ok ->
            {:noreply, push_navigate(socket, to: ~p"/zarzadzanie/projekty/#{project.id}")}

          :error ->
            LiveToast.send_toast(:error, "Nie udało się zapisać pracowników")
            {:noreply, socket}
        end

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  def handle_event("save", %{"project" => params}, %{assigns: %{live_action: :edit}} = socket) do
    project = socket.assigns.project
    Bodyguard.permit!(Timetracker, :update_project, socket.assigns.current_user, project)

    case Timetracker.update_project(project, params) do
      {:ok, project} ->
        case set_project_users(project, socket.assigns.project_users) do
          :ok ->
            {:noreply, push_navigate(socket, to: ~p"/zarzadzanie/projekty/#{project.id}")}

          :error ->
            LiveToast.send_toast(:error, "Nie udało się zapisać pracowników")
            {:noreply, socket}
        end

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  def handle_event("add_user", %{"user_id" => user_id}, socket) do
    case Enum.find(socket.assigns.available_users, &(&1.id == user_id)) do
      nil ->
        {:noreply, socket}

      user ->
        project_users = [%{user: user, removed_from_project: false} | socket.assigns.project_users]
        {:noreply, assign_edit_users(socket, project_users)}
    end
  end

  def handle_event("remove_user", %{"user_id" => user_id}, socket) do
    project_users =
      Enum.map(socket.assigns.project_users, fn entry ->
        case entry.user.id do
          ^user_id -> %{entry | removed_from_project: true}
          _ -> entry
        end
      end)

    {:noreply, assign_edit_users(socket, project_users)}
  end

  def handle_event("restore_user", %{"user_id" => user_id}, socket) do
    project_users =
      Enum.map(socket.assigns.project_users, fn entry ->
        case entry.user.id do
          ^user_id -> %{entry | removed_from_project: false}
          _ -> entry
        end
      end)

    {:noreply, assign_edit_users(socket, project_users)}
  end

  defp assign_form_view(socket, project) do
    project_users =
      case project.id do
        nil ->
          []

        project_id ->
          project_id
          |> Timetracker.get_project_users_with_removed()
          |> Enum.map(fn user ->
            %{
              user: Accounts.get_user_with_avatar(user),
              removed_from_project: user.removed_from_project
            }
          end)
          |> Enum.sort_by(&{&1.removed_from_project, &1.user.name, &1.user.email})
      end

    socket
    |> assign(:project, project)
    |> assign(:form, project |> Project.changeset(%{}) |> to_form())
    |> assign_edit_users(project_users)
  end

  defp assign_edit_users(socket, project_users) do
    available_users =
      Timetracker.list_users_with_projects()
      |> Enum.map(&Accounts.get_user_with_avatar/1)
      |> Enum.reject(fn user ->
        Enum.any?(project_users, fn %{user: project_user} -> project_user.id == user.id end)
      end)
      |> Enum.sort_by(&{&1.name, &1.email})

    socket
    |> assign(:project_users, project_users)
    |> assign(:available_users, available_users)
  end

  defp set_project_users(project, project_users) do
    user_ids =
      project_users
      |> Enum.reject(& &1.removed_from_project)
      |> Enum.map(& &1.user.id)

    case Timetracker.set_users_to_project(project, user_ids) do
      {:ok, _project} -> :ok
      {:error, _changeset} -> :error
    end
  end
end
