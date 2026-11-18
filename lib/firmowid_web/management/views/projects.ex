defmodule FirmowidWeb.Management.Views.Projects do
  @moduledoc false
  use FirmowidWeb, :live_view

  import FirmowidUI.Components.Button
  import FirmowidUI.Components.Link
  import FirmowidWeb.DesignSystem.Components.EmptyState
  import FirmowidWeb.Management.Components.ListToolbar
  import Phoenix.Component, except: [link: 1]

  alias Firmowid.TimeFormatter
  alias Firmowid.Timetracker
  alias Firmowid.Timetracker.Project
  alias Firmowid.Timetracker.Session
  alias FirmowidWeb.Management.Utilities.CounterpartyHelpers
  alias FirmowidWeb.Management.Utilities.Navigation

  require Ash.Query

  on_mount {FirmowidWeb.Infrastructure.Hooks.RequireAdmin, :default}

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.ash_scope

    all_projects = Timetracker.list_projects!(%{}, scope: scope)
    active_months = Timetracker.months_with_sessions(%{}, scope)

    socket =
      socket
      |> assign(:page_title, gettext("Project management"))
      # The page spaces itself, as in the design (see `projects.html.heex`).
      |> assign(:no_padding, true)
      |> assign(:zero_state?, Enum.empty?(all_projects))
      |> assign(:active_months, active_months)

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    params = Navigation.projects_params(params)
    selected_date = Navigation.parse_month(params)

    socket =
      socket
      |> assign(:params, params)
      |> assign(:selected_date, selected_date)
      |> assign(:search, params["szukaj"] || "")
      |> assign_projects()

    {:noreply, socket}
  end

  @impl true
  def handle_event("change-month", %{"month" => month}, socket) do
    params = Map.put(socket.assigns.params, "miesiac", month)
    {:noreply, refresh_page(socket, params)}
  end

  def handle_event("search", %{"szukaj" => search}, socket) do
    params = Map.put(socket.assigns.params, "szukaj", String.trim(search))
    {:noreply, refresh_page(socket, params)}
  end

  def handle_event("unarchive_project", %{"id" => id}, socket) do
    scope = socket.assigns.ash_scope

    with {:ok, project} <- Project.get(id, scope: scope, not_found_error?: false),
         {:ok, _project} <- Project.unarchive(project, scope: scope) do
      {:noreply, assign_projects(socket)}
    else
      _ ->
        {:noreply, put_flash(socket, :error, gettext("Could not restore the project"))}
    end
  end

  defp assign_projects(socket) do
    scope = socket.assigns.ash_scope
    date = socket.assigns.selected_date
    search = socket.assigns.search

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
      args
      |> Timetracker.query_to_list_projects(scope: scope)
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
        Map.put(project, :duration, seconds)
      end)

    Firmowid.Repo.drop_paradedb_unnamed()

    assign(socket, :projects, projects)
  end

  attr :selected_date, Date, required: true
  attr :projects, :list, required: true

  # Figma "Ten miesiąc": the listed month in numbers, beside the table on wide screens.
  defp month_summary(assigns) do
    total = length(assigns.projects)

    assigns =
      assign(assigns,
        title: Firmowid.Cldr.Date.to_string!(assigns.selected_date, format: "LLLL y"),
        rows: [
          {pgettext("projects month", "Hours in projects"), total_duration_text(assigns.projects)},
          {pgettext("projects month", "Active projects"), total},
          {pgettext("projects month", "With hours this month"),
           pgettext("projects month", "%{count} of %{total}",
             count: Enum.count(assigns.projects, &(&1.duration >= 60)),
             total: total
           )}
        ]
      )

    ~H"""
    <.summary_card title={@title} rows={@rows} />
    """
  end

  attr :projects, :list, required: true

  # Figma "Archiwum": the archive in numbers, its hours counted over the projects' whole life.
  defp archive_summary(assigns) do
    last_archived_on = assigns.projects |> Enum.map(& &1.archived_at) |> Enum.max(Date)

    assigns =
      assign(assigns,
        rows: [
          {pgettext("projects archive", "Archived projects"), length(assigns.projects)},
          {pgettext("projects archive", "Total hours"), total_duration_text(assigns.projects)},
          {pgettext("projects archive", "Last archived"), Calendar.strftime(last_archived_on, "%d.%m.%Y")}
        ]
      )

    ~H"""
    <.summary_card title={pgettext("projects archive", "Archive")} rows={@rows} />
    """
  end

  attr :title, :string, required: true
  attr :rows, :list, required: true, doc: "`{label, value}` pairs"

  defp summary_card(assigns) do
    ~H"""
    <section class="flex flex-col gap-4 rounded-sm bg-white p-5">
      <h2 class="text-caps-sm/[normal] font-medium text-grey-600 uppercase">{@title}</h2>
      <dl class="flex flex-col gap-2">
        <div :for={{label, value} <- @rows} class="flex items-baseline justify-between gap-3 text-sm">
          <dt class="truncate leading-[1.35] text-grey-700">{label}</dt>
          <dd class="shrink-0 leading-[normal] font-medium text-grey-900 tabular-nums">{value}</dd>
        </div>
      </dl>
    </section>
    """
  end

  # Figma "Przywracanie": what restoring a project does.
  defp restoring_hint(assigns) do
    ~H"""
    <section class="flex flex-col gap-4 rounded-sm bg-white p-5">
      <h2 class="text-caps-sm/[normal] font-medium text-grey-600 uppercase">
        {pgettext("projects archive", "Restoring")}
      </h2>
      <p class="text-sm/[1.35] text-grey-500">
        {gettext(
          "A restored project returns to the active list with its whole history of hours, and the team can assign time to it again."
        )}
      </p>
    </section>
    """
  end

  attr :projects, :list, required: true
  attr :month, :integer, required: true
  attr :params, :map, required: true

  # Figma "Bez godzin": the active projects nobody worked on in the month, the candidates for the
  # archive. Hidden when every project has hours.
  defp projects_without_hours(assigns) do
    assigns = assign(assigns, :idle, Enum.filter(assigns.projects, &(&1.duration < 60)))

    ~H"""
    <section :if={@idle != []} class="flex flex-col gap-4 rounded-sm bg-white p-5">
      <header class="flex items-center justify-between gap-3 text-grey-600">
        <h2 class="text-caps-sm/[normal] font-medium uppercase">
          {no_hours_title(@month)}
        </h2>
        <span class="text-sm/[1.35] tabular-nums">{length(@idle)}</span>
      </header>
      <ul class="flex flex-col gap-2">
        <li :for={project <- @idle} class="min-w-0">
          <.link
            kind="unstyled"
            navigate={Navigation.project_path(project.id, Map.take(@params, ["miesiac"]))}
            class="block truncate text-sm/[1.35] text-grey-900 hover:underline"
          >
            {project.name}
          </.link>
        </li>
      </ul>
      <p class="text-sm/[1.35] text-grey-500">
        {gettext("If a project has ended, you can archive it.")}
      </p>
    </section>
    """
  end

  # Polish and Ukrainian decline the month here ("w listopadzie"), so each month is its own text.
  defp no_hours_title(1), do: pgettext("projects month", "No hours in January")
  defp no_hours_title(2), do: pgettext("projects month", "No hours in February")
  defp no_hours_title(3), do: pgettext("projects month", "No hours in March")
  defp no_hours_title(4), do: pgettext("projects month", "No hours in April")
  defp no_hours_title(5), do: pgettext("projects month", "No hours in May")
  defp no_hours_title(6), do: pgettext("projects month", "No hours in June")
  defp no_hours_title(7), do: pgettext("projects month", "No hours in July")
  defp no_hours_title(8), do: pgettext("projects month", "No hours in August")
  defp no_hours_title(9), do: pgettext("projects month", "No hours in September")
  defp no_hours_title(10), do: pgettext("projects month", "No hours in October")
  defp no_hours_title(11), do: pgettext("projects month", "No hours in November")
  defp no_hours_title(12), do: pgettext("projects month", "No hours in December")

  # A duration such as "61 h 30 min"; less than a minute reads "0 h" (Figma "Wiersz projektu").
  defp duration_text(seconds) when seconds < 60, do: pgettext("duration", "%{hours} h", hours: 0)
  defp duration_text(seconds), do: TimeFormatter.format_duration(seconds)

  defp total_duration_text(projects), do: projects |> Enum.map(& &1.duration) |> Enum.sum() |> duration_text()

  # The parts of a duration, such as `[["61", "h"], ["30", "min"]]`, so the units can be set apart.
  defp duration_parts(seconds) do
    Regex.scan(~r/(\d+)\s(\S+)/u, duration_text(seconds), capture: :all_but_first)
  end

  defp refresh_page(socket, params) do
    params =
      Map.reject(params, fn
        {_k, ""} -> true
        {_k, v} -> is_nil(v)
      end)

    push_patch(socket, to: Navigation.projects_path(socket.assigns.live_action, params))
  end
end
