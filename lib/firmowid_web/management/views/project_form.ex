defmodule FirmowidWeb.Management.Views.ProjectForm do
  @moduledoc false
  use FirmowidWeb, :live_view

  alias Firmowid.Accounts
  alias Firmowid.Ash.Timetracker.Project, as: AshProject

  @impl true
  def mount(_params, _session, %{assigns: %{live_action: :new}} = socket) do
    Bodyguard.permit!(Firmowid.Management, :read_projects, socket.assigns.current_user)
    scope = socket.assigns.ash_scope

    form =
      AshProject
      |> AshPhoenix.Form.for_create(:create, scope: scope, as: "project")
      |> to_form()

    {:ok, assign_form_view(socket, nil, form)}
  end

  def mount(%{"id" => id}, _session, %{assigns: %{live_action: :edit}} = socket) do
    Bodyguard.permit!(Firmowid.Management, :read_projects, socket.assigns.current_user)
    scope = socket.assigns.ash_scope

    case AshProject.get(id, scope: scope, not_found_error?: false) do
      {:ok, nil} ->
        {:ok, push_navigate(socket, to: ~p"/zarzadzanie/projekty")}

      {:ok, project} ->
        form =
          project
          |> AshPhoenix.Form.for_update(:update, scope: scope, as: "project")
          |> to_form()

        {:ok, assign_form_view(socket, project, form)}
    end
  end

  @impl true
  def handle_event("validate", %{"project" => params}, socket) do
    form =
      socket.assigns.form
      |> AshPhoenix.Form.validate(params)
      |> to_form()

    {:noreply, assign(socket, :form, form)}
  end

  def handle_event("save", %{"project" => params}, %{assigns: %{live_action: :new}} = socket) do
    case AshPhoenix.Form.submit(socket.assigns.form, params: params) do
      {:ok, project} ->
        case set_project_users(project, socket.assigns.project_users, socket.assigns.ash_scope) do
          :ok ->
            {:noreply, push_navigate(socket, to: ~p"/zarzadzanie/projekty/#{project.id}")}

          :error ->
            LiveToast.send_toast(:error, "Nie udało się zapisać pracowników")
            {:noreply, socket}
        end

      {:error, form} ->
        {:noreply, assign(socket, :form, to_form(form))}
    end
  end

  def handle_event("save", %{"project" => params}, %{assigns: %{live_action: :edit}} = socket) do
    case AshPhoenix.Form.submit(socket.assigns.form, params: params) do
      {:ok, project} ->
        case set_project_users(project, socket.assigns.project_users, socket.assigns.ash_scope) do
          :ok ->
            {:noreply, push_navigate(socket, to: ~p"/zarzadzanie/projekty/#{project.id}")}

          :error ->
            LiveToast.send_toast(:error, "Nie udało się zapisać pracowników")
            {:noreply, socket}
        end

      {:error, form} ->
        {:noreply, assign(socket, :form, to_form(form))}
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

  defp assign_form_view(socket, project, form) do
    scope = socket.assigns.ash_scope
    project_id = if project, do: project.id

    project_users =
      case project_id do
        nil ->
          []

        project_id ->
          {:ok, users} = AshProject.project_users_with_removed(project_id, scope: scope)

          users
          |> Enum.map(fn %{user: user, removed_from_project: removed} ->
            %{
              user: Accounts.get_user_with_avatar(user),
              removed_from_project: removed
            }
          end)
          |> Enum.sort_by(&{&1.removed_from_project, &1.user.name, &1.user.email})
      end

    socket
    |> assign(:project, project)
    |> assign(:form, form)
    |> assign_edit_users(project_users)
  end

  defp assign_edit_users(socket, project_users) do
    available_users =
      list_users_with_projects()
      |> Enum.map(&Accounts.get_user_with_avatar/1)
      |> Enum.reject(fn user ->
        Enum.any?(project_users, fn %{user: project_user} -> project_user.id == user.id end)
      end)
      |> Enum.sort_by(&{&1.name, &1.email})

    socket
    |> assign(:project_users, project_users)
    |> assign(:available_users, available_users)
  end

  defp set_project_users(project, project_users, scope) do
    user_ids =
      project_users
      |> Enum.reject(& &1.removed_from_project)
      |> Enum.map(& &1.user.id)

    case AshProject.set_users(user_ids, %{project_id: project.id}, scope: scope) do
      {:ok, _result} -> :ok
      {:error, _error} -> :error
    end
  end

  # User-centric query — inlined here because the User schema hasn't been migrated
  # to Ash yet. Once Accounts is Ash-native, replace with an Ash read action.
  defp list_users_with_projects do
    Firmowid.Accounts.User
    |> Firmowid.Repo.all()
    |> Firmowid.Repo.preload(:projects)
  end
end
