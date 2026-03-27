defmodule FirmowidWeb.ManagementLive.Employee do
  @moduledoc false
  use FirmowidWeb, :live_view

  import FirmowidWeb.ManagementLive.Employees, only: [hours_record_status: 1]

  alias Firmowid.Ash.Timetracker.Session, as: AshSession
  alias Firmowid.Helpers.TimeConverter
  alias Firmowid.Management
  alias FirmowidWeb.Helpers.TimeFormatter

  @impl true
  def mount(_params, _session, socket) do
    Bodyguard.permit!(Management, :read_employee, socket.assigns.current_user)
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

    socket =
      case Management.list_employee_details(id, selected_date) do
        nil ->
          push_navigate(socket, to: ~p"/zarzadzanie/pracownicy")

        employee ->
          {:ok, active_months} =
            AshSession.months_with_sessions(%{user_id: id}, scope: scope)

          socket
          |> assign(:employee, employee)
          |> assign(:active_months, active_months)
          |> assign(:projects_filter_date, selected_date)
          |> assign(:page_title, get_employee_display_name(employee))
      end

    {:noreply, socket}
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
  attr :class, :string, default: ""
  slot :inner_block

  defp user_card_info(assigns) do
    ~H"""
    <div class={classes(["space-y-1", @class])}>
      <div class="text-grey-700 text-sm/snug">{@label}</div>
      <div class="flex gap-2 items-center text-base/snug">{render_slot(@inner_block)}</div>
    </div>
    """
  end

  attr :class, :string, default: ""
  slot :inner_block, required: true

  defp card(assigns) do
    ~H"""
    <section class={
      classes([
        "bg-white text-black p-6 rounded-md shadow flex flex-col gap-y-6",
        @class
      ])
    }>
      {render_slot(@inner_block)}
    </section>
    """
  end

  slot :inner_block

  defp card_header(assigns) do
    ~H"""
    <h3 class="text-base/tight font-medium text-grey-900">{render_slot(@inner_block)}</h3>
    """
  end

  attr :project, :map, required: true

  defp project_accordion(assigns) do
    ~H"""
    <div
      id={"project-accordion-#{@project.id}"}
      class="overflow-hidden grid grid-cols-[1fr_min-content_min-content] gap-x-6 group"
    >
      <button
        type="button"
        phx-click={toggle_project_accordion(@project.id)}
        class="grid grid-cols-subgrid col-span-full items-center py-4 group"
      >
        <span class="text-start text-nowrap">{@project.name}</span>
        <span class="text-nowrap">
          {@project.sessions
          |> Enum.map(& &1.duration)
          |> Enum.sum()
          |> TimeConverter.time_worked_in_seconds_to_hours()} h
        </span>
        <.icon
          name="hero-chevron-down"
          class="group-data-expanded:rotate-180 size-4 transition-transform duration-200 ease-in-out"
        />
      </button>
      <div
        class="grid grid-rows-[0fr] group-data-expanded:grid-rows-[1fr] transition-[grid-template-rows] duration-300 ease-in-out col-span-2 overflow-hidden"
        role="region"
      >
        <div class="flex flex-col gap-y-2 ml-4 *:last:mb-4 overflow-hidden">
          <%= if Enum.empty?(@project.sessions) do %>
            <p class="text-grey-700">
              Brak sesji w tym miesiącu
            </p>
          <% else %>
            <div
              :for={session <- @project.sessions}
              class="flex justify-between text-base/snug text-grey-700"
            >
              <p class="text-nowrap truncate">{session.title}</p>
              <p>
                {TimeConverter.time_worked_in_seconds_to_hours(session.duration)} h
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

    <div class="flex gap-6 items-start">
      <.card class="grow">
        <div class="flex justify-between items-center">
          <.card_header>
            Projekty pracownika
          </.card_header>
          <.date_picker
            id="projects_filter_month"
            selected_date={@projects_filter_date}
            active_months={@active_months}
          />
        </div>
        <div class="divide-y divide-lightGreyBg">
          <%= if Enum.empty?(@employee.projects) do %>
            <div class="text-sm text-darkGrey mt-4">Brak projektów</div>
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
                {TimeConverter.time_worked_in_seconds_to_hours(@employee.time_worked)} godz.
              </span>
            </.user_card_info>
            <.user_card_info label="Wynagrodzenie">
              <span class="text-turquoise-700 font-medium">
                {:PLN
                |> Money.new(
                  Decimal.mult(
                    @employee.hourly_rate,
                    Decimal.new(TimeConverter.time_worked_in_seconds_to_hours(@employee.time_worked))
                  )
                )
                |> Money.to_string!(no_fraction_if_integer: true, currency_symbol: "PLN")}
              </span>
            </.user_card_info>
          </div>
        </.card>
        <.card class="gap-y-4">
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
end
