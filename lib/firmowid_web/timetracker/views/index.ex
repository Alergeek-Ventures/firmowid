defmodule FirmowidWeb.Timetracker.Views.Index do
  @moduledoc false
  use FirmowidWeb, :live_view

  import FirmowidWeb.DesignSystem.Components.Button
  import FirmowidWeb.DesignSystem.Components.CoreComponents, except: [button: 1]
  import FirmowidWeb.DesignSystem.Components.Link
  import Phoenix.Component, except: [link: 1]

  alias Ash.Error.Invalid
  alias Ash.Error.Unknown
  alias Ash.Error.Unknown.UnknownError
  alias Firmowid.Ash.Timetracker
  alias Firmowid.Ash.Timetracker.Changes.NormalizeSessionBoundaries
  alias Firmowid.Ash.Timetracker.HoursRecord, as: AshHoursRecord
  alias Firmowid.Ash.Timetracker.OverlapResolver
  alias Firmowid.Ash.Timetracker.Session, as: AshSession
  alias Firmowid.Ash.Timetracker.TrimPlan
  alias FirmowidWeb.Infrastructure.Utilities.PosthogBusinessEvents
  alias FirmowidWeb.Infrastructure.Utilities.TimeFormatter
  alias FirmowidWeb.Timetracker.Utilities.GroupedSessionForm
  alias FirmowidWeb.Timetracker.Utilities.SessionForm

  require Ash.Query

  @day_names %{
    1 => "Poniedziałek",
    2 => "Wtorek",
    3 => "Środa",
    4 => "Czwartek",
    5 => "Piątek",
    6 => "Sobota",
    7 => "Niedziela"
  }

  @month_names_genitive %{
    1 => "stycznia",
    2 => "lutego",
    3 => "marca",
    4 => "kwietnia",
    5 => "maja",
    6 => "czerwca",
    7 => "lipca",
    8 => "sierpnia",
    9 => "września",
    10 => "października",
    11 => "listopada",
    12 => "grudnia"
  }

  @month_names_locative %{
    1 => "styczniu",
    2 => "lutym",
    3 => "marcu",
    4 => "kwietniu",
    5 => "maju",
    6 => "czerwcu",
    7 => "lipcu",
    8 => "sierpniu",
    9 => "wrześniu",
    10 => "październiku",
    11 => "listopadzie",
    12 => "grudniu"
  }

  def mount(_params, _session, socket) do
    scope = socket.assigns.ash_scope
    user = socket.assigns.current_user

    {:ok, last_session} = AshSession.most_recent(scope: scope, not_found_error?: false)

    active_projects =
      Timetracker.list_projects!(%{user_id: user.id, status: :active}, scope: scope)

    default_project_id =
      if last_session && Enum.any?(active_projects, &(&1.id == last_session.project_id)) do
        last_session.project_id
      end

    {:ok,
     socket
     |> assign(:form, to_form(SessionForm.changeset(%{"project_id" => default_project_id})))
     |> assign(:active_projects, active_projects)
     |> assign(:projects_by_id, Map.new(active_projects, &{&1.id, &1}))
     |> assign_sessions()
     |> assign(:is_form_extended, false)
     |> assign(:trim_plan, nil)}
  end

  def assign_sessions(%{assigns: assigns} = socket) when not is_map_key(assigns, :sessions_after) do
    scope = socket.assigns.ash_scope
    user_id = socket.assigns.current_user.id
    timezone = socket.assigns.timezone

    weeks =
      %{user_id: user_id}
      |> Timetracker.query_to_list_sessions(scope: scope)
      |> Ash.Query.distinct(:week_start)
      |> Ash.Query.distinct_sort(week_start: :desc)
      |> Ash.Query.sort(week_start: :desc)
      |> Ash.Query.load(:week_start)
      |> Ash.Query.limit(4)
      |> Ash.read!(scope: scope)
      |> Enum.map(fn s ->
        s.week_start
        |> DateTime.from_naive!("Etc/UTC")
        |> DateTime.shift_zone!(timezone)
        |> DateTime.to_date()
      end)

    last_four_weeks = List.last(weeks, Date.utc_today())

    socket
    |> assign(:sessions_after, last_four_weeks)
    |> assign_sessions()
  end

  def assign_sessions(%{assigns: %{sessions_after: %Date{} = after_date}} = socket) do
    scope = socket.assigns.ash_scope
    timezone = socket.assigns.timezone
    user_id = socket.assigns.current_user.id

    {:ok, sessions} =
      AshSession.list_user_sessions(%{after_date: after_date}, scope: scope)

    sessions =
      Enum.map(sessions, fn session ->
        session
        |> Map.update!(:start_datetime, &DateTime.shift_zone!(&1, timezone))
        |> Map.update!(:end_datetime, fn
          nil -> nil
          end_datetime -> DateTime.shift_zone!(end_datetime, timezone)
        end)
      end)

    before_dt = DateTime.new!(after_date, ~T[00:00:00])

    next_weeks =
      %{user_id: user_id}
      |> Timetracker.query_to_list_sessions(scope: scope)
      |> Ash.Query.filter(start_datetime < ^before_dt)
      |> Ash.Query.distinct(:week_start)
      |> Ash.Query.distinct_sort(week_start: :desc)
      |> Ash.Query.sort(week_start: :desc)
      |> Ash.Query.load(:week_start)
      |> Ash.Query.limit(1)
      |> Ash.read!(scope: scope)
      |> Enum.map(fn s ->
        s.week_start
        |> DateTime.from_naive!("Etc/UTC")
        |> DateTime.shift_zone!(timezone)
        |> DateTime.to_date()
      end)

    next_sessions_after = List.first(next_weeks)

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

    {:ok, current_session} = AshSession.get_current(scope: scope, not_found_error?: false)

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

    socket
    |> assign(:next_sessions_after, next_sessions_after)
    |> assign(:today_sessions, today_sessions)
    |> assign(:grouped_sessions, grouped_sessions)
    |> assign(:current_session, current_session)
    |> assign(:projects_by_id, projects_by_id)
    |> update(:form, fn form ->
      case current_session do
        nil ->
          form

        session ->
          session
          |> SessionForm.from_session(socket.assigns.timezone)
          |> SessionForm.changeset(%{})
          |> to_form()
      end
    end)
    |> assign_page_title()
    |> assign_month_stats()
  end

  def group_nearby(sessions) do
    Enum.chunk_by(sessions, fn session -> {session.title, session.project_id} end)
  end

  def assign_page_title(socket) do
    case socket.assigns.current_session do
      nil -> assign(socket, :page_title, "Czasośledź")
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
          LiveToast.send_toast(:error, "Sesja nachodzi na inną sesję.")
        else
          raise error
        end

        {:noreply, socket}

      {:error, %Invalid{} = error} ->
        messages =
          Enum.map_join(error.errors, ", ", fn err -> Map.get(err, :message, "Nieznany błąd") end)

        LiveToast.send_toast(:error, messages)
        {:noreply, socket}

      {:error, _other} ->
        LiveToast.send_toast(:error, "Wystąpił nieoczekiwany błąd.")
        {:noreply, socket}
    end
  end

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
  # `prevent_overlapping_sessions` acts as the authoritative safety net — if
  # it fires during execution, we catch the error and ask the user to retry.
  defp save_with_overlap_check(attrs, socket) do
    scope = socket.assigns.ash_scope
    user_id = socket.assigns.current_user.id

    attrs = normalize_session_attrs(attrs)

    # The overlap plan must use the exact boundaries persisted by Session.
    {new_start, new_end} = effective_time_range(attrs)

    case AshSession.list_overlapping(user_id, new_start, %{end_datetime: new_end}, scope: scope) do
      {:ok, []} ->
        # No overlaps — save normally (original flow)
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
              "Sesja nachodzi na zatwierdzone sesje: #{titles}. Zmień czas nowej sesji."
            )

            {:noreply, socket}
        end

      {:error, _} ->
        LiveToast.send_toast(:error, "Nie udało się sprawdzić konfliktów. Spróbuj ponownie.")
        {:noreply, socket}
    end
  end

  defp effective_time_range(attrs) do
    start_dt = attrs[:start_datetime]
    end_dt = attrs[:end_datetime]
    {start_dt, end_dt}
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

    result = create_session(attrs, scope)

    handle_new_session_save_result(result, socket)
  end

  defp handle_new_session_save_result({:ok, session}, socket) do
    socket
    |> PosthogBusinessEvents.capture(:time_entry_created)
    |> then(&handle_session_save_result({:ok, session}, &1))
  end

  defp handle_new_session_save_result(result, socket), do: handle_session_save_result(result, socket)

  defp create_session(attrs, scope) do
    OverlapResolver.create_session(attrs, scope)
  end

  def validate_and_update(params, socket) do
    edit_session(params, socket)
  end

  defp ash_update_sessions(session_updates, socket) do
    scope = socket.assigns.ash_scope

    results =
      Enum.reduce_while(session_updates, :ok, fn {session, attrs}, :ok ->
        case AshSession.update(session, attrs, scope: scope) do
          {:ok, _updated} -> {:cont, :ok}
          {:error, error} -> {:halt, {:error, session.id, error}}
        end
      end)

    case results do
      :ok ->
        {:noreply, assign_sessions(socket)}

      {:error, _session_id, %Unknown{} = error} ->
        if overlap_error?(error) do
          LiveToast.send_toast(:error, "Sesja nachodzi na inną sesję.")
        else
          LiveToast.send_toast(:error, "Wystąpił błąd podczas aktualizacji sesji.")
        end

        {:noreply, socket}

      {:error, session_id, %Invalid{errors: errors}} ->
        Enum.each(errors, fn error ->
          LiveToast.send_toast(:error, "#{Exception.message(error)} (sesja ID: #{session_id})")
        end)

        {:noreply, socket}

      {:error, _session_id, %Ash.Error.Forbidden{}} ->
        LiveToast.send_toast(
          :error,
          "Brak uprawnień do edycji tej sesji (sesja może być zablokowana)."
        )

        {:noreply, socket}

      {:error, _session_id, _other} ->
        LiveToast.send_toast(:error, "Wystąpił błąd podczas aktualizacji sesji.")
        {:noreply, socket}
    end
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
        |> AshSession.update(attributes, scope: scope)
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
        times =
          form.start_end_times
          |> Enum.find(fn s -> s.id == session.id end)
          |> SessionForm.times_to_datetimes(socket.assigns.timezone)

        {start_datetime, end_datetime} = times

        attrs = %{
          title: form.title,
          project_id: form.project_id,
          start_datetime: start_datetime,
          end_datetime: end_datetime
        }

        {session, attrs}
      end)

    ash_update_sessions(session_updates, socket)
  end

  def edit_sessions_realtime(ids, %{"title" => title, "project_id" => project_id}, socket) do
    sessions = fetch_sessions_by_ids(ids, socket)

    session_updates =
      Enum.map(sessions, fn session ->
        {session, %{title: title, project_id: project_id}}
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

  def handle_event("toggle_extended_form", _, socket) do
    {:noreply, update(socket, :is_form_extended, &(!&1))}
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

  def handle_event("validate_and_update", %{"session_form" => form_params}, socket) do
    validate_and_update(form_params, socket)
  end

  def handle_event("save", %{"session_form" => session}, socket) do
    case session
         |> SessionForm.changeset()
         |> SessionForm.create_attributes(socket.assigns.current_user.id, socket.assigns.timezone) do
      {:ok, attrs} ->
        save_with_overlap_check(attrs, socket)

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  # See TOCTOU note in save_with_overlap_check/2 — stale plan is caught
  # by the DB trigger and surfaced as a retry toast.
  def handle_event("confirm_overlap_save", _params, socket) do
    %{new_session_attrs: attrs, actions: actions} = socket.assigns.trim_plan
    scope = socket.assigns.ash_scope

    result = OverlapResolver.execute(actions, attrs, scope)

    socket = assign(socket, trim_plan: nil)

    case result do
      {:ok, new_session} ->
        handle_new_session_save_result({:ok, new_session}, socket)

      {:error, %Unknown{} = error} ->
        if overlap_error?(error) do
          LiveToast.send_toast(:error, "Konflikt sesji uległ zmianie. Spróbuj ponownie.")
        else
          raise error
        end

        {:noreply, assign_sessions(socket)}

      {:error, _} ->
        LiveToast.send_toast(:error, "Wystąpił nieoczekiwany błąd. Spróbuj ponownie.")
        {:noreply, assign_sessions(socket)}
    end
  end

  def handle_event("cancel_overlap_save", _params, socket) do
    {:noreply, assign(socket, trim_plan: nil)}
  end

  def handle_event("end_session", _, socket) do
    scope = socket.assigns.ash_scope
    current_session = socket.assigns.current_session

    case AshSession.stop(current_session, scope: scope) do
      {:ok, ended_session} ->
        duration_seconds = DateTime.diff(ended_session.end_datetime, ended_session.start_datetime)
        _duration_minutes = div(duration_seconds, 60)

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

    case AshSession.destroy(session, scope: scope) do
      :ok ->
        {:noreply, assign_sessions(socket)}

      {:error, _error} ->
        LiveToast.send_toast(:error, "Nie udało się usunąć sesji")
        {:noreply, socket}
    end
  end

  def handle_event("edit_sessions", %{"sessions_form" => %{"ids" => ids} = form_params}, socket) do
    form =
      form_params
      |> GroupedSessionForm.changeset()
      |> Ecto.Changeset.apply_changes()

    sessions = fetch_sessions_by_ids(ids, socket)

    session_updates =
      Enum.map(sessions, fn session ->
        {start_datetime, end_datetime} =
          form.start_end_times
          |> Enum.find(fn s -> s.id == session.id end)
          |> SessionForm.times_to_datetimes(socket.assigns.timezone)

        attrs = %{
          title: form.title,
          project_id: form.project_id,
          start_datetime: start_datetime,
          end_datetime: end_datetime
        }

        {session, attrs}
      end)

    ash_update_sessions(session_updates, socket)
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

    case AshSession.update(session, %{end_datetime: end_datetime}, scope: scope) do
      {:ok, _} ->
        {:noreply, assign_sessions(socket)}

      {:error, %Unknown{} = error} ->
        if overlap_error?(error) do
          LiveToast.send_toast(:error, "Sesja nachodzi na inną sesję.")
        else
          LiveToast.send_toast(:error, "Nie udało się zaktualizować sesji")
        end

        {:noreply, socket}

      {:error, _} ->
        LiveToast.send_toast(:error, "Nie udało się zaktualizować sesji")
        {:noreply, socket}
    end
  end

  def format_day_header(%Date{} = date) do
    day_name =
      Calendar.strftime(date, "%A", day_of_week_names: fn number -> Map.get(@day_names, number, "Unknown") end)

    day_number = Calendar.strftime(date, "%d.%m")
    "#{day_name} (#{day_number})"
  end

  def format_current_day_header(%Date{} = date) do
    day_name = Map.fetch!(@day_names, Date.day_of_week(date))
    month_name = Map.fetch!(@month_names_genitive, date.month)

    "#{day_name}, #{date.day}. #{month_name}"
  end

  def format_week_header(%Date{} = date) do
    week_start = Date.beginning_of_week(date)
    week_end = Date.end_of_week(date)

    week_start_str =
      if week_start.month == week_end.month do
        Calendar.strftime(week_start, "%d")
      else
        Calendar.strftime(week_start, "%d.%m")
      end

    week_end_str = Calendar.strftime(week_end, "%d.%m.%Y")

    "TYDZIEŃ #{week_start_str}-#{week_end_str}"
  end

  def format_time(""), do: nil
  def format_time(nil), do: nil
  def format_time(%Time{} = time), do: Calendar.strftime(time, "%H:%M")

  def calculate_total_duration(sessions) do
    Enum.reduce(sessions, 0, fn session, acc ->
      acc + (session.duration || 0)
    end)
  end

  def assign_month_stats(socket) do
    scope = socket.assigns.ash_scope
    now = DateTime.now!(socket.assigns.timezone)

    total_query =
      Timetracker.query_to_list_sessions(
        %{month: now.month, year: now.year, user_id: socket.assigns.current_user.id},
        scope: scope
      )

    %{total: total_seconds} =
      Ash.aggregate!(total_query, {:total, :sum, field: :duration, default: 0}, scope: scope)

    hours = div(total_seconds, 60 * 60)
    minutes = rem(div(total_seconds, 60), 60)
    percentage = round(total_seconds / (160 * 3600) * 100)

    current_month = Map.fetch!(@month_names_locative, now.month)

    today = Date.utc_today()

    {:ok, hours_record} =
      AshHoursRecord.by_month(socket.assigns.current_user.id, today.month, today.year,
        scope: scope,
        not_found_error?: false
      )

    socket
    |> assign(:month_stats, %{
      hours: hours,
      minutes: minutes,
      elapsed: DateTime.shift(now, second: -total_seconds),
      percentage: percentage,
      month: current_month
    })
    |> assign(:is_hours_record_submitted, hours_record != nil)
  end
end
