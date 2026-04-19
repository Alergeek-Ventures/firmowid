defmodule FirmowidWeb.Management.Views.Projects do
  @moduledoc false
  use FirmowidWeb, :live_view

  alias Firmowid.Ash.Timetracker
  alias Firmowid.Ash.Timetracker.Project, as: AshProject
  alias Firmowid.Ash.Timetracker.Session

  import FirmowidWeb.DesignSystem.Components.CoreComponents, except: [button: 1]
  import FirmowidWeb.DesignSystem.Components.Button

  require Ash.Query

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.ash_scope

    all_projects = Timetracker.list_projects!(%{}, scope: scope)
    active_months = months_with_sessions(%{}, scope)

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

    with {:ok, project} <- AshProject.get(id, scope: scope, not_found_error?: false),
         {:ok, _project} <- AshProject.unarchive(project, scope: scope) do
      {:noreply, assign_projects(socket)}
    else
      _ ->
        {:noreply, put_flash(socket, :error, "Nie udało się przywrócić projektu")}
    end
  end

  defp assign_projects(socket) do
    scope = socket.assigns.ash_scope
    date = socket.assigns.selected_date
    search = socket.assigns.params["q"] || ""

    {filter_args, all_time?} =
      case socket.assigns.live_action do
        :index -> {%{status: :active}, false}
        :archive -> {%{status: :archived}, true}
      end

    search_args = if search in [nil, ""], do: %{}, else: %{search: search}
    args = Map.merge(filter_args, search_args)

    month = date.month
    year = date.year

    duration_filter =
      if all_time? do
        Ash.Query.new(Session)
      else
        Ash.Query.filter(
          Session,
          fragment("extract(month from ?) = ?", start_datetime, ^month) and
            fragment("extract(year from ?) = ?", start_datetime, ^year)
        )
      end

    default_sort = if search in [nil, ""], do: [name: :asc], else: []

    projects =
      AshProject
      |> Ash.Query.for_read(:list, args, scope: scope)
      |> Ash.Query.aggregate(:duration, :sum, :sessions,
        field: :duration,
        default: 0,
        query: duration_filter
      )
      |> Ash.Query.load(counterparty: [:display_label])
      |> Ash.Query.sort(default_sort)
      |> Ash.read!(scope: scope)
      |> Enum.map(fn project ->
        seconds = project.aggregates[:duration] || 0
        Map.put(project, :hours, Timetracker.seconds_to_hours(seconds))
      end)

    Firmowid.Repo.drop_paradedb_unnamed()

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

  # Distinct months (as naive_datetime) that have sessions, newest first.
  defp months_with_sessions(filters, scope), do: Timetracker.months_with_sessions(filters, scope)
end
