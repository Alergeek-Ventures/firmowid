defmodule FirmowidWeb.Management.Views.Employee do
  @moduledoc false
  use FirmowidWeb, :live_view

  import FirmowidWeb.Management.Views.Employees, only: [hours_record_status: 1]

  alias Firmowid.Ash.Core
  alias Firmowid.Ash.Payroll.UserSalary, as: AshUserSalary
  alias Firmowid.Ash.Timetracker
  alias Firmowid.Ash.Timetracker.Session
  alias FirmowidWeb.Infrastructure.Utilities.TimeFormatter

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(%{"id" => id} = params, _uri, socket) do
    scope = socket.assigns.ash_scope

    selected_date =
      case params do
        %{"month" => month} -> Date.from_iso8601!(month)
        _ -> Date.utc_today()
      end

    user = Core.get_user!(id, scope: scope, not_found_error?: false)

    socket =
      if is_nil(user) do
        push_navigate(socket, to: ~p"/zarzadzanie/pracownicy")
      else
        employee = build_employee(user, id, selected_date, scope)
        active_months = months_with_sessions(%{user_id: id}, scope)

        socket
        |> assign(:employee, employee)
        |> assign(:active_months, active_months)
        |> assign(:projects_filter_date, selected_date)
        |> assign(:page_title, get_employee_display_name(employee))
      end

    {:noreply, socket}
  end

  defp build_employee(user, user_id, date, scope) do
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
    salaries = AshUserSalary.as_of!(date, scope: scope)

    hourly_rate =
      salaries
      |> Enum.find(&(&1.user_id == user_id))
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

    user
    |> Map.put(:projects, projects)
    |> Map.put(:hourly_rate, hourly_rate)
    |> Map.put(:hours_record, hours_record)
    |> Map.put(:time_worked, total_time)
  end

  defp get_employee_display_name(employee), do: employee.name || employee.email

  defp get_employee_slack_url(employee) do
    employee.slack_url || "https://alergeekventures.slack.com"
  end

  @impl true
  def handle_event("change-month", %{"month" => month}, socket) do
    employee = socket.assigns.employee

    {:noreply, push_patch(socket, to: ~p"/zarzadzanie/pracownicy/#{employee.id}?month=#{month}")}
  end

  attr :label, :string, required: true
  attr :class, :any, default: ""
  slot :inner_block

  defp user_card_info(assigns) do
    ~H"""
    <div class={["space-y-1", @class]}>
      <div class="text-grey-700 text-sm/snug">{@label}</div>
      <div class="flex items-center gap-2 text-base/snug">{render_slot(@inner_block)}</div>
    </div>
    """
  end

  attr :class, :any, default: ""
  attr :gap_size, :string, default: "6"
  slot :inner_block, required: true

  defp card(assigns) do
    ~H"""
    <section class={[
      "flex flex-col rounded-md bg-white p-6 text-black shadow",
      @gap_size && "gap-y-#{@gap_size}",
      @class
    ]}>
      {render_slot(@inner_block)}
    </section>
    """
  end

  slot :inner_block

  defp card_header(assigns) do
    ~H"""
    <h3 class="text-grey-900 text-base/tight font-medium">{render_slot(@inner_block)}</h3>
    """
  end

  attr :project, :map, required: true

  defp project_accordion(assigns) do
    ~H"""
    <div
      id={"project-accordion-#{@project.id}"}
      class="group grid grid-cols-[1fr_min-content_min-content] gap-x-6 overflow-hidden"
    >
      <button
        type="button"
        phx-click={toggle_project_accordion(@project.id)}
        class="group col-span-full grid grid-cols-subgrid items-center py-4"
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
      </button>
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

  attr :employee, :map, required: true
  attr :projects_filter_date, :any, required: true
  attr :active_months, :list, required: true

  defp employee_projects_tab(assigns) do
    ~H"""
    <.card>
      <%!-- TODO: allow editing the user wage --%>
      <.card_header>
        Dane do przelewu
      </.card_header>
      <div class="grid grid-cols-[minmax(min-content,1fr)_minmax(min-content,2fr)] gap-4">
        <.user_card_info label="Stawka">
          {:PLN
          |> Money.new(@employee.hourly_rate)
          |> Money.to_string!(no_fraction_if_integer: true)}/godz.
        </.user_card_info>
        <.user_card_info label="Numer konta bankowego">
          {@employee.bank_account_number || "Brak danych"}
        </.user_card_info>
      </div>
    </.card>

    <div class="flex items-start gap-6">
      <.card class="grow">
        <div class="flex items-center justify-between">
          <.card_header>
            Projekty pracownika
          </.card_header>
          <.date_picker
            id="projects_filter_month"
            selected_date={@projects_filter_date}
            active_months={@active_months}
          />
        </div>
        <div class="divide-lightGreyBg divide-y">
          <%= if Enum.empty?(@employee.projects) do %>
            <div class="text-darkGrey mt-4 text-sm">Brak projektów</div>
          <% else %>
            <.project_accordion :for={project <- @employee.projects} project={project} />
          <% end %>
        </div>
      </.card>
      <div class="flex flex-col gap-4">
        <.card>
          <.card_header>
            Podsumowanie miesiąca
          </.card_header>
          <div class="flex flex-col gap-4">
            <.user_card_info label="Przepracowano">
              <span class="text-turquoise-700 font-medium">
                {Timetracker.seconds_to_hours(@employee.time_worked)} godz.
              </span>
            </.user_card_info>
            <.user_card_info label="Wynagrodzenie">
              <span class="text-turquoise-700 font-medium">
                {:PLN
                |> Money.new(
                  Decimal.mult(
                    @employee.hourly_rate,
                    Decimal.new(Timetracker.seconds_to_hours(@employee.time_worked))
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
            <.hours_record_status hours_record={@employee.hours_record} user={@employee} />
          </div>
        </.card>
      </div>
    </div>
    """
  end

  # Distinct months (as naive_datetime) that have sessions, newest first.
  defp months_with_sessions(filters, scope) do
    Session
    |> Ash.Query.for_read(:list, filters, scope: scope)
    |> Ash.Query.distinct(:month_start)
    |> Ash.Query.distinct_sort(month_start: :desc)
    |> Ash.Query.sort(month_start: :desc)
    |> Ash.Query.load(:month_start)
    |> Ash.read!(scope: scope)
    |> Enum.map(& &1.month_start)
  end
end
