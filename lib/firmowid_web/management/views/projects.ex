defmodule FirmowidWeb.Management.Views.Projects do
  @moduledoc false
  use FirmowidWeb, :live_view

  alias Firmowid.Ash.Timetracker.Project, as: AshProject
  alias Firmowid.Ash.Timetracker.Session, as: AshSession
  alias Firmowid.SalesInvoices.Counterparty

  @impl true
  def mount(_params, _session, socket) do
    Bodyguard.permit!(Firmowid.Management, :read_projects, socket.assigns.current_user)
    scope = socket.assigns.ash_scope

    {:ok, all_projects} = Ash.read(AshProject, scope: scope)
    {:ok, active_months} = AshSession.months_with_sessions(%{}, scope: scope)

    socket =
      socket
      |> assign(:page_title, "Zarządzanie projektami")
      |> assign(:zero_state?, Enum.empty?(all_projects))
      |> assign(:active_months, active_months)

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    params = Map.take(params, ["month", "q"])

    selected_date =
      case params do
        %{"month" => month} -> Date.from_iso8601!(month)
        _ -> Date.utc_today()
      end

    socket =
      socket
      |> assign(:params, params)
      |> assign(:selected_date, selected_date)
      |> assign_projects()

    {:noreply, socket}
  end

  @impl true
  def handle_event("change-month", %{"month" => month}, socket) do
    params = Map.put(socket.assigns.params, "month", month)
    {:noreply, refresh_page(socket, params)}
  end

  def handle_event("search", %{"q" => search}, socket) do
    params = Map.put(socket.assigns.params, "q", String.trim(search))
    {:noreply, refresh_page(socket, params)}
  end

  def handle_event("unarchive_project", %{"id" => id}, socket) do
    scope = socket.assigns.ash_scope
    project = AshProject.get!(id, scope: scope)

    {:ok, _project} = AshProject.unarchive(project, scope: scope)

    {:noreply, assign_projects(socket)}
  end

  defp assign_projects(socket) do
    scope = socket.assigns.ash_scope
    search = socket.assigns.params["q"] || ""

    {:ok, projects} =
      case socket.assigns.live_action do
        :index ->
          AshProject.list_active(socket.assigns.selected_date, %{search: search}, scope: scope)

        :archive ->
          AshProject.list_archived(%{search: search}, scope: scope)
      end

    assign(socket, :projects, projects)
  end

  defp refresh_page(socket, params) do
    params =
      Map.reject(params, fn
        {_k, ""} -> true
        {_k, v} -> is_nil(v)
      end)

    path =
      case socket.assigns.live_action do
        :index -> ~p"/zarzadzanie/projekty?#{params}"
        :archive -> ~p"/zarzadzanie/projekty/archiwum?#{params}"
      end

    push_patch(socket, to: path)
  end
end
