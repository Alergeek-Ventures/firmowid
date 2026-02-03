defmodule FirmowidWeb.ManagementLive.Projects do
  @moduledoc false
  use FirmowidWeb, :live_view

  alias Firmowid.Management
  alias Firmowid.SalesInvoices.Counterparty
  alias Firmowid.Timetracker

  @impl true
  def mount(_params, _session, socket) do
    Bodyguard.permit!(Management, :read_projects, socket.assigns.current_user)

    socket =
      socket
      |> assign(:page_title, "Zarządzanie projektami")
      |> assign(:zero_state?, Enum.empty?(Timetracker.list_projects()))
      |> assign(:active_months, Timetracker.get_months_with_sessions())

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
    project = Timetracker.get_project!(id)
    Bodyguard.permit!(Timetracker, :update_project, socket.assigns.current_user, project)

    {:ok, _project} = Timetracker.unarchive_project(project)

    {:noreply, assign_projects(socket)}
  end

  defp assign_projects(socket) do
    search = socket.assigns.params["q"] || ""

    projects =
      case socket.assigns.live_action do
        :index -> Timetracker.list_active_projects(socket.assigns.selected_date, search)
        :archive -> Timetracker.list_archived_projects(socket.assigns.selected_date, search)
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
