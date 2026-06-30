defmodule FirmowidWeb.Management.Components.ProjectsTab do
  @moduledoc "LiveComponent for displaying employee projects, sessions, and salary summary."
  use FirmowidWeb, :live_component

  import FirmowidWeb.DesignSystem.Components.MonthPicker
  import FirmowidWeb.Management.Components.Card
  import FirmowidWeb.Management.Components.HoursRecordStatus, only: [hours_record_status: 1]

  alias Firmowid.Ash.Payroll
  alias Firmowid.Ash.Timetracker
  alias Firmowid.Ash.Timetracker.Session
  alias FirmowidWeb.Infrastructure.Utilities.TimeFormatter

  @impl true
  def mount(socket) do
    {:ok, socket}
  end

  @impl true
  def update(assigns, socket) do
    user = assigns.user
    user_id = user.id
    date = assigns.date
    scope = assigns.scope

    # 1. Sessions for this user+month, grouped by project+title
    sessions =
      Session
      |> Ash.Query.for_read(:list, %{user_id: user_id, month: date.month, year: date.year}, scope: scope)
      |> Ash.Query.load(:duration)
      |> Ash.read!(scope: scope)

    # 2. Group sessions by project_id, then by project+title for display
    sessions_by_project =
      sessions
      |> Enum.group_by(& &1.project_id)
      |> Map.new(fn {pid, ss} ->
        grouped =
          ss
          |> Enum.group_by(& &1.title)
          |> Enum.map(fn {title, title_sessions} ->
            %{title: title, duration: title_sessions |> Enum.map(& &1.duration) |> Enum.sum()}
          end)
          |> Enum.sort_by(& &1.duration, :desc)

        {pid, grouped}
      end)

    # 3. Projects this user belongs to, with grouped sessions attached
    projects =
      %{user_id: user_id}
      |> Timetracker.list_projects!(scope: scope)
      |> Enum.map(fn project ->
        Map.put(project, :sessions, Map.get(sessions_by_project, project.id, []))
      end)

    # 4. Salary as of this month
    before_date = Date.end_of_month(date)

    salaries = Payroll.list_salaries!(%{user_id: user.id, active_at: before_date}, scope: scope)

    salary_history = Payroll.list_salaries!(%{user_id: user.id}, scope: scope, load: [:ends_at])

    hourly_rate =
      salaries
      |> List.first()
      |> case do
        nil -> Decimal.new(0)
        salary -> salary.hourly_rate
      end

    # 5. Hours record for this month
    hours_record =
      %{user_id: user_id, month: date.month, year: date.year}
      |> Timetracker.list_hours_records!(scope: scope)
      |> List.first()

    # 6. Total time worked
    total_time = sessions |> Enum.map(& &1.duration) |> Enum.sum()

    socket =
      socket
      |> assign(assigns)
      |> assign(:projects, projects)
      |> assign(:hourly_rate, hourly_rate)
      |> assign(:hours_record, hours_record)
      |> assign(:time_worked, total_time)
      |> assign(:salary_history, salary_history)

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex h-full min-h-0 flex-col gap-6">
      <.card class="relative z-10" dimmed={@user.archived_at}>
        <%!-- TODO: allow editing the user wage --%>
        <.card_header>
          Dane do przelewu
        </.card_header>
        <div class="grid grid-cols-[minmax(min-content,1fr)_minmax(min-content,2fr)] gap-4">
          <.user_card_info label="Stawka">
            {:PLN
            |> Money.new(@hourly_rate)
            |> Money.to_string!(no_fraction_if_integer: true)}/godz.
          </.user_card_info>
          <.user_card_info label="Numer konta bankowego">
            {@user.bank_account_number || "Brak danych"}
          </.user_card_info>
        </div>
      </.card>

      <div class="flex min-h-0 flex-1 gap-6">
        <.card :if={!@user.archived_at} class="flex min-h-0 grow flex-col">
          <div class="flex shrink-0 items-center justify-between">
            <.card_header>
              Projekty pracownika
            </.card_header>
            <.month_picker
              id="projects_filter_month"
              selected_date={@date}
              active_months={@active_months}
            />
          </div>

          <div class="relative w-full flex-1">
            <div class="divide-lightGreyBg absolute inset-0 divide-y overflow-y-auto pr-2">
              <%= if Enum.empty?(@projects) do %>
                <div class="text-darkGrey mt-4 text-sm">Brak projektów</div>
              <% else %>
                <.project_accordion :for={project <- @projects} project={project} />
              <% end %>
            </div>
          </div>
        </.card>

        <div class="flex w-[350px] shrink-0 flex-col gap-4">
          <.card>
            <.card_header>
              Podsumowanie miesiąca
            </.card_header>
            <div class="flex flex-col gap-4">
              <.user_card_info label="Przepracowano">
                <span class="text-turquoise-700 font-medium">
                  {Timetracker.seconds_to_hours(@time_worked)} godz.
                </span>
              </.user_card_info>
              <.user_card_info label="Wynagrodzenie">
                <span class="text-turquoise-700 font-medium">
                  {:PLN
                  |> Money.new(
                    Decimal.mult(
                      @hourly_rate,
                      Decimal.new(Timetracker.seconds_to_hours(@time_worked))
                    )
                  )
                  |> Money.to_string!(no_fraction_if_integer: true, currency_symbol: "PLN")}
                </span>
              </.user_card_info>
            </div>
          </.card>

          <.card gap_size="4">
            <.card_header>
              Ewidencja
            </.card_header>
            <div class="flex gap-3">
              <.hours_record_status hours_record={@hours_record} user={@user} />
            </div>
          </.card>

          <.card gap_size="4">
            <.card_header>
              Historia stawek
            </.card_header>
            <div class="flex flex-col gap-2">
              <%= if Enum.empty?(@salary_history) do %>
                <p class="text-grey-700">Brak danych</p>
              <% else %>
                <div :for={salary <- @salary_history} class="flex items-end gap-2">
                  <span>
                    {:PLN
                    |> Money.new(salary.hourly_rate)
                    |> Money.to_string!(no_fraction_if_integer: true)}/godz.
                  </span>
                  <span class="text-grey-500 text-sm">
                    ({TimeFormatter.format_date(salary.starts_at)} - {if salary.ends_at,
                      do: TimeFormatter.format_date(salary.ends_at),
                      else: "obecnie"})
                  </span>
                </div>
              <% end %>
            </div>
          </.card>
        </div>
      </div>
    </div>
    """
  end

  attr :project, :map, required: true

  defp project_accordion(assigns) do
    ~H"""
    <div
      id={"project-accordion-#{@project.id}"}
      class="group grid grid-cols-[1fr_min-content_min-content] gap-x-6 overflow-hidden"
    >
      <FirmowidWeb.DesignSystem.Components.Button.button
        type="button"
        variant="unstyled"
        phx-click={toggle_project_accordion(@project.id)}
        class="group col-span-full grid w-full cursor-pointer grid-cols-subgrid items-center gap-x-6 py-4 text-left"
      >
        <span class="text-start text-nowrap">{@project.name}</span>
        <span class="text-nowrap">
          {@project.sessions
          |> Enum.map(& &1.duration)
          |> Enum.sum()
          |> Timetracker.seconds_to_hours()} h
        </span>
        <.icon
          name="hero-chevron-down"
          class="size-4 transition-transform duration-200 ease-in-out group-data-expanded:rotate-180"
        />
      </FirmowidWeb.DesignSystem.Components.Button.button>
      <div
        class="col-span-2 grid grid-rows-[0fr] overflow-hidden transition-[grid-template-rows] duration-300 ease-in-out group-data-expanded:grid-rows-[1fr]"
        role="region"
      >
        <div class="ml-4 flex flex-col gap-y-2 overflow-hidden *:last:mb-4">
          <%= if Enum.empty?(@project.sessions) do %>
            <p class="text-grey-700">
              Brak sesji w tym miesiącu
            </p>
          <% else %>
            <div
              :for={session <- @project.sessions}
              class="text-grey-700 flex justify-between text-base/snug"
            >
              <p class="truncate text-nowrap">{session.title}</p>
              <p>
                {Timetracker.seconds_to_hours(session.duration)} h
              </p>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  defp toggle_project_accordion(js \\ %JS{}, project_id) do
    JS.toggle_attribute(js, {"data-expanded", "true"}, to: "#project-accordion-#{project_id}")
  end
end
