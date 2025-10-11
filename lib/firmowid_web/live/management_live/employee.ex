defmodule FirmowidWeb.ManagementLive.Employee do
  @moduledoc false
  use FirmowidWeb, :live_view

  alias Firmowid.Employee
  alias Firmowid.Helpers.TimeConverter
  alias Firmowid.Timetracker
  alias FirmowidWeb.Helpers.TimeFormatter

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    Bodyguard.permit!(Employee, :read_employee, socket.assigns.current_user)

    active_months = Timetracker.get_months_with_sessions(id)

    socket =
      socket
      |> assign(:employee_id, id)
      |> assign(:projects_filter_date, Date.utc_today())
      |> assign(:leaves_filter_year, Date.utc_today())
      |> assign_employee()
      |> assign(:active_months, active_months)
      |> assign(:tab, "projekty")
      |> assign_title()
      # TODO: obtain these from the database
      |> assign(:phone, "+48 123 456 789")
      |> assign(:slack_url, "https://alergeekventures.slack.com/")
      |> assign(:slack_username, "JanBeznazwiskowy")
      |> assign(:bank_account_number, "1234 5678 9012 3456 7890 1234")
      |> assign(:birthday, ~D[2000-07-21])
      |> assign(:employment_details, %{
        employment_type: "Umowa zlecenie",
        position: "Software Developer",
        student_status_until: ~D[2026-06-30],
        contract_signed_on: ~D[2022-01-15]
      })

    {:ok, socket}
  end

  defp get_employee_display_name(employee) do
    employee.name || employee.email
  end

  defp assign_employee(socket) do
    employee = Employee.list_employee_details(socket.assigns.employee_id, socket.assigns.projects_filter_date)
    assign(socket, :employee, employee)
  end

  defp assign_title(socket) do
    assign(socket, :page_title, get_employee_display_name(socket.assigns.employee))
  end

  @impl true
  def handle_params(%{"tab" => tab}, _uri, socket) do
    {:noreply, assign(socket, tab: tab)}
  end

  def handle_params(_unsigned_params, _uri, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("change-month", %{"month" => month}, socket) do
    {:noreply,
     socket
     |> assign(:projects_filter_date, Date.from_iso8601!(month))
     |> assign_employee()}
  end

  def return_to_employees_list(assigns) do
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
    <div class={[@class, "text-black bg-white p-6 rounded-md shadow flex flex-col gap-y-[22px]"]}>
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :title, :string, required: true

  defp editable_header(assigns) do
    # TODO: allow editing the content
    ~H"""
    <div class="flex gap-3">
      <span>{@title}</span>
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

  defp project_accordion(assigns) do
    ~H"""
    <div id={"project-accordion-#{@project.id}"} phx-hook="Accordion">
      <div data-accordion-item class="group overflow-hidden grid grid-cols-[1fr_auto_40px]">
        <button
          data-accordion-trigger
          type="button"
          class="grid grid-cols-subgrid col-span-3 pt-4"
        >
          <span class="text-start">{@project.name}</span>
          <span>
            {@project.sessions
            |> Enum.map(& &1.time_worked)
            |> Enum.sum()
            |> TimeConverter.time_worked_in_seconds_to_hours()} h
          </span>
          <svg
            width="16"
            height="15"
            viewBox="0 0 16 15"
            fill="none"
            xmlns="http://www.w3.org/2000/svg"
            class={[
              "ml-auto text-darkGrey my-auto transition-transform",
              "group-[.open]:rotate-180"
            ]}
          >
            <g clip-path="url(#clip0_4698_33604)">
              <path
                d="M4.05957 4.81152L7.99904 10.2451L9.96857 7.52847L11.9381 4.81181"
                stroke="#4E4E4E"
                stroke-width="1.65682"
                stroke-linecap="round"
                stroke-linejoin="round"
              />
            </g>
            <defs>
              <clipPath id="clip0_4698_33604">
                <rect width="16" height="13.2545" fill="white" transform="translate(0 0.873047)" />
              </clipPath>
            </defs>
          </svg>
        </button>
        <div
          data-accordion-content
          class={[
            "grid grid-cols-subgrid col-span-2 mt-1.5 mb-2.5 space-y-3 items-end",
            "text-darkGrey"
          ]}
        >
          <%= if length(@project.sessions) == 0 do %>
            <div class="text-sm text-darkGrey">
              Brak sesji w tym miesiącu
            </div>
          <% else %>
            <%= for session <- @project.sessions do %>
              <div>{session.title}</div>
              <div>
                {TimeConverter.time_worked_in_seconds_to_hours(session.time_worked)} h
              </div>
            <% end %>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  def employee_projects_tab(assigns) do
    ~H"""
    <.card>
      <.editable_header title="Dane do przelewu" />
      <div class="flex justify-between">
        <.user_card_info label="Stawka">
          {:PLN
          |> Money.new(@employee.hourly_rate)
          |> Money.to_string!(fractional_digits: 0)}/godz.
        </.user_card_info>
        <.user_card_info label="Numer konta bankowego" class="mr-32">
          {@bank_account_number}
        </.user_card_info>
      </div>
    </.card>
    <div class="flex gap-4 items-start">
      <.card class="grow min-h-[12.5rem]">
        <div class="flex justify-between items-center">
          <.editable_header title="Projekty pracownika" />
          <.date_picker
            id="projects_filter_month"
            selected_date={@projects_filter_date}
            active_months={@active_months}
            class="rounded-[5px] w-fit text-darkGrey py-1"
          />
        </div>
        <div class="mt-1 divide-y divide-lightGreyBg">
          <%= if length(@employee.projects) == 0 do %>
            <div class="text-sm text-darkGrey mt-4">Brak projektów</div>
          <% else %>
            <%= for project <- @employee.projects do %>
              <.project_accordion project={project} />
            <% end %>
          <% end %>
        </div>
      </.card>
      <div class="min-w-[251px] space-y-4">
        <.card class="!gap-y-[18px] h-[12.5rem]">
          <div>Podsumowanie miesiąca</div>
          <div class="space-y-3">
            <.user_card_info label="Przepracowano">
              <span class="text-greenText">
                {TimeConverter.time_worked_in_seconds_to_hours(@employee.time_worked)} godz.
              </span>
            </.user_card_info>
            <.user_card_info label="Wynagrodzenie">
              <span class="text-greenText">
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
          </div>
        </.card>
        <.card>
          <div>Ewidencja</div>
          <%!-- TODO: ewidencja --%>
          <div class="flex items-center gap-4 bg-white rounded-[5px]">
            <span class="text-[11px] font-semibold text-darkGrey bg-greyButtonBg pl-2 pr-1 py-[4px] uppercase rounded-[5px] flex items-center justify-between flex-1 gap-1">
              Brak <.icon name="hero-x-mark-micro" />
            </span>
            <svg
              xmlns="http://www.w3.org/2000/svg"
              width="24"
              height="24"
              viewBox="0 0 24 24"
              fill="none"
              stroke-width="1.5"
              stroke-linecap="round"
              stroke-linejoin="round"
              class="stroke-greyButtonBg shrink-0 mr-[5px] mb-[1px]"
            >
              <path d="M15 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7Z" /><path d="m14.5 12.5-5 5" /><path d="m9.5 12.5 5 5" />
            </svg>
          </div>
        </.card>
      </div>
    </div>
    """
  end

  def employee_profile_tab(assigns) do
    ~H"""
    <div class="grid grid-cols-2 gap-10">
      <.card class="col-span-2">
        <.editable_header title="Dane korespondencyjne" />
        <div class="grid grid-cols-2">
          <div class="space-y-4">
            <.user_card_info label="Numer telefonu">
              <.link href={"tel:#{@phone}"} class="hover:underline">
                {@phone}
              </.link>
            </.user_card_info>
            <.user_card_info label="Adres e-mail">
              <.link href={"mailto:#{@employee.email}"} class="hover:underline">
                {@employee.email}
              </.link>
            </.user_card_info>
            <.user_card_info label="Slack">
              <.link href={"#{@slack_url}/team/#{@slack_username}"} class="hover:underline">
                @{@slack_username}
              </.link>
            </.user_card_info>
          </div>
          <div class="space-y-4">
            <.user_card_info label="Adres korespondencyjny">
              <%!-- TODO: real addresses --%>
              <address class="not-italic">
                <div>ul. Przykładowa 1/2</div>
                <div>00-001 Warszawa</div>
              </address>
            </.user_card_info>
            <.user_card_info label="Adres zamieszkania">
              <address class="not-italic">
                <div>ul. Przemysłowa 3/4</div>
                <div>00-001 Warszawa</div>
              </address>
            </.user_card_info>
          </div>
        </div>
      </.card>
      <.card>
        <.editable_header title="Informacje o zatrudnieniu" />
        <.user_card_info label="Rodzaj umowy">
          {@employment_details.employment_type}
        </.user_card_info>
        <.user_card_info label="Stanowisko">
          {@employment_details.position}
        </.user_card_info>
        <.user_card_info label="Status studenta">
          <%= if is_nil(is_nil(@employment_details.student_status_until)) do %>
            brak
          <% else %>
            <span class="text-greenText font-bold mr-1">aktywny</span>
            <span class="text-grey-500 text-sm">
              (do {TimeFormatter.format_date(@employment_details.student_status_until)})
            </span>
          <% end %>
        </.user_card_info>
        <.user_card_info label="Data podpisania umowy">
          <div class="w-full flex justify-between items-center">
            <div>{TimeFormatter.format_date(@employment_details.contract_signed_on)} r.</div>
            <%!-- TODO: download employee contract --%>
            <.button
              color="light_grey"
              class="uppercase text-xs font-semibold py-0 px-2 rounded-[3px]"
            >
              Umowa <.icon name="hero-document" class="size-5 ml-1" />
            </.button>
          </div>
        </.user_card_info>
      </.card>
      <%!-- TODO: calendar --%>
      <.card>(kalendarz pracy)</.card>
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

  def employee_documents_tab(assigns) do
    ~H"""
    <.card class="grid grid-cols-[1fr_auto]">
      <div>Przesłane dokumenty</div>
      <%!-- TODO: add functionality --%>
      <.button
        class="ml-2 text-black/80 flex items-center py-[6px] pr-4 pl-2.5 font-medium rounded-[5px]"
        color="light_grey"
      >
        <.icon name="hero-plus-mini" class="size-6 mr-1" /> Dodaj dokument
      </.button>
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
      <.document_filter_option
        label="Sortuj"
        icon="hero-funnel"
        class="bg-transparent p-0 ml-auto"
      />
    </.card>
    """
  end

  def employee_leaves_tab(assigns) do
    ~H"""
    <div class="space-y-10">
      <.card>
        <div>Wnioski do zatwierdzenia</div>
      </.card>
      <.card>
        <div class="flex justify-between">
          <div>Pozostałe wnioski</div>
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
