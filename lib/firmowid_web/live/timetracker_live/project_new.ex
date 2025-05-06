defmodule FirmowidWeb.TimetrackerLive.ProjectNew do
  use FirmowidWeb, :live_view
  alias Firmowid.Timetracker
  alias Firmowid.Timetracker.Project

  @impl true
  def mount(_params, _session, socket) do
    Bodyguard.permit!(Timetracker, :create_project, socket.assigns.current_user)

    {:ok, assign(socket, form: to_form(Project.form_changeset()))}
  end

  @impl true
  def handle_event("validate", %{"project" => params}, socket) do
    {:noreply, assign(socket, form: Project.form_changeset(params) |> to_form(action: :validate))}
  end

  def handle_event("save", %{"project" => params}, socket) do
    case Timetracker.create_project(params) do
      {:ok, _project} ->
        {:noreply, redirect(socket, to: ~p"/czasosledz/projekty")}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end
end
