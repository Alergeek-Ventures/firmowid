defmodule FirmowidWeb.TimetrackerLive.Index do
  @moduledoc false
  use FirmowidWeb, :live_view

  alias Firmowid.Analytics
  alias Firmowid.Timetracker
  alias Firmowid.Timetracker.Session
  alias FirmowidWeb.Helpers.TimeFormatter
  alias FirmowidWeb.TimetrackerLive.GroupedSessionForm
  alias FirmowidWeb.TimetrackerLive.SessionForm

  def mount(_params, _session, socket) do
    Bodyguard.permit!(Timetracker, :read_user_sessions, socket.assigns.current_user)
    Bodyguard.permit!(Timetracker, :read_user_projects, socket.assigns.current_user)

    last_session = Timetracker.get_most_recent_session(socket.assigns.current_user.id)
    active_projects = Timetracker.list_user_active_projects(socket.assigns.current_user.id)

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
     |> assign(:is_form_extended, false)}
  end

  def assign_sessions(%{assigns: assigns} = socket) when not is_map_key(assigns, :sessions_after) do
    last_four_weeks =
      socket.assigns.current_user.id
      |> Timetracker.weeks_with_user_sessions(timezone: socket.assigns.timezone, limit: 4)
      |> List.last(Date.utc_today())

    socket
    |> assign(:sessions_after, last_four_weeks)
    |> assign_sessions()
  end

  def assign_sessions(%{assigns: %{sessions_after: %Date{} = after_date}} = socket) do
    timezone = socket.assigns.timezone

    sessions =
      socket.assigns.current_user.id
      |> Timetracker.list_user_sessions(after_date: after_date)
      |> Enum.map(fn session ->
        session
        |> Map.update!(:start_datetime, &DateTime.shift_zone!(&1, timezone))
        |> Map.update!(:end_datetime, fn
          nil -> nil
          end_datetime -> DateTime.shift_zone!(end_datetime, timezone)
        end)
      end)

    next_sessions_after =
      socket.assigns.current_user.id
      |> Timetracker.weeks_with_user_sessions(
        timezone: timezone,
        limit: 1,
        after_date: after_date
      )
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

    current_session = Timetracker.get_current_session(socket.assigns.current_user.id)

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

    projects_by_id = project_ids_in_sessions |> Timetracker.list_projects_by_ids() |> Map.new(&{&1.id, &1})
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
      {:ok, %{end_time: nil} = session} ->
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

      {:error, :overlap} ->
        LiveToast.send_toast(:error, "Sesja nachodzi na inną sesję.")
        {:noreply, socket}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  def validate_and_update(params, socket) do
    current_sessions_ids =
      socket.assigns.today_sessions
      |> Enum.at(0)
      |> Enum.map(& &1.id)

    if length(current_sessions_ids) > 1 do
      edit_sessions_realtime(current_sessions_ids, params, socket)
    else
      edit_session(params, socket)
    end
  end

  defp timetracker_update_sessions(changesets, socket) do
    case Timetracker.update_sessions(changesets) do
      {:ok, _sessions} ->
        {:noreply, assign_sessions(socket)}

      {:error, :overlap} ->
        LiveToast.send_toast(:error, "Sesja nachodzi na inną sesję.")
        {:noreply, socket}

      {:error, session_id, changeset, _changes_so_far} ->
        Enum.each(changeset.errors, fn {_field, {message, _}} ->
          LiveToast.send_toast(:error, "#{message} (sesja ID: #{session_id})")
        end)

        {:noreply, socket}
    end
  end

  def edit_session(params, socket) do
    current_session = socket.assigns.current_session

    current_session
    |> SessionForm.from_session(socket.assigns.timezone)
    |> SessionForm.changeset(params)
    |> SessionForm.attributes(socket.assigns.current_user.id, socket.assigns.timezone)
    |> case do
      {:ok, attributes} ->
        Bodyguard.permit!(
          Timetracker,
          :update_session,
          socket.assigns.current_user,
          current_session
        )

        current_session
        |> Timetracker.update_session(attributes)
        |> handle_session_save_result(socket)

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp ids_to_session_changeset(ids, socket, attrs \\ %{}) do
    ids
    |> Timetracker.list_sessions_by_ids()
    |> Enum.map(fn session ->
      Bodyguard.permit!(Timetracker, :update_session, socket.assigns.current_user, session)
      Session.changeset(session, attrs)
    end)
  end

  def edit_sessions(ids, form, socket) do
    form =
      form
      |> GroupedSessionForm.changeset()
      |> Ecto.Changeset.apply_changes()

    ids
    |> ids_to_session_changeset(socket)
    |> GroupedSessionForm.from_changesets(form, socket.assigns.timezone)
    |> timetracker_update_sessions(socket)
  end

  def edit_sessions_realtime(ids, %{"title" => title, "project_id" => project_id}, socket) do
    ids
    |> ids_to_session_changeset(socket, %{title: title, project_id: project_id})
    |> timetracker_update_sessions(socket)
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
    {:ok, validated_session} =
      session
      |> SessionForm.changeset()
      |> SessionForm.attributes(socket.assigns.current_user.id, socket.assigns.timezone)

    Bodyguard.permit!(
      Timetracker,
      :create_session,
      socket.assigns.current_user,
      validated_session
    )

    socket = assign(socket, is_form_extended: false)

    result = Timetracker.start_session(validated_session)

    case result do
      {:ok, started_session} ->
        Analytics.track_event("session_start", socket.assigns.current_user, %{
          project_id: started_session.project_id
        })

      _ ->
        :ok
    end

    handle_session_save_result(result, socket)
  end

  def handle_event("end_session", _, socket) do
    session = Timetracker.get_session!(socket.assigns.current_session.id)
    Bodyguard.permit!(Timetracker, :update_session, socket.assigns.current_user, session)

    case Timetracker.end_session(socket.assigns.current_session) do
      {:ok, ended_session} ->
        duration_minutes = div(Session.calculate_session_duration(ended_session), 60)

        Analytics.track_event("session_end", socket.assigns.current_user, %{
          session_duration_minutes: duration_minutes,
          project_id: ended_session.project_id
        })

        {:noreply,
         socket
         |> assign(is_form_extended: false)
         |> assign_sessions()}

      {:error, _changeset} ->
        {:noreply, socket}
    end
  end

  def handle_event("delete_session", %{"id" => id}, socket) do
    session = Timetracker.get_session!(id)
    Bodyguard.permit!(Timetracker, :delete_session, socket.assigns.current_user, session)

    case Timetracker.delete_session(id) do
      {:ok, _session} ->
        {:noreply, assign_sessions(socket)}

      {:error, _changeset} ->
        LiveToast.send_toast(:error, "Nie udało się usunąć sesji")
        {:noreply, socket}
    end
  end

  def handle_event("edit_sessions", %{"sessions_form" => %{"ids" => ids} = form}, socket) do
    form =
      form
      |> GroupedSessionForm.changeset()
      |> Ecto.Changeset.apply_changes()

    ids
    |> Timetracker.list_sessions_by_ids()
    |> Enum.map(fn session ->
      Bodyguard.permit!(Timetracker, :update_session, socket.assigns.current_user, session)

      Session.changeset(session)
    end)
    |> GroupedSessionForm.from_changesets(
      form,
      socket.assigns.timezone
    )
    |> timetracker_update_sessions(socket)
  end

  def handle_event("load_more", _, socket) do
    Bodyguard.permit!(
      Timetracker,
      :read_user_sessions,
      socket.assigns.current_user
    )

    {:noreply,
     socket
     |> assign(:sessions_after, socket.assigns.next_sessions_after)
     |> assign_sessions()}
  end

  def format_day_header(%Date{} = date) do
    day_name =
      Calendar.strftime(date, "%A",
        day_of_week_names: fn number ->
          case number do
            1 -> "Poniedziałek"
            2 -> "Wtorek"
            3 -> "Środa"
            4 -> "Czwartek"
            5 -> "Piątek"
            6 -> "Sobota"
            7 -> "Niedziela"
            _ -> "Unknown"
          end
        end
      )

    day_number = Calendar.strftime(date, "%d.%m")
    "#{day_name} (#{day_number})"
  end

  def format_current_day_header(%Date{} = date) do
    day_name =
      case Date.day_of_week(date) do
        1 -> "Poniedziałek"
        2 -> "Wtorek"
        3 -> "Środa"
        4 -> "Czwartek"
        5 -> "Piątek"
        6 -> "Sobota"
        7 -> "Niedziela"
      end

    month_name =
      case date.month do
        1 -> "stycznia"
        2 -> "lutego"
        3 -> "marca"
        4 -> "kwietnia"
        5 -> "maja"
        6 -> "czerwca"
        7 -> "lipca"
        8 -> "sierpnia"
        9 -> "września"
        10 -> "października"
        11 -> "listopada"
        12 -> "grudnia"
      end

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
      acc +
        Session.calculate_session_duration(session)
    end)
  end

  def assign_month_stats(socket) do
    now = DateTime.now!(socket.assigns.timezone)

    total_seconds =
      Timetracker.get_sessions_duration_in_month(socket.assigns.current_user.id, now)

    hours = div(total_seconds, 60 * 60)
    minutes = rem(div(total_seconds, 60), 60)
    percentage = round(total_seconds / (160 * 3600) * 100)

    current_month =
      case now.month do
        1 -> "styczniu"
        2 -> "lutym"
        3 -> "marcu"
        4 -> "kwietniu"
        5 -> "maju"
        6 -> "czerwcu"
        7 -> "lipcu"
        8 -> "sierpniu"
        9 -> "wrześniu"
        10 -> "październiku"
        11 -> "listopadzie"
        12 -> "grudniu"
      end

    assign(socket, :month_stats, %{
      hours: hours,
      minutes: minutes,
      elapsed: DateTime.add(now, -total_seconds),
      percentage: percentage,
      month: current_month
    })
  end
end
