defmodule FirmowidWeb.TimetrackerLive.Index do
  alias FirmowidWeb.TimetrackerLive.SessionForm
  alias Firmowid.Timetracker.Session
  alias Firmowid.Timetracker
  alias Firmowid.Accounts
  alias FirmowidWeb.Helpers.TimeFormatter
  use FirmowidWeb, :live_view

  def mount(_params, _session, socket) do
    Bodyguard.permit!(Timetracker, :read_user_sessions, socket.assigns.current_user)
    Bodyguard.permit!(Timetracker, :read_user_projects, socket.assigns.current_user)

    user = socket.assigns.current_user
    organization_id = user.organization_id
    organization = Accounts.get_organization_with_avatar(user.organization)

    Posthog.capture("$set", user.id, %{
      "$set" => %{
        email: user.email,
        name: user.name,
        role: user.role,
        system_role: user.system_role,
        employment_date:
          case user.employment_date do
            nil -> nil
            date -> Date.to_iso8601(date)
          end,
        organization_id: organization_id,
        organization_name: organization.name
      }
    })

    Posthog.capture("timetracker_view", user.id, %{
      organization_id: organization_id
    })

    four_weeks_ago =
      Date.utc_today() |> Date.beginning_of_week() |> Date.shift(week: -3)

    last_session = Timetracker.get_most_recent_session(socket.assigns.current_user.id)
    default_project_id = if last_session, do: last_session.project_id, else: nil

    {:ok,
     socket
     |> assign(:sessions_after, four_weeks_ago)
     |> assign_sessions()
     |> assign(:projects, Timetracker.list_user_projects(socket.assigns.current_user.id))
     |> assign(:form, to_form(SessionForm.changeset(%{"project_id" => default_project_id})))
     |> assign(:is_form_extended, false)}
  end

  def assign_sessions(%{assigns: %{sessions_after: after_date}} = socket) do
    sessions =
      Timetracker.list_user_sessions(socket.assigns.current_user.id, after_date: after_date)

    next_sessions_available =
      Timetracker.count_user_sessions(socket.assigns.current_user.id) > length(sessions)

    {today_sessions, rest_sessions} =
      Enum.split_with(sessions, fn session ->
        DateTime.to_date(session.start_datetime) == Date.utc_today()
      end)

    today_sessions = today_sessions |> group_nearby()

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
           {day, sessions |> group_nearby()}
         end)}
      end)

    socket
    |> assign(:today_sessions, today_sessions)
    |> assign(:grouped_sessions, grouped_sessions)
    |> assign(:next_sessions_available, next_sessions_available)
    |> assign(:current_session, Timetracker.get_current_session(socket.assigns.current_user.id))
    |> assign(:month_stats, calculate_month_stats(socket.assigns.current_user.id))
  end

  def group_nearby(sessions) do
    Enum.chunk_by(sessions, fn session -> {session.title, session.project_id} end)
  end

  def expand_sessions(socket, session) do
    start_date = session.start_datetime |> DateTime.to_date()

    if Date.before?(start_date, socket.assigns.sessions_after) do
      assign(socket, :sessions_after, start_date)
    else
      socket
    end
  end

  def handle_event("toggle_extended_form", _, socket) do
    now = DateTime.now!("Europe/Warsaw")

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

  def handle_event("validate", %{"session_form" => session}, socket) do
    {:noreply, assign(socket, form: to_form(SessionForm.changeset(session)))}
  end

  def handle_event("save", %{"session_form" => session}, socket) do
    {:ok, validated_session} =
      session |> SessionForm.changeset() |> SessionForm.attributes(socket.assigns.current_user.id)

    Bodyguard.permit!(
      Timetracker,
      :create_session,
      socket.assigns.current_user,
      validated_session
    )

    case Timetracker.start_session(validated_session) do
      {:ok, %{end_time: nil} = session} ->
        {:noreply,
         socket
         |> assign(is_form_extended: false, current_session: session)
         |> expand_sessions(session)
         |> assign_sessions()}

      {:ok, session} ->
        {:noreply,
         socket
         |> assign(is_form_extended: false)
         |> expand_sessions(session)
         |> assign_sessions()}

      {:error, :overlap} ->
        LiveToast.send_toast(:error, "Sesja nachodzi na inną sesję.")
        {:noreply, socket}

      {:error, changeset} ->
        {:noreply, socket |> assign(:form, to_form(changeset))}
    end
  end

  def handle_event("end_session", _, socket) do
    session = Timetracker.get_session!(socket.assigns.current_session.id)
    Bodyguard.permit!(Timetracker, :update_session, socket.assigns.current_user, session)

    case Timetracker.end_session(socket.assigns.current_session) do
      {:ok, _session} ->
        {:noreply, socket |> assign(:current_session, nil) |> assign_sessions()}

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

  def handle_event("edit_session", %{"session_form" => params}, socket) do
    session = Timetracker.get_session!(params["id"])

    Bodyguard.permit!(Timetracker, :update_session, socket.assigns.current_user, session)

    params =
      params
      |> Map.update("start_datetime", nil, &string_to_datetime/1)
      |> Map.update("end_datetime", nil, &string_to_datetime/1)

    case Timetracker.update_session(session.id, params) do
      {:ok, session} ->
        {:noreply,
         socket
         |> expand_sessions(session)
         |> assign_sessions()
         |> push_event("js-exec", %{
           to: "#edit-session-modal-#{session.id}",
           attr: "phx-remove"
         })}

      {:error, :overlap} ->
        LiveToast.send_toast(:error, "Sesja nachodzi na inną sesję.")
        {:noreply, socket}

      {:error, changeset} ->
        changeset.errors
        |> Enum.each(fn {_field, {message, _}} ->
          LiveToast.send_toast(:error, "#{message}")
        end)

        {:noreply, socket}
    end
  end

  def handle_event("load_more", _, socket) do
    Bodyguard.permit!(
      Timetracker,
      :read_user_sessions,
      socket.assigns.current_user
    )

    {:noreply,
     socket
     |> assign(:sessions_after, Date.shift(socket.assigns.sessions_after, week: -1))
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

  def format_time(%DateTime{} = datetime) do
    datetime
    |> DateTime.shift_zone!("Europe/Warsaw")
    |> Calendar.strftime("%H:%M")
  end

  def format_time(%Time{} = time) do
    time |> Calendar.strftime("%H:%M")
  end

  def calculate_total_duration(sessions) do
    Enum.reduce(sessions, 0, fn session, acc ->
      acc +
        Session.calculate_session_duration(session)
    end)
  end

  defp string_to_datetime(nil), do: nil

  defp string_to_datetime(""), do: nil

  defp string_to_datetime(string) do
    NaiveDateTime.from_iso8601!(string <> ":00")
    |> DateTime.from_naive!("Europe/Warsaw")
  end

  def calculate_month_stats(user_id) do
    now = DateTime.now!("Europe/Warsaw")
    total_seconds = Timetracker.get_sessions_duration_in_month(user_id, now)

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

    %{
      hours: hours,
      minutes: minutes,
      elapsed: DateTime.utc_now() |> DateTime.add(-total_seconds),
      percentage: percentage,
      month: current_month
    }
  end
end
