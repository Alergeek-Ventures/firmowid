defmodule FirmowidWeb.Management.Components.ProjectsTab do
  @moduledoc "LiveComponent with an employee's monthly projects or work calendar, hours record and payout summary."
  use FirmowidWeb, :live_component

  import FirmowidUI.Components.Button
  import FirmowidWeb.DesignSystem.Components.MonthPicker
  import FirmowidWeb.HoursRecord.Components.ChangeRequest
  import FirmowidWeb.HoursRecord.Components.Status, only: [hours_record_status: 1]
  import FirmowidWeb.Infrastructure.Flags, only: [flag_enabled?: 2]
  import FirmowidWeb.Infrastructure.Hooks.RequireOrganization, only: [attach_access_hook: 2]

  alias Firmowid.Payroll
  alias Firmowid.Timetracker
  alias Firmowid.Timetracker.HoursRecord
  alias FirmowidWeb.Management.Components.WorkDistribution
  alias FirmowidWeb.Management.Utilities.Navigation
  alias FirmowidWeb.Payroll.Components.MonthlyPayout

  @months_per_page 3

  @impl true
  def mount(socket) do
    {:ok, attach_access_hook(socket, :scope)}
  end

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(Map.delete(assigns, :refetch))
      |> assign_view()
      |> assign_monthly_payout()
      |> assign_hours_records()

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex h-full min-h-0 flex-col gap-6">
      <div class="flex min-h-0 flex-1 gap-6 max-md:flex-col">
        <.card class="flex min-h-0 grow flex-col">
          <div class="flex shrink-0 items-end justify-between gap-4">
            <.tabs label={gettext("Employee projects view")}>
              <:tab
                patch={view_path(@user, @date, :list)}
                active={@view == :list}
              >
                {gettext("Projects")}
              </:tab>
              <:tab
                patch={view_path(@user, Navigation.current_month(), :distribution)}
                active={@view == :distribution}
              >
                {gettext("Work distribution")}
              </:tab>
            </.tabs>
            <.month_picker
              :if={@view == :list}
              id="projects_filter_month"
              selected_date={@date}
              active_months={@active_months}
              size="small"
              variant="outline"
            />
          </div>

          <div class="relative w-full flex-1">
            <div class="absolute inset-0 scrollbar-card divide-y divide-grey-100 overflow-y-auto pr-4 max-md:static max-md:overflow-visible">
              <%= cond do %>
                <% @view == :distribution -> %>
                  <WorkDistribution.work_distribution
                    sessions={@distribution_sessions}
                    months={@distribution_months}
                    more={
                      is_nil(@selected_day) and
                        length(@distribution_months) < length(@all_distribution_months)
                    }
                    selected_day={@selected_day}
                    target={@myself}
                  />
                <% Enum.empty?(@projects) -> %>
                  <div class="mt-4 text-sm text-grey-700">{gettext("No projects")}</div>
                <% true -> %>
                  <.project_accordion :for={project <- @projects} project={project} />
              <% end %>
            </div>
          </div>
        </.card>

        <div class="flex min-h-0 w-80 max-w-full shrink-0 flex-col gap-4 overflow-y-auto max-md:w-full">
          <.card :if={@hours_record} gap_size="4" class="shrink-0">
            <.card_header>
              Ewidencja
            </.card_header>
            <div class="flex gap-3">
              <.hours_record_status
                hours_record={@hours_record}
                user={@user}
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
          <.card :if={flag_enabled?(:accurate_salary_calculation, assigns)} class="shrink-0">
            <MonthlyPayout.summary
              calculation={@monthly_payout}
              month={@date}
            />
          </.card>
          <.card :if={@previous_hours_records != []} gap_size="4" class="shrink-0">
            <.submission_history records={@previous_hours_records} user={@user} />
          </.card>
        </div>
      </div>
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

  def handle_event("select_day", %{"date" => date}, socket) do
    day = Date.from_iso8601!(date)
    month = Date.beginning_of_month(day)

    cond do
      day == socket.assigns.selected_day ->
        {:noreply, assign(socket, :selected_day, nil)}

      month == Date.beginning_of_month(socket.assigns.date) ->
        {:noreply, assign(socket, :selected_day, day)}

      true ->
        {:noreply,
         socket
         |> assign(:selected_day, day)
         |> push_patch(to: view_path(socket.assigns.user, month, :distribution))}
    end
  end

  def handle_event("load_more_months", _params, socket) do
    %{all_distribution_months: all_months, distribution_months: months} = socket.assigns
    more = Enum.slice(all_months, length(months), @months_per_page)

    {:noreply,
     socket
     |> assign(:distribution_months, months ++ more)
     |> update(:distribution_sessions, &(&1 ++ list_distribution_sessions(socket, more)))}
  end

  defp view_path(user, date, view) do
    Navigation.employee_path(user.id, %{
      miesiac: date,
      widok: Navigation.encode_employee_projects_view(view)
    })
  end

  # Calendars of this month and every earlier month with sessions, newest first. Older
  # months load a page at a time as the list is scrolled; re-renders keep the loaded ones.
  defp assign_view(%{assigns: %{view: :distribution}} = socket) do
    %{date: date, active_months: active_months} = socket.assigns
    date = Date.beginning_of_month(date)
    this_month = Navigation.current_month()

    all_months = [
      this_month
      | active_months
        |> Enum.map(&NaiveDateTime.to_date/1)
        |> Enum.filter(&Date.before?(&1, this_month))
    ]

    loaded = max(length(socket.assigns[:distribution_months] || []), @months_per_page)
    months = Enum.take(all_months, loaded)

    # A day stays selected across re-renders of its own month only.
    selected_day = socket.assigns[:selected_day]

    selected_day =
      if selected_day && Date.beginning_of_month(selected_day) == date, do: selected_day

    assign(socket,
      all_distribution_months: all_months,
      distribution_months: months,
      distribution_sessions: list_distribution_sessions(socket, months),
      selected_day: selected_day
    )
  end

  defp assign_view(socket) do
    %{date: date, user: user, scope: scope} = socket.assigns
    member_id = user.member.id

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

    assign(socket, projects: projects, selected_day: nil)
  end

  defp list_distribution_sessions(_socket, []), do: []

  defp list_distribution_sessions(socket, months) do
    {started_from, started_to} = WorkDistribution.started_range(months)

    Timetracker.list_sessions!(
      %{
        member_id: socket.assigns.user.member.id,
        started_from: started_from,
        started_to: started_to
      },
      scope: socket.assigns.scope,
      load: [:duration, :project]
    )
  end

  defp assign_monthly_payout(socket) do
    %{date: date, user: user, scope: scope} = socket.assigns

    salary =
      %{user_id: user.id, active_at: Date.end_of_month(date)}
      |> Payroll.list_salaries!(load: [monthly_payout: [month: date]], scope: scope)
      |> List.first()

    assign(socket, :monthly_payout, if(salary, do: salary.monthly_payout))
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

  attr :project, :map, required: true

  defp project_accordion(assigns) do
    ~H"""
    <div
      id={"project-accordion-#{@project.id}"}
      class="group grid grid-cols-[minmax(0,1fr)_min-content_min-content] gap-x-6 overflow-hidden"
    >
      <.button
        type="button"
        variant="unstyled"
        phx-click={toggle_project_accordion(@project.id)}
        class="group col-span-full grid w-full cursor-pointer grid-cols-subgrid items-center gap-x-6 py-4 text-left"
      >
        <span class="text-start wrap-break-word">{@project.name}</span>
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
              {gettext("No sessions this month")}
            </p>
          <% else %>
            <div
              :for={session <- @project.sessions}
              class="flex justify-between gap-x-4 text-base/snug text-grey-700"
            >
              <p class="min-w-0 wrap-break-word">{session.title}</p>
              <p class="shrink-0 text-nowrap">
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
