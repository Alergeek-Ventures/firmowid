defmodule FirmowidWeb.HoursRecord.Views.Index do
  @moduledoc "Shows monthly hours and allows submission and change requests for signed records."
  use FirmowidWeb, :live_view

  import FirmowidUI.Components.Button
  import FirmowidUI.Components.Link
  import FirmowidWeb.DesignSystem.Components.CoreComponents
  import FirmowidWeb.DesignSystem.Components.MonthPicker
  import FirmowidWeb.HoursRecord.Components.ChangeRequest

  import FirmowidWeb.HoursRecord.Components.Document,
    only: [in_progress: 1, sent: 1, pending_label: 1]

  import Phoenix.Component, except: [link: 1]

  alias Firmowid.LocalDate
  alias Firmowid.Payroll
  alias Firmowid.TimeFormatter
  alias Firmowid.Timetracker
  alias Firmowid.Timetracker.HoursRecord
  alias Firmowid.Timetracker.Session
  alias FirmowidWeb.Infrastructure.Utilities.QueryParams
  alias FirmowidWeb.Timetracker.Utilities.Navigation
  alias FirmowidWeb.Timetracker.Views.Index, as: TimetrackerIndex

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.ash_scope
    current_user = socket.assigns.current_user

    selected_date = Date.utc_today()
    active_months = Timetracker.months_with_sessions(%{member_id: current_user.member.id}, scope)
    {:ok, current_contract} = Payroll.load_current_contract(current_user.member.id, scope: scope)

    can_use_hours_records = current_user.member.name && not is_nil(current_contract)

    [settings_before, settings_after] =
      "To fill in the timesheet you must set your name and employment date in %{link}"
      |> gettext(link: "__LINK__")
      |> String.split("__LINK__", parts: 2)

    socket =
      socket
      |> assign(:selected_date, selected_date)
      |> assign(:active_months, active_months)
      |> assign(:can_use_hours_records, can_use_hours_records)
      |> assign(settings_before: settings_before, settings_after: settings_after)
      |> assign(:page_title, pgettext("hours record page", "Timesheet"))
      |> assign(:main_class, "bg-white")

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    month = QueryParams.parse_date(params, "miesiac", Date.beginning_of_month(Date.utc_today()))

    {:noreply,
     socket
     |> assign(selected_date: month, change_request_error: nil, just_sent?: false)
     |> assign(
       :month_label,
       month |> Firmowid.Cldr.Date.to_string!(format: "LLLL y") |> String.capitalize()
     )
     |> assign(:change_request_form, to_form(%{}, as: :change_request))
     |> refetch_data()}
  end

  @impl true
  def handle_event("toggle-project", %{"id" => project_id}, socket) do
    projects =
      Enum.map(socket.assigns.projects, fn
        %{id: ^project_id} = project ->
          Map.put(project, :expanded, !project.expanded)

        project ->
          project
      end)

    {:noreply, assign(socket, :projects, projects)}
  end

  def handle_event("change-month", %{"month" => month}, socket) do
    # handle_params assigns the month together with its data, so the page changes once.
    {:noreply, push_patch(socket, to: Navigation.hours_record_index_path(Date.from_iso8601!(month)))}
  end

  def handle_event("request-change", %{"change_request" => params}, socket) do
    scope = socket.assigns.ash_scope
    date = socket.assigns.selected_date

    with {:ok, record} <-
           HoursRecord.by_month(socket.assigns.current_user.member.id, date.month, date.year, scope: scope),
         {:ok, _record} <-
           HoursRecord.request_change(
             record,
             Map.take(params, ["change_request_kind", "change_request_reason"]),
             scope: scope
           ) do
      {:noreply,
       socket
       |> assign(:change_request_error, nil)
       |> refetch_data()
       |> push_event("js-exec", %{to: "#hours-record-change-request", attr: "data-cancel"})}
    else
      {:error, _error} ->
        {:noreply,
         socket
         |> assign(:change_request_form, to_form(params, as: :change_request))
         |> assign(
           :change_request_error,
           gettext(
             "Could not submit the request. Enter a reason (up to 2000 characters). If a request already exists, refresh the page."
           )
         )}
    end
  end

  def handle_event("withdraw-change-request", _params, socket) do
    {:ok, _record} =
      HoursRecord.withdraw_change_request(socket.assigns.current_hours_record,
        scope: socket.assigns.ash_scope
      )

    {:noreply, refetch_data(socket)}
  end

  @impl true
  def handle_info(:upload_complete, socket) do
    {:noreply, socket |> assign(:just_sent?, true) |> refetch_data()}
  end

  def refetch_data(socket) do
    scope = socket.assigns.ash_scope
    selected_date = socket.assigns.selected_date
    member_id = socket.assigns.current_user.member.id
    month = selected_date.month
    year = selected_date.year

    # A project open in one month stays open in the next, so switching months does
    # not fold it away.
    expanded_ids =
      for %{expanded: true, id: id} <- socket.assigns[:projects] || [], into: MapSet.new(), do: id

    projects =
      member_id
      |> Timetracker.projects_duration_for_month(selected_date, scope)
      |> Enum.map(fn project ->
        # Eagerly fetch sessions grouped by title for this user+project+month
        grouped_sessions =
          %{member_id: member_id, project_id: project.id, month: month, year: year}
          |> Timetracker.list_sessions!(scope: scope)
          |> Enum.group_by(& &1.title)
          |> Enum.map(fn {title, ss} ->
            # The newest session names the task in the time tracker's filtered list.
            newest = Enum.max_by(ss, & &1.start_datetime, DateTime)
            %{id: newest.id, title: title, duration: ss |> Enum.map(& &1.duration) |> Enum.sum()}
          end)
          |> Enum.sort_by(& &1.duration, :desc)

        Map.merge(project, %{
          expanded: MapSet.member?(expanded_ids, project.id),
          sessions: grouped_sessions
        })
      end)

    total_duration = Session.month_duration!(selected_date, scope: scope)

    {:ok, current_month_hours_record} =
      HoursRecord.by_month(member_id, month, year,
        scope: scope,
        load: [:blob],
        not_found_error?: false
      )

    period_records =
      Timetracker.list_hours_records!(
        %{member_id: member_id, month: month, year: year, submission_status: nil},
        scope: scope
      )

    {:ok, running_session} = Session.get_current(scope: scope)

    socket
    |> assign(:running_session, running_session)
    # The record is signed once the month is over; until then it can only be previewed.
    |> assign(
      :month_in_progress?,
      Date.compare(Date.end_of_month(selected_date), LocalDate.today()) != :lt
    )
    |> assign(:current_hours_record, current_month_hours_record)
    |> assign(
      :change_requests,
      # A request still waiting for a decision is shown inside the document card.
      Enum.filter(
        period_records,
        &(&1.change_requested_at && &1.change_request_decision &&
            &1.submission_status == :submitted)
      )
    )
    |> assign(
      :previous_hours_records,
      Enum.filter(period_records, &(&1.submission_status == :withdrawn))
    )
    |> assign(:projects, projects)
    |> assign(:total_duration, total_duration)
  end
end
