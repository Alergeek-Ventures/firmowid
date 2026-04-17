defmodule FirmowidWeb.Management.Views.ProjectForm do
  @moduledoc false
  use FirmowidWeb, :live_view

  import FirmowidWeb.DesignSystem.Components.Button
  import FirmowidWeb.DesignSystem.Components.CoreComponents, except: [button: 1]
  import FirmowidWeb.DesignSystem.Components.Link
  import Phoenix.Component, except: [link: 1]

  alias Firmowid.Ash.Core
  alias Firmowid.Ash.Timetracker.Project, as: AshProject

  @impl true
  def mount(_params, _session, %{assigns: %{live_action: :new}} = socket) do
    scope = socket.assigns.ash_scope

    form =
      AshProject
      |> AshPhoenix.Form.for_create(:create, scope: scope, as: "project")
      |> to_form()

    {:ok, assign_form_view(socket, nil, form)}
  end

  def mount(%{"id" => id}, _session, %{assigns: %{live_action: :edit}} = socket) do
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

  def handle_event("save", %{"project" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.form,
           params: project_params(params, socket.assigns.project_users)
         ) do
      {:ok, project} ->
        {:noreply, push_navigate(socket, to: ~p"/zarzadzanie/projekty/#{project.id}")}

      {:error, form} ->
        {:noreply, assign(socket, :form, to_form(form))}
    end
  end

  def handle_event("add_user", %{"user_id" => user_id}, socket) do
    case Enum.find(socket.assigns.available_users, &(&1.id == user_id)) do
      nil ->
        {:noreply, socket}

      user ->
        project_users = [
          %{user: user, removed_from_project: false} | socket.assigns.project_users
        ]

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

    project_users =
      case project do
        nil ->
          []

        project ->
          # Current members from the loaded relationship
          member_ids = MapSet.new(project.users, & &1.id)

          # Users with sessions for this project (may include removed members)
          session_user_ids =
            Firmowid.Ash.Timetracker.Session
            |> Ash.Query.for_read(:list, %{project_id: project.id}, scope: scope)
            |> Ash.read!(scope: scope)
            |> MapSet.new(& &1.user_id)

          all_ids = MapSet.union(member_ids, session_user_ids)

          users_by_id = Map.new(project.users, &{&1.id, &1})

          all_ids
          |> Enum.map(fn uid ->
            user = resolve_user(uid, users_by_id, scope)

            user_with_avatar =
              Ash.load!(user, [avatar_blob: [:url]], scope: scope)

            %{user: user_with_avatar, removed_from_project: not MapSet.member?(member_ids, uid)}
          end)
          |> Enum.sort_by(&{&1.removed_from_project, &1.user.name, &1.user.email})
      end

    socket
    |> assign(:project, project)
    |> assign(:form, form)
    |> assign_edit_users(project_users)
  end

  defp assign_edit_users(socket, project_users) do
    scope = socket.assigns.ash_scope

    available_users =
      scope
      |> list_users_with_projects()
      |> Enum.map(fn user ->
        Ash.load!(user, [avatar_blob: [:url]], scope: scope)
      end)
      |> Enum.reject(fn user ->
        Enum.any?(project_users, fn %{user: project_user} -> project_user.id == user.id end)
      end)
      |> Enum.sort_by(&{&1.name, &1.email})

    socket
    |> assign(:project_users, project_users)
    |> assign(:available_users, available_users)
  end

  defp project_params(params, project_users) do
    user_ids =
      project_users
      |> Enum.reject(& &1.removed_from_project)
      |> Enum.map(& &1.user.id)

    Map.put(params, "user_ids", user_ids)
  end

  # Resolve a user by ID: prefer already-loaded project members, fall back to Core.
  defp resolve_user(uid, users_by_id, scope) do
    case Map.get(users_by_id, uid) do
      nil -> Core.get_org_user!(%{id: uid}, scope: scope)
      u -> u
    end
  end

  # User-centric query using Ash Core domain
  defp list_users_with_projects(scope) do
    Core.list_users!(%{status: :active}, scope: scope)
  end
end
