defmodule FirmowidWeb.Timetracker.Views.Index do
  @moduledoc false
  use FirmowidWeb, :live_view

  import FirmowidUI.Components.Button
  import FirmowidUI.Components.Link
  import FirmowidWeb.DesignSystem.Components.CoreComponents
  import Phoenix.Component, except: [link: 1]

  alias Ash.Error.Invalid
  alias Ash.Error.Unknown
  alias Ash.Error.Unknown.UnknownError
  alias Firmowid.TimeFormatter
  alias Firmowid.Timetracker
  alias Firmowid.Timetracker.Changes.NormalizeSessionBoundaries
  alias Firmowid.Timetracker.HoursRecord
  alias Firmowid.Timetracker.OverlapResolver
  alias Firmowid.Timetracker.Session
  alias Firmowid.Timetracker.TrimPlan
  alias FirmowidUI.Components.Inputs
  alias FirmowidWeb.Infrastructure.Utilities.LocalTime
  alias FirmowidWeb.Infrastructure.Utilities.PosthogBusinessEvents
  alias FirmowidWeb.Infrastructure.Utilities.QueryParams
  alias FirmowidWeb.Timetracker.Utilities.GroupedSessionForm
  alias FirmowidWeb.Timetracker.Utilities.Navigation
  alias FirmowidWeb.Timetracker.Utilities.SessionForm

  defp day_name(1), do: pgettext("weekday name", "Monday")
  defp day_name(2), do: pgettext("weekday name", "Tuesday")
  defp day_name(3), do: pgettext("weekday name", "Wednesday")
  defp day_name(4), do: pgettext("weekday name", "Thursday")
  defp day_name(5), do: pgettext("weekday name", "Friday")
  defp day_name(6), do: pgettext("weekday name", "Saturday")
  defp day_name(7), do: pgettext("weekday name", "Sunday")

  # Month names in the form used inside a full date, e.g. "5. października".
  defp month_name_in_date(1), do: pgettext("month name in a date", "January")
  defp month_name_in_date(2), do: pgettext("month name in a date", "February")
  defp month_name_in_date(3), do: pgettext("month name in a date", "March")
  defp month_name_in_date(4), do: pgettext("month name in a date", "April")
  defp month_name_in_date(5), do: pgettext("month name in a date", "May")
  defp month_name_in_date(6), do: pgettext("month name in a date", "June")
  defp month_name_in_date(7), do: pgettext("month name in a date", "July")
  defp month_name_in_date(8), do: pgettext("month name in a date", "August")
  defp month_name_in_date(9), do: pgettext("month name in a date", "September")
  defp month_name_in_date(10), do: pgettext("month name in a date", "October")
  defp month_name_in_date(11), do: pgettext("month name in a date", "November")
  defp month_name_in_date(12), do: pgettext("month name in a date", "December")

  # Month names in the form used after "in", e.g. "w październiku".
  defp month_name_after_in(1), do: pgettext("month name after 'in'", "January")
  defp month_name_after_in(2), do: pgettext("month name after 'in'", "February")
  defp month_name_after_in(3), do: pgettext("month name after 'in'", "March")
  defp month_name_after_in(4), do: pgettext("month name after 'in'", "April")
  defp month_name_after_in(5), do: pgettext("month name after 'in'", "May")
  defp month_name_after_in(6), do: pgettext("month name after 'in'", "June")
  defp month_name_after_in(7), do: pgettext("month name after 'in'", "July")
  defp month_name_after_in(8), do: pgettext("month name after 'in'", "August")
  defp month_name_after_in(9), do: pgettext("month name after 'in'", "September")
  defp month_name_after_in(10), do: pgettext("month name after 'in'", "October")
  defp month_name_after_in(11), do: pgettext("month name after 'in'", "November")
  defp month_name_after_in(12), do: pgettext("month name after 'in'", "December")

  def mount(_params, _session, socket) do
    scope = socket.assigns.ash_scope
    user = socket.assigns.current_user

    {:ok, last_session} = Session.most_recent(scope: scope, not_found_error?: false)

    active_projects =
      Timetracker.list_projects!(%{member_id: user.member.id, status: :active}, scope: scope)

    default_project_id =
      if last_session && Enum.any?(active_projects, &(&1.id == last_session.project_id)) do
        last_session.project_id
      end

    {:ok,
     socket
     |> assign(:main_class, "bg-white")
     |> assign(:form, to_form(SessionForm.changeset(%{"project_id" => default_project_id})))
     |> assign(:active_projects, active_projects)
     |> assign(:projects_by_id, Map.new(active_projects, &{&1.id, &1}))
     |> assign(:filter, nil)
     |> assign(:is_form_extended, false)
     |> assign(:edit_check, nil)
     |> assign_sessions()
     |> assign(:trim_plan, nil)}
  end

  def handle_params(params, _url, socket) do
    {:noreply,
     socket
     |> assign(:filter, parse_filter(params, socket.assigns.ash_scope))
     |> assign(:highlighted_task, parse_task(params))
     |> assign_filtered_tasks()
     |> assign_timesheet_month()}
  end

  # `?projekt=<id>&miesiac=2026-11-01` narrows the list to one project's month, the
  # same sessions the timesheet sums up. An unknown project shows the usual list.
  defp parse_filter(params, scope) do
    with {:ok, project_id} <- Ecto.UUID.cast(params["projekt"]),
         %Date{} = month <- QueryParams.parse_date(params, "miesiac", nil),
         [project] <- Timetracker.list_projects!(%{ids: [project_id]}, scope: scope) do
      %{project: project, month: Date.beginning_of_month(month)}
    else
      _no_filter -> nil
    end
  end

  # `&zadanie=<id>`, the newest session of a task, lights that task up for a moment;
  # the timesheet links to it.
  defp parse_task(params) do
    case Ecto.UUID.cast(params["zadanie"]) do
      {:ok, id} -> id
      :error -> nil
    end
  end

  # The filtered list shows the month's tasks, each task being all sessions with
  # one title, newest first so the running session leads its group.
  defp assign_filtered_tasks(%{assigns: %{filter: nil}} = socket), do: assign(socket, :filtered_tasks, [])

  defp assign_filtered_tasks(%{assigns: %{filter: filter}} = socket) do
    timezone = socket.assigns.timezone

    tasks =
      %{
        member_id: socket.assigns.current_user.member.id,
        project_id: filter.project.id,
        month: filter.month.month,
        year: filter.month.year
      }
      |> Timetracker.list_sessions!(scope: socket.assigns.ash_scope, query: [load: [:lockdown]])
      |> Enum.map(&to_local_time(&1, timezone))
      |> Enum.group_by(& &1.title)
      |> Enum.map(fn {_title, sessions} ->
        Enum.sort_by(sessions, & &1.start_datetime, {:desc, DateTime})
      end)
      |> Enum.sort_by(&calculate_total_duration/1, :desc)

    # An archived project from an older month is missing from the map, which
    # holds active projects and those of the recently loaded weeks.
    socket
    |> assign(:filtered_tasks, tasks)
    |> update(:projects_by_id, &Map.put(&1, filter.project.id, filter.project))
  end

  defp to_local_time(session, timezone) do
    session
    |> Map.update!(:start_datetime, &DateTime.shift_zone!(&1, timezone))
    |> Map.update!(:end_datetime, fn
      nil -> nil
      end_datetime -> DateTime.shift_zone!(end_datetime, timezone)
    end)
  end

  @doc """
  Month a session counts towards, taken in UTC as the session list and the
  timesheet count it.
  """
  @spec session_month(map()) :: Date.t()
  def session_month(session) do
    session.start_datetime
    |> DateTime.shift_zone!("Etc/UTC")
    |> DateTime.to_date()
    |> Date.beginning_of_month()
  end

  @doc ~s(Name of a month as it follows "in", for example "w listopadzie".)
  @spec month_after_in(Date.t()) :: String.t()
  def month_after_in(%Date{month: month}), do: month_name_after_in(month)

  @doc """
  Entrance of the session list when the filter opens or closes, and of the
  manual time fields when they open: it rises a few pixels and fades in. Only the entrance, since the outgoing list would stay
  beside the new one while it faded out. It ends with no classes left, as a
  lingering translate would anchor the rows' sticky headers and popovers.
  """
  @spec list_enter() :: JS.t()
  def list_enter do
    JS.transition(
      {"ease-out duration-200 motion-reduce:transition-none", "opacity-0 translate-y-2", ""},
      time: 200
    )
  end

  @doc "Name of a month as it stands alone, for example in \"Firmowid · listopad\"."
  @spec month_name(Date.t()) :: String.t()
  def month_name(%Date{} = date), do: TimeFormatter.format_date(date, "LLLL")

  def assign_sessions(%{assigns: assigns} = socket) when not is_map_key(assigns, :sessions_after) do
    member_id = socket.assigns.current_user.member.id
    last_four_weeks = List.last(week_starts(socket, %{member_id: member_id}, 4), Date.utc_today())

    socket
    |> assign(:sessions_after, last_four_weeks)
    |> assign_sessions()
  end

  def assign_sessions(%{assigns: %{sessions_after: %Date{} = after_date}} = socket) do
    scope = socket.assigns.ash_scope
    timezone = socket.assigns.timezone
    member_id = socket.assigns.current_user.member.id

    {:ok, sessions} =
      Session.list_user_sessions(%{after_date: after_date}, scope: scope)

    sessions = Enum.map(sessions, &to_local_time(&1, timezone))

    before_dt = DateTime.new!(after_date, ~T[00:00:00])

    next_sessions_after =
      socket
      |> week_starts(%{member_id: member_id, started_to: before_dt}, 1)
      |> List.first()

    {today_sessions, rest_sessions} =
      Enum.split_with(sessions, fn session ->
        DateTime.to_date(session.start_datetime) ==
          timezone |> DateTime.now!() |> DateTime.to_date()
      end)

    today_sessions = group_nearby(today_sessions)

    grouped_sessions =
      rest_sessions
      |> Enum.sort_by(& &1.start_datetime, {:desc, DateTime})
      |> Enum.group_by(&Date.beginning_of_week(&1.start_datetime))
      |> Enum.sort_by(fn {week, _sessions} -> week end, {:desc, Date})
      |> Enum.map(fn {week, sessions} ->
        {week,
         sessions
         |> Enum.group_by(&DateTime.to_date(&1.start_datetime))
         |> Enum.sort_by(fn {day, _sessions} -> day end, {:desc, Date})
         |> Enum.map(fn {day, sessions} ->
           {day, group_nearby(sessions)}
         end)}
      end)

    {:ok, current_session} = Session.get_current(scope: scope, not_found_error?: false)

    project_ids_in_sessions =
      sessions
      |> Enum.map(& &1.project_id)
      |> then(fn ids ->
        if current_session do
          [current_session.project_id | ids]
        else
          ids
        end
      end)
      |> Enum.uniq()

    projects_list = Timetracker.list_projects!(%{ids: project_ids_in_sessions}, scope: scope)
    projects_by_id = Map.new(projects_list, &{&1.id, &1})

    projects_by_id = Map.merge(socket.assigns.projects_by_id, projects_by_id)

    edited = if socket.assigns.is_form_extended, do: socket.assigns[:current_session]

    socket
    |> assign(:next_sessions_after, next_sessions_after)
    |> assign(:today_sessions, today_sessions)
    |> assign(:grouped_sessions, grouped_sessions)
    |> assign(:current_session, current_session)
    |> assign(:projects_by_id, projects_by_id)
    |> assign_session_form(edited, current_session)
    |> assign_page_title()
    |> assign_hours_record_submitted()
    |> assign_timesheet_month()
    |> assign_filtered_tasks()
  end

  # An open edit of the running session keeps what the user typed, but only while that
  # session is still the running one: stopped or replaced elsewhere, the edit is dropped.
  defp assign_session_form(socket, %Session{id: id}, %Session{id: id}), do: socket

  defp assign_session_form(socket, edited, current_session) do
    socket
    |> then(&if(edited, do: assign(&1, is_form_extended: false, edit_check: nil), else: &1))
    |> update(:form, fn form ->
      cond do
        current_session ->
          current_session
          |> SessionForm.from_session(socket.assigns.timezone)
          |> SessionForm.changeset(%{})
          |> to_form()

        edited ->
          to_form(SessionForm.changeset(%{"project_id" => edited.project_id}))

        true ->
          form
      end
    end)
  end

  # Mondays of the newest weeks with matching sessions, as dates in the user's timezone.
  defp week_starts(socket, filters, limit) do
    filters
    |> Timetracker.list_sessions!(
      scope: socket.assigns.ash_scope,
      query: [
        distinct: [:week_start],
        distinct_sort: [week_start: :desc],
        sort: [week_start: :desc],
        load: [:week_start],
        limit: limit
      ]
    )
    |> Enum.map(fn session ->
      session.week_start
      |> DateTime.from_naive!("Etc/UTC")
      |> DateTime.shift_zone!(socket.assigns.timezone)
      |> DateTime.to_date()
    end)
  end

  # Neighbouring sessions of one task share a row, even when only some were
  # remote; the row then shows a lighter house.
  def group_nearby(sessions) do
    Enum.chunk_by(sessions, fn session ->
      {session.title, session.project_id}
    end)
  end

  @doc "Grey pill with the total time beside a session list's heading."
  @spec total_pill_classes() :: String.t()
  def total_pill_classes do
    "rounded bg-grey-200 px-2.5 py-1 text-base/[1.25] font-semibold text-grey-900 tabular-nums"
  end

  def assign_page_title(socket) do
    case socket.assigns.current_session do
      nil -> assign(socket, :page_title, pgettext("page title", "Time tracker"))
      session -> assign(socket, :page_title, session.title)
    end
  end

  def expand_sessions(socket, session) do
    start_date = DateTime.to_date(session.start_datetime)

    if Date.before?(start_date, socket.assigns.sessions_after) do
      assign(socket, :sessions_after, start_date)
    else
      socket
    end
  end

  def handle_session_save_result(result, socket) do
    case result do
      {:ok, %{end_datetime: nil} = session} ->
        {:noreply,
         socket
         |> assign(:current_session, session)
         |> expand_sessions(session)
         |> assign_sessions()}

      {:ok, session} ->
        {:noreply,
         socket
         |> expand_sessions(session)
         |> assign_sessions()}

      {:error, %Unknown{} = error} ->
        if overlap_error?(error) do
          LiveToast.send_toast(:error, gettext("The session overlaps another session."))
        else
          raise error
        end

        {:noreply, socket}

      {:error, %Invalid{} = error} ->
        messages =
          Enum.map_join(error.errors, ", ", fn err ->
            translate_ash_message(err)
          end)

        LiveToast.send_toast(:error, messages)
        {:noreply, socket}

      {:error, _other} ->
        LiveToast.send_toast(:error, gettext("An unexpected error occurred."))
        {:noreply, socket}
    end
  end

  defp translate_ash_message(%{message: message} = error) when is_binary(message),
    do: Inputs.translate_error({message, Map.get(error, :vars, [])})

  defp translate_ash_message(_error), do: gettext("Unknown error")

  defp overlap_error?(%Unknown{errors: errors}) do
    Enum.any?(errors, fn
      %UnknownError{error: %Postgrex.Error{postgres: %{message: msg}}} ->
        String.contains?(msg, "overlaps")

      %UnknownError{error: message} when is_binary(message) ->
        String.contains?(message, "overlaps")

      _ ->
        false
    end)
  end

  # ── Overlap detection and resolution ─────────────────────────────────

  # TOCTOU note: The trim plan is computed here and shown to the user for
  # confirmation. Between this check and `confirm_overlap_save`, the overlap
  # landscape may change (another session created/modified). The DB trigger
  # `prevent_session_overlap` acts as the authoritative safety net — if
  # it fires during execution, we catch the error and ask the user to retry.
  defp save_with_overlap_check(attrs, socket) do
    scope = socket.assigns.ash_scope
    member_id = socket.assigns.current_user.member.id

    attrs = normalize_session_attrs(attrs)

    # The overlap plan must use the exact boundaries persisted by Session.
    %{start_datetime: new_start, end_datetime: new_end} = attrs

    case Session.list_overlapping(member_id, new_start, %{end_datetime: new_end}, scope: scope) do
      {:ok, []} ->
        # No overlaps — save normally
        save_session_directly(attrs, socket)

      {:ok, overlapping_sessions} ->
        case TrimPlan.compute(new_start, new_end, overlapping_sessions) do
          {:ok, actions} ->
            trim_plan = %{
              new_session_attrs: attrs,
              new_start: new_start,
              new_end: new_end,
              actions: actions,
              overlapping_sessions: overlapping_sessions
            }

            {:noreply,
             socket
             |> assign(:trim_plan, trim_plan)
             |> assign(:is_form_extended, false)}

          {:error, :locked_conflict, locked_sessions} ->
            titles = Enum.map_join(locked_sessions, ", ", & &1.title)

            LiveToast.send_toast(
              :error,
              gettext(
                "The session overlaps approved sessions: %{titles}. Change the time of the new session.",
                titles: titles
              )
            )

            {:noreply, socket}
        end

      {:error, _} ->
        LiveToast.send_toast(:error, gettext("Could not check for conflicts. Try again."))
        {:noreply, socket}
    end
  end

  defp normalize_session_attrs(attrs) do
    attrs
    |> Map.put_new_lazy(:start_datetime, fn -> DateTime.utc_now() end)
    |> Map.update!(:start_datetime, &NormalizeSessionBoundaries.datetime/1)
    |> Map.update(:end_datetime, nil, &NormalizeSessionBoundaries.datetime/1)
  end

  defp save_session_directly(attrs, socket) do
    scope = socket.assigns.ash_scope
    socket = assign(socket, is_form_extended: false)

    result = OverlapResolver.create_session(attrs, scope)

    handle_new_session_save_result(result, socket)
  end

  defp handle_new_session_save_result({:ok, session}, socket) do
    socket
    |> PosthogBusinessEvents.capture(:time_entry_created)
    |> then(&handle_session_save_result({:ok, session}, &1))
  end

  defp handle_new_session_save_result(result, socket), do: handle_session_save_result(result, socket)

  defp ash_update_sessions(session_updates, socket) do
    scope = socket.assigns.ash_scope

    results =
      Enum.reduce_while(session_updates, :ok, fn {session, attrs}, :ok ->
        case Session.update(session, attrs, scope: scope) do
          {:ok, _updated} -> {:cont, :ok}
          {:error, error} -> {:halt, {:error, session.id, error}}
        end
      end)

    case results do
      :ok ->
        :ok

      {:error, _session_id, %Unknown{} = error} ->
        if overlap_error?(error) do
          LiveToast.send_toast(:error, gettext("The session overlaps another session."))
        else
          LiveToast.send_toast(:error, gettext("An error occurred while updating the session."))
        end

      {:error, _session_id, %Invalid{errors: errors}} ->
        messages =
          Enum.map_join(errors, ", ", fn error ->
            translate_ash_message(error)
          end)

        LiveToast.send_toast(:error, messages)

      {:error, _session_id, %Ash.Error.Forbidden{}} ->
        LiveToast.send_toast(
          :error,
          gettext("You do not have permission to edit this session (it may be locked).")
        )

      {:error, _session_id, _other} ->
        LiveToast.send_toast(:error, gettext("An error occurred while updating the session."))
    end

    # Updates before a failure stay saved, so the list is reloaded either way.
    {:noreply, assign_sessions(socket)}
  end

  def edit_session(params, %{assigns: %{current_session: nil}} = socket) do
    {:noreply, assign(socket, form: to_form(SessionForm.changeset(params)))}
  end

  def edit_session(params, socket) do
    scope = socket.assigns.ash_scope
    current_session = socket.assigns.current_session

    current_session
    |> SessionForm.from_session(socket.assigns.timezone)
    |> SessionForm.changeset(params)
    |> SessionForm.update_attributes(socket.assigns.timezone)
    |> case do
      {:ok, attributes} ->
        current_session
        |> Session.update(attributes, scope: scope)
        |> handle_session_save_result(socket)

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp fetch_sessions_by_ids(ids, socket) do
    scope = socket.assigns.ash_scope
    Timetracker.list_sessions!(%{ids: ids}, scope: scope)
  end

  def edit_sessions(ids, form, socket) do
    form =
      form
      |> GroupedSessionForm.changeset()
      |> Ecto.Changeset.apply_changes()

    sessions = fetch_sessions_by_ids(ids, socket)

    session_updates =
      Enum.map(sessions, fn session ->
        entry = Enum.find(form.start_end_times, &(&1.id == session.id))

        {start_datetime, end_datetime} =
          SessionForm.times_to_datetimes(entry, socket.assigns.timezone)

        attrs = %{
          title: form.title,
          project_id: form.project_id,
          start_datetime: start_datetime,
          end_datetime: end_datetime,
          is_remote: entry.is_remote
        }

        {session, attrs}
      end)

    ash_update_sessions(session_updates, socket)
  end

  # Saves the workplace with the title and project: the form is rendered again
  # from the stored sessions, which would otherwise put back the old choice.
  def edit_sessions_realtime(ids, form, socket) do
    form =
      form
      |> GroupedSessionForm.changeset()
      |> Ecto.Changeset.apply_changes()

    session_updates =
      ids
      |> fetch_sessions_by_ids(socket)
      |> Enum.map(fn session ->
        entry = Enum.find(form.start_end_times, &(&1.id == session.id))
        {session, %{title: form.title, project_id: form.project_id, is_remote: entry.is_remote}}
      end)

    ash_update_sessions(session_updates, socket)
  end

  def handle_event("toggle_extended_form", _, %{assigns: %{current_session: nil}} = socket) do
    now = DateTime.now!(socket.assigns.timezone)

    {:noreply,
     socket
     |> update(:is_form_extended, &(!&1))
     |> assign(
       :form,
       socket.assigns.form.params
       |> Map.merge(%{
         "date" => DateTime.to_date(now),
         "start_time" => DateTime.to_time(now)
       })
       |> SessionForm.changeset()
       |> to_form()
     )}
  end

  def handle_event("toggle_extended_form", _, %{assigns: %{is_form_extended: true}} = socket) do
    {:noreply, close_current_session_edit(socket)}
  end

  def handle_event("toggle_extended_form", _, socket) do
    changeset =
      socket.assigns.current_session
      |> SessionForm.from_session(socket.assigns.timezone)
      |> SessionForm.changeset(%{})

    {:noreply,
     socket
     |> assign(:is_form_extended, true)
     |> assign(:form, to_form(changeset))
     |> assign(:edit_check, check_current_session_edit(changeset, socket))}
  end

  def handle_event("cancel_current_session_edit", _, socket) do
    {:noreply, close_current_session_edit(socket)}
  end

  def handle_event("save_current_session", %{"session_form" => params}, socket) do
    changeset = current_session_changeset(params, socket)

    case check_current_session_edit(changeset, socket) do
      {:ok, times} ->
        form = Ecto.Changeset.apply_changes(changeset)

        attributes =
          Map.merge(times, %{
            title: form.title,
            project_id: form.project_id,
            is_remote: form.is_remote
          })

        update_current_session_with_overlap_check(attributes, socket)

      error ->
        {:noreply, assign(socket, form: to_form(changeset), edit_check: error)}
    end
  end

  def handle_event("validate", %{"session_form" => session}, socket) do
    {:noreply, assign(socket, form: to_form(SessionForm.changeset(session)))}
  end

  def handle_event("validate_and_update_list_onsubmit", %{"sessions_form" => %{"ids" => ids} = form}, socket) do
    edit_sessions(ids, form, socket)
  end

  def handle_event("validate_and_update_list_onchange", %{"sessions_form" => %{"ids" => ids} = form}, socket) do
    edit_sessions_realtime(ids, form, socket)
  end

  # While the running session's times are open for editing, changes are only checked: they
  # are saved with "Save" (Figma "Edycja bieżącej sesji").
  def handle_event(
        "validate_and_update",
        %{"session_form" => form_params},
        %{assigns: %{is_form_extended: true, current_session: %Session{}}} = socket
      ) do
    changeset = current_session_changeset(form_params, socket)

    {:noreply,
     socket
     |> assign(:form, to_form(changeset))
     |> assign(:edit_check, check_current_session_edit(changeset, socket))}
  end

  def handle_event("validate_and_update", %{"session_form" => form_params}, socket) do
    edit_session(form_params, socket)
  end

  def handle_event("save", %{"session_form" => session}, socket) do
    case session
         |> SessionForm.changeset()
         |> SessionForm.create_attributes(
           socket.assigns.current_user.member.id,
           socket.assigns.timezone
         ) do
      {:ok, attrs} ->
        save_with_overlap_check(attrs, socket)

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  # See TOCTOU note in save_with_overlap_check/2 — stale plan is caught
  # by the DB trigger and surfaced as a retry toast.
  def handle_event("confirm_overlap_save", _params, socket) do
    %{new_session_attrs: attrs, actions: actions} = trim_plan = socket.assigns.trim_plan
    scope = socket.assigns.ash_scope

    result =
      case trim_plan do
        %{edited_session: %Session{} = session} ->
          OverlapResolver.execute_update(actions, session, attrs, scope)

        _new_session ->
          OverlapResolver.execute(actions, attrs, scope)
      end

    socket = assign(socket, trim_plan: nil)

    case result do
      {:ok, edited} when is_map_key(trim_plan, :edited_session) ->
        handle_session_save_result(
          {:ok, edited},
          assign(socket, is_form_extended: false, edit_check: nil)
        )

      {:ok, new_session} ->
        handle_new_session_save_result({:ok, new_session}, socket)

      {:error, %Unknown{} = error} ->
        if overlap_error?(error) do
          LiveToast.send_toast(:error, gettext("The session conflict has changed. Try again."))
        else
          raise error
        end

        {:noreply, assign_sessions(socket)}

      {:error, _} ->
        LiveToast.send_toast(:error, gettext("An unexpected error occurred. Try again."))
        {:noreply, assign_sessions(socket)}
    end
  end

  def handle_event("cancel_overlap_save", _params, socket) do
    {:noreply, assign(socket, trim_plan: nil)}
  end

  # Stops the session running now: the one this page shows may have ended
  # meanwhile in another tab or by the auto-stop.
  def handle_event("end_session", _, socket) do
    case Session.stop_current(scope: socket.assigns.ash_scope) do
      {:ok, _ended_session} ->
        {:noreply,
         socket
         |> assign(is_form_extended: false)
         |> assign_sessions()}

      {:error, _error} ->
        {:noreply, socket}
    end
  end

  def handle_event("delete_session", %{"id" => id}, socket) do
    scope = socket.assigns.ash_scope
    session = Timetracker.get_session_by_id!(id, scope: scope)

    case Session.destroy(session, scope: scope) do
      :ok ->
        {:noreply, assign_sessions(socket)}

      {:error, _error} ->
        LiveToast.send_toast(:error, gettext("Could not delete the session"))
        {:noreply, socket}
    end
  end

  # The small select in a row's work-mode slot switches all the row's sessions.
  def handle_event("set_work_mode", %{"ids" => ids, "is_remote" => is_remote}, socket) do
    ids
    |> fetch_sessions_by_ids(socket)
    |> Enum.map(&{&1, %{is_remote: is_remote}})
    |> ash_update_sessions(socket)
  end

  def handle_event("load_more", _, socket) do
    {:noreply,
     socket
     |> assign(:sessions_after, socket.assigns.next_sessions_after)
     |> assign_sessions()}
  end

  def handle_event("collapse_overnight_session", %{"id" => id}, socket) do
    scope = socket.assigns.ash_scope
    timezone = socket.assigns.timezone
    session = Timetracker.get_session_by_id!(id, scope: scope)

    start_local = DateTime.shift_zone!(session.start_datetime, timezone)
    start_date = DateTime.to_date(start_local)

    end_datetime =
      start_date
      |> DateTime.new!(~T[23:59:00], timezone)
      |> DateTime.shift_zone!("Etc/UTC")

    case Session.update(session, %{end_datetime: end_datetime}, scope: scope) do
      {:ok, _} ->
        {:noreply, assign_sessions(socket)}

      {:error, %Unknown{} = error} ->
        if overlap_error?(error) do
          LiveToast.send_toast(:error, gettext("The session overlaps another session."))
        else
          LiveToast.send_toast(:error, gettext("Could not update the session"))
        end

        {:noreply, socket}

      {:error, _} ->
        LiveToast.send_toast(:error, gettext("Could not update the session"))
        {:noreply, socket}
    end
  end

  def format_day_header(%Date{} = date) do
    day_name =
      Calendar.strftime(date, "%A", day_of_week_names: &day_name/1)

    day_number = Calendar.strftime(date, "%d.%m")
    "#{day_name} (#{day_number})"
  end

  def format_current_day_header(%Date{} = date) do
    gettext("%{weekday}, %{month} %{day}",
      weekday: day_name(Date.day_of_week(date)),
      day: date.day,
      month: month_name_in_date(date.month)
    )
  end

  # A form field that casts to its current value stays out of the changeset's
  # changes, so the form returns the raw "HH:MM" param instead of a %Time{}.
  # Saves the edited running session. When its new times overlap other sessions, it asks
  # first in the same confirmation as a new session, listing how they will be adjusted.
  defp update_current_session_with_overlap_check(attributes, socket) do
    %{current_session: session, ash_scope: scope} = socket.assigns
    start = NormalizeSessionBoundaries.datetime(attributes.start_datetime)

    finish =
      attributes.end_datetime && NormalizeSessionBoundaries.datetime(attributes.end_datetime)

    overlapping =
      case Session.list_overlapping(session.member_id, start, %{end_datetime: finish}, scope: scope) do
        {:ok, sessions} -> {:ok, Enum.reject(sessions, &(&1.id == session.id))}
        error -> error
      end

    case overlapping do
      {:ok, []} ->
        session
        |> Session.update(attributes, scope: scope)
        |> handle_session_save_result(assign(socket, is_form_extended: false, edit_check: nil))

      {:ok, sessions} ->
        case TrimPlan.compute(start, finish, sessions) do
          {:ok, actions} ->
            {:noreply,
             assign(socket, :trim_plan, %{
               new_session_attrs: attributes,
               new_start: start,
               new_end: finish,
               actions: actions,
               overlapping_sessions: sessions,
               edited_session: session
             })}

          {:error, :locked_conflict, locked_sessions} ->
            LiveToast.send_toast(
              :error,
              gettext(
                "The session overlaps approved sessions: %{titles}. Change the time of the new session.",
                titles: Enum.map_join(locked_sessions, ", ", & &1.title)
              )
            )

            {:noreply, socket}
        end

      {:error, _} ->
        LiveToast.send_toast(:error, gettext("Could not check for conflicts. Try again."))
        {:noreply, socket}
    end
  end

  defp close_current_session_edit(socket) do
    form =
      case socket.assigns.current_session do
        nil ->
          socket.assigns.form

        session ->
          session
          |> SessionForm.from_session(socket.assigns.timezone)
          |> SessionForm.changeset(%{})
          |> to_form()
      end

    assign(socket, is_form_extended: false, edit_check: nil, form: form)
  end

  defp current_session_changeset(params, socket) do
    socket.assigns.current_session
    |> SessionForm.from_session(socket.assigns.timezone)
    |> SessionForm.changeset(params)
  end

  # Checks the edited times of the running session. Returns `{:ok, times}` with the UTC start
  # and end (nil keeps it running), or `{:error, field, message}` for the field to mark.
  defp check_current_session_edit(changeset, socket) do
    form = Ecto.Changeset.apply_changes(changeset)
    timezone = socket.assigns.timezone
    now = DateTime.utc_now()
    now_label = now |> DateTime.shift_zone!(timezone) |> Calendar.strftime("%H:%M")

    with :ok <- check_edit_presence(form),
         start = LocalTime.to_utc(form.date, form.start_time, timezone),
         finish = form.end_time && LocalTime.to_utc(form.date, form.end_time, timezone),
         :ok <- check_edit_start(start, now, now_label),
         :ok <- check_edit_end(start, finish, now, now_label) do
      {:ok, %{start_datetime: start, end_datetime: finish}}
    end
  end

  defp check_edit_presence(%{date: nil}), do: {:error, :date, gettext("Enter the date.")}

  defp check_edit_presence(%{start_time: nil}), do: {:error, :start_time, gettext("Enter the start time.")}

  defp check_edit_presence(_form), do: :ok

  defp check_edit_start(start, now, now_label) do
    if DateTime.after?(start, now),
      do: {:error, :start_time, gettext("The start cannot be later than now (%{time}).", time: now_label)},
      else: :ok
  end

  defp check_edit_end(_start, nil, _now, _now_label), do: :ok

  defp check_edit_end(start, finish, now, now_label) do
    cond do
      DateTime.compare(finish, start) == :eq ->
        {:error, :end_time, gettext("The session must last at least a minute.")}

      DateTime.before?(finish, start) ->
        {:error, :end_time, gettext("“To” must be later than “From”.")}

      DateTime.after?(finish, now) ->
        {:error, :end_time,
         gettext(
           "The end cannot be later than now (%{time}). Leave “To” empty if the session is still going.",
           time: now_label
         )}

      true ->
        :ok
    end
  end

  def format_time(time) when is_binary(time), do: time
  def format_time(nil), do: nil
  def format_time(%Time{} = time), do: Calendar.strftime(time, "%H:%M")

  def calculate_total_duration(sessions) do
    Enum.reduce(sessions, 0, fn session, acc ->
      acc + (session.duration || 0)
    end)
  end

  def assign_hours_record_submitted(socket) do
    today = Date.utc_today()

    {:ok, hours_record} =
      HoursRecord.by_month(socket.assigns.current_user.member.id, today.month, today.year,
        scope: socket.assigns.ash_scope,
        not_found_error?: false
      )

    assign(socket, :is_hours_record_submitted, hours_record != nil)
  end

  # The timesheet link in the header sums up the month it opens: the filtered
  # month, or the current one.
  defp assign_timesheet_month(socket) do
    date =
      case socket.assigns.filter do
        nil -> socket.assigns.timezone |> DateTime.now!() |> DateTime.to_date()
        filter -> filter.month
      end

    seconds = Session.month_duration!(date, scope: socket.assigns.ash_scope)

    assign(socket, :timesheet_month, %{date: date, duration: format_month_duration(seconds)})
  end

  # A month without a full minute reads "0 h", as the timesheet shows it.
  defp format_month_duration(seconds) when seconds < 60, do: pgettext("duration", "%{hours} h", hours: 0)

  defp format_month_duration(seconds), do: TimeFormatter.format_duration(seconds)
end
