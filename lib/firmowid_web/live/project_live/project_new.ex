defmodule FirmowidWeb.Project.ProjectNew do
  @moduledoc false
  use FirmowidWeb, :live_view

  alias Firmowid.Analytics
  alias Firmowid.Timetracker
  alias Firmowid.Timetracker.Project

  @impl true
  def mount(_params, _session, socket) do
    Bodyguard.permit!(Timetracker, :create_project, socket.assigns.current_user)

    {:ok, assign(socket, form: to_form(Project.form_changeset()))}
  end

  @impl true
  def handle_event("validate", %{"project" => params}, socket) do
    {:noreply, assign(socket, form: params |> Project.form_changeset() |> to_form(action: :validate))}
  end

  def handle_event("save", %{"project" => params}, socket) do
    Bodyguard.permit!(Timetracker, :create_project, socket.assigns.current_user)

    case Timetracker.create_project(params) do
      {:ok, _project} ->
        Analytics.track_event("project_create", socket.assigns.current_user, %{})

        {:noreply, redirect(socket, to: ~p"/czasosledz/projekty")}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end
end
