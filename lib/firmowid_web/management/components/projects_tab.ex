defmodule FirmowidWeb.Management.Components.ProjectsTab do
  @moduledoc "LiveComponent for displaying employee projects, sessions, and salary summary."
  use FirmowidWeb, :live_component

  import FirmowidUI.Components.Button
  import FirmowidWeb.DesignSystem.Components.CoreComponents, except: [button: 1]
  import FirmowidWeb.DesignSystem.Components.MonthPicker
  import FirmowidWeb.HoursRecord.Components.ChangeRequest
  import FirmowidWeb.Management.Components.Card
  import FirmowidWeb.Management.Components.HoursRecordStatus, only: [hours_record_status: 1]

  alias Firmowid.Ash.Core
  alias Firmowid.Ash.Payroll
  alias Firmowid.Ash.Timetracker
  alias Firmowid.Ash.Timetracker.HoursRecord
  alias FirmowidWeb.Infrastructure.Utilities.TimeFormatter
  alias FirmowidWeb.Payroll.Components.PayoutEstimates

  @impl true
  def mount(socket) do
    {:ok, socket}
  end

  @impl true
  def update(assigns, socket) do
    user = assigns.user
    member_id = user.member.id
    date = assigns.date
    scope = assigns.scope

    # 1. Sessions for this user+month, grouped by project+title
    sessions =
      %{member_id: member_id, month: date.month, year: date.year}
      |> Timetracker.query_to_list_sessions(scope: scope)
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

    # 3. Projects this user belongs to, sorted by duration, with grouped sessions attached
    projects =
      %{
        member_id: member_id,
        active_from: Date.beginning_of_month(date),
        active_to: Date.end_of_month(date)
      }
      |> Timetracker.list_projects!(scope: scope)
      |> Enum.map(fn project ->
        Map.put(project, :sessions, Map.get(sessions_by_project, project.id, []))
      end)
      |> Enum.sort_by(
        fn project ->
          project.sessions |> Enum.map(& &1.duration) |> Enum.sum()
        end,
        :desc
      )

    # 4. Salary as of this month
    before_date = Date.end_of_month(date)

    salaries =
      Payroll.list_salaries!(%{user_id: user.id, active_at: before_date},
        load: [monthly_amount: [month: date], payout_estimates: [month: date]],
        scope: scope
      )

    salary = List.first(salaries)

    salary_history = Payroll.list_salaries!(%{user_id: user.id}, scope: scope, load: [:ends_at])

    hourly_rate =
      salaries
      |> List.first()
      |> case do
        nil -> Decimal.new(0)
        salary -> salary.hourly_rate
      end

    socket =
      socket
      |> assign(assigns)
      |> assign(:projects, projects)
      |> assign(:hourly_rate, hourly_rate)
      |> assign(:monthly_gross, if(salary, do: salary.monthly_amount, else: Money.new!(:PLN, 0)))
      |> assign(:payout_estimates, if(salary, do: salary.payout_estimates, else: []))
      |> assign_hours_records()
      |> assign(:salary_history, salary_history)
      |> assign(:editing_payout, false)
      |> assign(:payout_form, payout_form(hourly_rate, user.member.bank_account_number))

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex h-full min-h-0 flex-col gap-6">
      <.card class="relative z-10" dimmed={@user.member.archived_at}>
        <.card_header>
          Dane do przelewu
          <:actions>
            <.card_edit_actions
              editing={@editing_payout}
              form="payout-form"
              toggle_event="toggle_payout_editor"
              target={@myself}
            />
          </:actions>
        </.card_header>

        <.form
          id="payout-form"
          for={@payout_form}
          phx-target={@myself}
          phx-submit="save_payout"
        >
          <div class="grid grid-cols-[minmax(min-content,2fr)_minmax(min-content,1fr)] gap-4">
            <.field_row label="Numer konta bankowego" for={@payout_form[:bank_account_number].id}>
              <%= if @editing_payout do %>
                <.input
                  field={@payout_form[:bank_account_number]}
                  type="text"
                  new={true}
                  class="w-full"
                />
              <% else %>
                {@user.member.bank_account_number || "Brak danych"}
              <% end %>
            </.field_row>
            <div class="flex items-end justify-between gap-4">
              <%= if @editing_payout do %>
                <.field_row
                  label="Nowa stawka"
                  for={@payout_form[:hourly_rate].id}
                  class="text-nowrap"
                >
                  <div class="flex items-center gap-2">
                    <.input
                      field={@payout_form[:hourly_rate]}
                      type="number"
                      step="0.01"
                      min="0"
                      new={true}
                      input_class="max-w-20 text-right"
                    />
                    <p>zł/godz.</p>
                  </div>
                </.field_row>
              <% else %>
                <.field_row label="Stawka" class="text-nowrap">
                  <div class="min-h-8.5">
                    {Money.new(:PLN, @hourly_rate) |> Money.to_string!(no_fraction_if_integer: true)}/godz.
                  </div>
                </.field_row>
                <.button
                  type="button"
                  variant="outline"
                  size="small"
                  phx-click={show_modal("salary-history-modal")}
                  disabled={Enum.empty?(@salary_history)}
                  class="self-center"
                >
                  Historia stawek
                </.button>
              <% end %>
            </div>
          </div>
        </.form>
      </.card>

      <div class="flex min-h-0 flex-1 gap-6">
        <.card class="flex min-h-0 grow flex-col">
          <div class="flex shrink-0 items-center justify-between">
            <.card_header>
              Projekty pracownika
            </.card_header>
            <.month_picker
              id="projects_filter_month"
              selected_date={@date}
              active_months={@active_months}
              size="small"
              variant="outline"
            />
          </div>

          <div class="relative w-full flex-1">
            <div class="absolute inset-0 scrollbar-card divide-y divide-grey-100 overflow-y-auto pr-4">
              <%= if Enum.empty?(@projects) do %>
                <div class="mt-4 text-sm text-grey-700">Brak projektów</div>
              <% else %>
                <.project_accordion :for={project <- @projects} project={project} />
              <% end %>
            </div>
          </div>
        </.card>

        <div class="flex min-h-0 shrink-0 flex-col gap-4 overflow-y-auto">
          <.card :if={@hours_record} gap_size="4" class="shrink-0">
            <.card_header>
              Ewidencja
            </.card_header>
            <div class="flex gap-3">
              <.hours_record_status
                hours_record={@hours_record}
                user={@user}
                show_change_request={false}
              />
            </div>
          </.card>
          <.card
            :for={record <- @hours_record_requests}
            gap_size="4"
            class="shrink-0 border border-rust-700 contain-[inline-size]"
          >
            <.change_request
              record={record}
              reviewable={@scope.actor.member.role == :admin}
              target={@myself}
            />
          </.card>
          <.card class="shrink-0">
            <PayoutEstimates.summary
              estimates={@payout_estimates}
              gross_amount={@monthly_gross}
              subtitle={TimeFormatter.format_date(@date, "LLLL yyyy")}
            />
          </.card>
          <.card :if={@previous_hours_records != []} gap_size="4" class="shrink-0">
            <.submission_history records={@previous_hours_records} user={@user} />
          </.card>
        </div>
      </div>

      <.modal id="salary-history-modal">
        <h2 class="mb-4 text-xl font-medium">Historia stawek</h2>
        <div class="flex scrollbar-card max-h-[400px] flex-col gap-2 divide-grey-100 overflow-y-auto">
          <%= if Enum.empty?(@salary_history) do %>
            <p class="text-grey-700">Brak danych</p>
          <% else %>
            <div :for={salary <- @salary_history} class="flex items-end gap-2">
              <span>
                {:PLN
                |> Money.new(salary.hourly_rate)
                |> Money.to_string!(no_fraction_if_integer: true)}/godz.
              </span>
              <span class="text-sm text-grey-500">
                ({TimeFormatter.format_date(salary.starts_at)} - {if salary.ends_at,
                  do: TimeFormatter.format_date(salary.ends_at),
                  else: "obecnie"})
              </span>
            </div>
          <% end %>
        </div>
      </.modal>
    </div>
    """
  end

  @impl true
  def handle_event("review-hours-record-change", %{"id" => id, "decision" => decision}, socket)
      when decision in ["accepted", "rejected"] do
    scope = socket.assigns.scope

    with {:ok, record} <- HoursRecord.get(id, scope: scope),
         true <- record.member_id == socket.assigns.user.member.id,
         {:ok, _record} <- review_request(record, decision, scope) do
      {:noreply,
       socket
       |> assign_hours_records()
       |> put_flash(:info, gettext("The request decision has been saved."))}
    else
      _error ->
        {:noreply,
         socket
         |> assign_hours_records()
         |> put_flash(
           :error,
           gettext("Could not save the decision. The request may already have been reviewed.")
         )}
    end
  end

  def handle_event("toggle_payout_editor", _params, socket) do
    {:noreply,
     socket
     |> assign(:editing_payout, not socket.assigns.editing_payout)
     |> then(&assign(&1, :payout_form, payout_form(&1)))}
  end

  def handle_event("save_payout", %{"hourly_rate" => hourly_rate, "bank_account_number" => bank_account_number}, socket) do
    scope = socket.assigns.scope
    user = socket.assigns.user

    {:noreply,
     socket
     |> save_wage(%{hourly_rate: hourly_rate, user: user}, scope)
     |> save_bank_account(%{bank_account_number: bank_account_number, user: user}, scope)
     |> assign(:editing_payout, false)
     |> then(&assign(&1, :payout_form, payout_form(&1)))}
  end

  defp review_request(record, "accepted", scope), do: HoursRecord.accept_change_request(record, scope: scope)

  defp review_request(record, "rejected", scope), do: HoursRecord.reject_change_request(record, scope: scope)

  defp assign_hours_records(socket) do
    date = socket.assigns.date

    records =
      Timetracker.list_hours_records!(
        %{
          member_id: socket.assigns.user.member.id,
          month: date.month,
          year: date.year,
          submission_status: nil
        },
        scope: socket.assigns.scope
      )

    socket
    |> assign(:hours_record, Enum.find(records, &(&1.submission_status == :submitted)))
    |> assign(
      :hours_record_requests,
      Enum.filter(records, &(&1.change_requested_at && &1.submission_status == :submitted))
    )
    |> assign(
      :previous_hours_records,
      Enum.filter(records, &(&1.submission_status == :withdrawn))
    )
  end

  defp save_wage(socket, %{hourly_rate: hourly_rate, user: user}, scope) do
    case Payroll.create_salary(%{hourly_rate: hourly_rate, member_id: user.member.id},
           scope: scope
         ) do
      {:ok, salary} ->
        history = Payroll.list_salaries!(%{user_id: user.id}, scope: scope, load: [:ends_at])

        active =
          %{user_id: user.id, active_at: Date.end_of_month(socket.assigns.date)}
          |> Payroll.list_salaries!(
            load: [
              monthly_amount: [month: socket.assigns.date],
              payout_estimates: [month: socket.assigns.date]
            ],
            scope: scope
          )
          |> List.first()

        socket
        |> assign(:hourly_rate, salary.hourly_rate)
        |> assign(:salary_history, history)
        |> assign(
          :monthly_gross,
          if(active, do: active.monthly_amount, else: Money.new!(:PLN, 0))
        )
        |> assign(:payout_estimates, if(active, do: active.payout_estimates, else: []))

      {:error, _} ->
        put_flash(socket, :error, "Nie udało się zapisać stawki. Spróbuj ponownie.")
    end
  end

  defp save_bank_account(socket, %{bank_account_number: bank_account_number, user: user}, scope) do
    case Core.update_member_profile(user.member, %{bank_account_number: bank_account_number}, scope: scope) do
      {:ok, member} ->
        updated_user = %{user | member: member}
        send(self(), {:employee_updated, updated_user})
        assign(socket, :user, updated_user)

      {:error, _} ->
        put_flash(socket, :error, "Nie udało się zapisać numeru konta. Spróbuj ponownie.")
    end
  end

  defp payout_form(socket) do
    payout_form(socket.assigns.hourly_rate, socket.assigns.user.member.bank_account_number)
  end

  defp payout_form(hourly_rate, bank_account_number) do
    to_form(%{
      "hourly_rate" => hourly_rate,
      "bank_account_number" => bank_account_number
    })
  end

  attr :project, :map, required: true

  defp project_accordion(assigns) do
    ~H"""
    <div
      id={"project-accordion-#{@project.id}"}
      class="group grid grid-cols-[1fr_min-content_min-content] gap-x-6 overflow-hidden"
    >
      <.button
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
      </.button>
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
              class="flex justify-between text-base/snug text-grey-700"
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
