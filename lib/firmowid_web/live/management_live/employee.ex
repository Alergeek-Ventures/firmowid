defmodule FirmowidWeb.ManagementLive.Employee do
  @moduledoc false
  use FirmowidWeb, :live_view

  alias Firmowid.Accounts.ContractType
  alias Firmowid.Helpers.TimeConverter
  alias Firmowid.Management
  alias Firmowid.Timetracker
  alias FirmowidWeb.Helpers.TimeFormatter

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    Bodyguard.permit!(Management, :read_employee, socket.assigns.current_user)

    active_months = Timetracker.get_months_with_sessions(id)

    socket =
      socket
      |> assign(:employee_id, id)
      |> assign(:projects_filter_date, Date.utc_today())
      |> assign(:leaves_filter_year, Date.utc_today())
      |> assign_employee()
      |> assign(:active_months, active_months)
      |> assign_title()

    {:ok, socket}
  end

  defp get_employee_display_name(employee) do
    employee.name || employee.email
  end

  defp get_employee_slack_url(employee) do
    employee.slack_url || "https://alergeekventures.slack.com"
  end

  defp assign_employee(socket) do
    employee = Management.list_employee_details(socket.assigns.employee_id, socket.assigns.projects_filter_date)
    assign(socket, :employee, employee)
  end

  defp assign_title(socket) do
    assign(socket, :page_title, get_employee_display_name(socket.assigns.employee))
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("change-month", %{"month" => month}, socket) do
    {:noreply,
     socket
     |> assign(:projects_filter_date, Date.from_iso8601!(month))
     |> assign_employee()}
  end

  defp return_to_employees_list(assigns) do
    ~H"""
    <.link
      navigate={~p"/zarzadzanie/pracownicy"}
      class="inline-block group"
    >
      <.icon name="hero-arrow-long-left" />
      <span class="group-hover:border-black border-b-2 border-transparent transition-colors">
        Powrót do listy pracowników
      </span>
    </.link>
    """
  end

  attr :label, :string, required: true
  attr :class, :string, default: ""
  slot :inner_block

  defp user_card_info(assigns) do
    ~H"""
    <div class={[@class, "space-y-1"]}>
      <div class="text-darkGrey text-sm">{@label}</div>
      <div class="flex gap-2 items-center">{render_slot(@inner_block)}</div>
    </div>
    """
  end

  attr :class, :string, default: ""
  slot :inner_block, required: true

  defp card(assigns) do
    ~H"""
    <section class={[
      @class,
      "bg-white text-black p-6 rounded-md shadow flex flex-col gap-y-[22px]"
    ]}>
      {render_slot(@inner_block)}
    </section>
    """
  end

  attr :title, :string, required: true

  defp editable_header(assigns) do
    # TODO: make the edit button functional
    ~H"""
    <div class="flex gap-3">
      <h3 class="font-medium">{@title}</h3>
      <button
        type="button"
        class="focus:outline-none"
      >
        <.icon
          name="hero-pencil-solid"
          class="size-4 text-grey-700 mb-1"
        />
      </button>
    </div>
    """
  end

  attr :project, :map, required: true

  defp project_accordion(assigns) do
    ~H"""
    <div class="overflow-hidden">
      <div class="grid grid-cols-[1fr_auto_40px]">
        <button
          phx-click={handle_toggle_accordion(@project.id)}
          type="button"
          class="accordion-trigger grid grid-cols-subgrid col-span-3 pt-4 [&_.accordion-trigger-icon]:aria-expanded:rotate-180"
          id={"project-accordion-trigger-#{@project.id}"}
          aria-controls={"project-accordion-panel-#{@project.id}"}
        >
          <span class="text-start">{@project.name}</span>
          <span>
            {@project.sessions
            |> Enum.map(& &1.duration)
            |> Enum.sum()
            |> TimeConverter.time_worked_in_seconds_to_hours()} h
          </span>
          <.icon
            name="hero-chevron-down"
            class="accordion-trigger-icon size-4 ml-auto my-auto transition-transform duration-300 ease-in-out"
          />
        </button>
        <div
          class="accordion-panel grid grid-rows-[0fr] data-[expanded]:grid-rows-[1fr] transition-all duration-300 ease-in-out col-span-2 mt-1.5 mb-2.5"
          id={"project-accordion-panel-#{@project.id}"}
          role="region"
        >
          <div class="grid grid-cols-subgrid col-span-2 space-y-3 items-end text-darkGrey overflow-hidden">
            <%= if Enum.empty?(@project.sessions) do %>
              <div class="text-sm text-darkGrey">
                Brak sesji w tym miesiącu
              </div>
            <% else %>
              <%= for session <- @project.sessions do %>
                <div>{session.title}</div>
                <div>
                  {TimeConverter.time_worked_in_seconds_to_hours(session.duration)} h
                </div>
              <% end %>
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp handle_toggle_accordion(project_id) do
    {"aria-expanded", "true", "false"}
    |> JS.toggle_attribute(to: "#project-accordion-trigger-#{project_id}")
    |> JS.toggle_attribute({"data-expanded", ""}, to: "#project-accordion-panel-#{project_id}")
  end

  attr :street, :string, required: true
  attr :city, :string, required: true
  attr :code, :string, required: true

  defp employee_address(assigns) do
    ~H"""
    <address class="not-italic">
      <div>{@street}</div>
      <div>{@code} {@city}</div>
    </address>
    """
  end

  attr :employee, :map, required: true
  attr :projects_filter_date, :any, required: true
  attr :active_months, :list, required: true

  defp employee_projects_tab(assigns) do
    ~H"""
    <.card>
      <%!-- TODO: allow editing the user wage --%>
      <.editable_header title="Dane do przelewu" />
      <div class="flex justify-between">
        <.user_card_info label="Stawka">
          {:PLN
          |> Money.new(@employee.hourly_rate)
          |> Money.to_string!(fractional_digits: 0)}/godz.
        </.user_card_info>
        <.user_card_info label="Numer konta bankowego" class="mr-32">
          {@employee.bank_account_number || "Brak danych"}
        </.user_card_info>
      </div>
    </.card>
    <div class="flex gap-10 items-start">
      <.card class="grow">
        <div class="flex justify-between items-center">
          <%!-- TODO: allow editing the user's projects --%>
          <.editable_header title="Projekty pracownika" />
          <.date_picker
            id="projects_filter_month"
            selected_date={@projects_filter_date}
            active_months={@active_months}
            class="rounded-[5px] w-fit text-darkGrey py-1"
          />
        </div>
        <div class="mt-1 divide-y divide-lightGreyBg">
          <%= if Enum.empty?(@employee.projects) do %>
            <div class="text-sm text-darkGrey mt-4">Brak projektów</div>
          <% else %>
            <%= for project <- @employee.projects do %>
              <.project_accordion project={project} />
            <% end %>
          <% end %>
        </div>
      </.card>
      <.card class="!bg-transparent border border-greyButtonBg shadow-none">
        <h3>Podsumowanie miesiąca</h3>
        <div class="flex flex-col gap-4">
          <.user_card_info label="Przepracowano">
            <span class="text-greenText text-xl font-medium">
              {TimeConverter.time_worked_in_seconds_to_hours(@employee.time_worked)} godz.
            </span>
          </.user_card_info>
          <.user_card_info label="Wynagrodzenie">
            <span class="text-greenText text-md font-medium">
              {:PLN
              |> Money.new(
                Decimal.mult(
                  @employee.hourly_rate,
                  Decimal.new(TimeConverter.time_worked_in_seconds_to_hours(@employee.time_worked))
                )
              )
              |> Money.to_string!(fractional_digits: 0, currency_symbol: "PLN")}
            </span>
          </.user_card_info>
          <.user_card_info label="Ewidencja">
            <%!-- TODO: ewidencja --%>
            <span class="text-[11px] font-semibold text-darkGrey bg-greyButtonBg pl-2 pr-1 py-[4px] uppercase rounded-[5px] flex items-center justify-between flex-1">
              Brak <.icon name="hero-x-mark-micro" />
            </span>
            <svg
              width="24"
              height="24"
              viewBox="0 0 24 24"
              fill="none"
              xmlns="http://www.w3.org/2000/svg"
            >
              <path
                d="M15 2H6C5.46957 2 4.96086 2.21071 4.58579 2.58579C4.21071 2.96086 4 3.46957 4 4V20C4 20.5304 4.21071 21.0391 4.58579 21.4142C4.96086 21.7893 5.46957 22 6 22H18C18.5304 22 19.0391 21.7893 19.4142 21.4142C19.7893 21.0391 20 20.5304 20 20V7L15 2Z"
                stroke="#DDDDDD"
                stroke-width="2"
                stroke-linecap="round"
                stroke-linejoin="round"
              />
              <path
                d="M14 2V6C14 6.53043 14.2107 7.03914 14.5858 7.41421C14.9609 7.78929 15.4696 8 16 8H20"
                stroke="#DDDDDD"
                stroke-width="2"
                stroke-linecap="round"
                stroke-linejoin="round"
              />
              <path
                d="M14.5 12.5L9.5 17.5"
                stroke="#DDDDDD"
                stroke-width="2"
                stroke-linecap="round"
                stroke-linejoin="round"
              />
              <path
                d="M9.5 12.5L14.5 17.5"
                stroke="#DDDDDD"
                stroke-width="2"
                stroke-linecap="round"
                stroke-linejoin="round"
              />
            </svg>
          </.user_card_info>
        </div>
      </.card>
    </div>
    """
  end

  attr :employee, :map, required: true

  defp employee_profile_tab(assigns) do
    ~H"""
    <div class="grid grid-cols-2 gap-10">
      <.card class="col-span-2">
        <.editable_header title="Dane korespondencyjne" />
        <div class="grid grid-cols-2 gap-24">
          <div class="space-y-4">
            <.user_card_info label="Numer telefonu">
              <%= if @employee.phone do %>
                <.link href={"tel:#{@employee.phone}"} class="hover:underline">
                  {@employee.phone}
                </.link>
              <% else %>
                <span class="text-darkGrey">Brak danych</span>
              <% end %>
            </.user_card_info>
            <.user_card_info label="Adres e-mail">
              <.link href={"mailto:#{@employee.email}"} class="hover:underline">
                {@employee.email}
              </.link>
            </.user_card_info>
            <.user_card_info label="Slack">
              <%= if @employee.slack_id do %>
                <.link
                  href={"#{get_employee_slack_url(@employee)}/team/#{@employee.slack_id}"}
                  class="hover:underline"
                >
                  @{@employee.slack_id}
                </.link>
              <% else %>
                <span class="text-darkGrey">Brak danych</span>
              <% end %>
            </.user_card_info>
          </div>
          <div class="space-y-4">
            <.user_card_info label="Adres korespondencyjny">
              <%= if @employee.correspondence_street && @employee.correspondence_city && @employee.correspondence_code do %>
                <.employee_address
                  street={@employee.correspondence_street}
                  city={@employee.correspondence_city}
                  code={@employee.correspondence_code}
                />
              <% else %>
                <span class="text-darkGrey">Brak danych</span>
              <% end %>
            </.user_card_info>
            <.user_card_info label="Adres zamieszkania">
              <%= if @employee.residence_street && @employee.residence_city && @employee.residence_code do %>
                <.employee_address
                  street={@employee.residence_street}
                  city={@employee.residence_city}
                  code={@employee.residence_code}
                />
              <% else %>
                <span class="text-darkGrey">Brak danych</span>
              <% end %>
            </.user_card_info>
          </div>
        </div>
      </.card>
      <.card>
        <.editable_header title="Informacje o zatrudnieniu" />
        <.user_card_info label="Rodzaj umowy">
          {ContractType.title(@employee.employment_contract_type) || "Brak danych"}
        </.user_card_info>
        <.user_card_info label="Stanowisko">
          {@employee.position || "Brak danych"}
        </.user_card_info>
        <.user_card_info label="Status studenta">
          <%= if is_nil(@employee.student_status_until) do %>
            brak
          <% else %>
            <span class="text-greenText font-bold mr-1">aktywny</span>
            <span class="text-grey-500 text-sm">
              (do {TimeFormatter.format_date(@employee.student_status_until)})
            </span>
          <% end %>
        </.user_card_info>
        <.user_card_info label="Data podpisania umowy">
          <%= if @employee.employment_date do %>
            <div class="w-full flex justify-between items-center">
              <div>{TimeFormatter.format_date(@employee.employment_date)} r.</div>
              <%!-- TODO: download employee contract --%>
              <.button
                color="light_grey"
                class="uppercase text-xs font-semibold py-0 px-2 rounded-[3px]"
              >
                Umowa <.icon name="hero-document" class="size-5 ml-1" />
              </.button>
            </div>
          <% else %>
            <span class="text-darkGrey">Brak danych</span>
          <% end %>
        </.user_card_info>
      </.card>
      <%!-- TODO: add calendar --%>
      <.card>Tutaj powstanie kalendarz pracy</.card>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :icon, :string, required: true
  attr :class, :string, default: ""

  defp document_filter_option(assigns) do
    ~H"""
    <button class={classes(["bg-lightGreyBg rounded-full py-0.5 px-4 text-darkGrey", @class])}>
      <span class="text-sm">{@label}</span>
      <.icon name={@icon} class="size-5" />
    </button>
    """
  end

  defp employee_documents_tab(assigns) do
    ~H"""
    <.card class="grid grid-cols-[1fr_auto]">
      <div>Przesłane dokumenty</div>
      <%!-- TODO: allow adding new document --%>
      <.button
        class="ml-2 text-black/80 flex items-center py-[6px] pr-4 pl-2.5 font-medium rounded-[5px]"
        color="light_grey"
      >
        <.icon name="hero-plus-mini" class="size-6 mr-1" /> Dodaj dokument
      </.button>
      <%!-- TODO: allow filtering documents --%>
      <div class="flex gap-2">
        <%= for {label, icon} <- [
          {"ewidencja", "hero-clock"},
          {"umowa", "hero-document"},
          {"zwrot", "hero-banknotes"},
          {"informacje", "hero-information-circle"}
          ] do %>
          <.document_filter_option label={label} icon={icon} />
        <% end %>
      </div>
      <%!-- TODO: allow sorting documents --%>
      <.document_filter_option
        label="Sortuj"
        icon="hero-funnel"
        class="bg-transparent p-0 ml-auto"
      />
    </.card>
    <%!-- TODO: display documents --%>
    """
  end

  defp employee_leaves_tab(assigns) do
    # TODO: add leaves functionality & modal
    ~H"""
    <div class="space-y-10">
      <.card>
        <div>Wnioski do zatwierdzenia</div>
      </.card>
      <.card>
        <div class="flex justify-between">
          <div>Pozostałe wnioski</div>
          <%!-- TODO: filter leaves by year; make the picker only select year instead of month & year --%>
          <.date_picker
            id="leaves_filter_year"
            selected_date={@leaves_filter_year}
            class="rounded-[5px] w-fit text-darkGrey py-1"
          />
        </div>
      </.card>
    </div>
    """
  end
end
