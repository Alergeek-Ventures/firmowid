defmodule FirmowidWeb.TimetrackerLive.Index do
  @moduledoc false
  use FirmowidWeb, :live_view

  alias Firmowid.Accounts
  alias Firmowid.Timetracker
  alias Firmowid.Timetracker.Session
  alias FirmowidWeb.Helpers.TimeFormatter
  alias FirmowidWeb.TimetrackerLive.SessionForm

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
        # We have to stringify datetime before sending because of posthog's weird decision
        # https://github.com/PostHog/posthog-elixir/blob/44b47bf7a54667879b0eeea79b92b309f62fb73c/lib/posthog/event.ex#L156
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

    last_session = Timetracker.get_most_recent_session(socket.assigns.current_user.id)
    default_project_id = if last_session, do: last_session.project_id

    {:ok,
     socket
     |> assign(:sessions_after, Date.utc_today())
     |> assign_sessions()
     |> assign(:projects, Timetracker.list_user_projects(socket.assigns.current_user.id))
     |> assign(:form, to_form(SessionForm.changeset(%{"project_id" => default_project_id})))
     |> assign(:is_form_extended, false)}
  end

  def assign_sessions(%{assigns: %{sessions_after: after_date}} = socket, opts \\ []) do
    timezone = socket.assigns.timezone

    limit = Keyword.get(opts, :limit, 5)

    {new_sessions, next_date} =
      Timetracker.list_user_sessions_paginated(socket.assigns.current_user.id,
        after_date: after_date,
        limit: limit
      )

    new_sessions =
      new_sessions
      |> Enum.map(fn session ->
        session
        |> Map.update!(:start_datetime, &DateTime.shift_zone!(&1, timezone))
        |> Map.update!(:end_datetime, fn
          nil -> nil
          end_datetime -> DateTime.shift_zone!(end_datetime, timezone)
        end)
      end)
      |> Session.put_lockdowns()

    next_sessions_available = not is_nil(next_date)

    existing_sessions = Map.get(socket.assigns, :sessions, [])

    sessions =
      new_sessions ++
        Enum.reject(existing_sessions, fn session ->
          Enum.find(new_sessions, &(&1.id == session.id))
        end)

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

    socket
    |> assign(:sessions, sessions)
    |> assign(:next_date, next_date)
    |> assign(:today_sessions, today_sessions)
    |> assign(:grouped_sessions, grouped_sessions)
    |> assign(:next_sessions_available, next_sessions_available)
    |> assign(:current_session, Timetracker.get_current_session(socket.assigns.current_user.id))
    |> assign_month_stats()
  end

  def reload_sessions(socket) do
    timezone = socket.assigns.timezone
    current_count = max(length(Map.get(socket.assigns, :sessions, [])), 5)

    {sessions, next_date} =
      Timetracker.list_user_sessions_paginated(socket.assigns.current_user.id,
        after_date: Date.utc_today(),
        limit: current_count
      )

    sessions =
      sessions
      |> Enum.map(fn session ->
        session
        |> Map.update!(:start_datetime, &DateTime.shift_zone!(&1, timezone))
        |> Map.update!(:end_datetime, fn
          nil -> nil
          end_datetime -> DateTime.shift_zone!(end_datetime, timezone)
        end)
      end)
      |> Session.put_lockdowns()

    next_sessions_available = not is_nil(next_date)

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

    socket
    |> assign(:sessions, sessions)
    |> assign(:next_date, next_date)
    |> assign(:today_sessions, today_sessions)
    |> assign(:grouped_sessions, grouped_sessions)
    |> assign(:next_sessions_available, next_sessions_available)
    |> assign(:current_session, Timetracker.get_current_session(socket.assigns.current_user.id))
    |> assign_month_stats()
  end

  def group_nearby(sessions) do
    Enum.chunk_by(sessions, fn session -> {session.title, session.project_id} end)
  end

  def expand_sessions(socket, session) do
    start_date = DateTime.to_date(session.start_datetime)

    if Date.before?(start_date, socket.assigns.sessions_after) do
      assign(socket, :sessions_after, start_date)
    else
      socket
    end
  end

  def handle_event("toggle_extended_form", _, socket) do
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

  def handle_event("validate", %{"session_form" => session}, socket) do
    {:noreply, assign(socket, form: to_form(SessionForm.changeset(session)))}
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

    case Timetracker.start_session(validated_session) do
      {:ok, %{end_time: nil} = session} ->
        {:noreply,
         socket
         |> assign(is_form_extended: false, current_session: session)
         |> expand_sessions(session)
         |> reload_sessions()}

      {:ok, session} ->
        {:noreply,
         socket
         |> assign(is_form_extended: false)
         |> expand_sessions(session)
         |> reload_sessions()}

      {:error, :overlap} ->
        LiveToast.send_toast(:error, "Sesja nachodzi na inną sesję.")
        {:noreply, socket}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  def handle_event("end_session", _, socket) do
    session = Timetracker.get_session!(socket.assigns.current_session.id)
    Bodyguard.permit!(Timetracker, :update_session, socket.assigns.current_user, session)

    case Timetracker.end_session(socket.assigns.current_session) do
      {:ok, _session} ->
        {:noreply,
         socket
         |> assign(:current_session, nil)
         |> reload_sessions()}

      {:error, _changeset} ->
        {:noreply, socket}
    end
  end

  def handle_event("delete_session", %{"id" => id}, socket) do
    session = Timetracker.get_session!(id)
    Bodyguard.permit!(Timetracker, :delete_session, socket.assigns.current_user, session)

    case Timetracker.delete_session(id) do
      {:ok, _session} ->
        {:noreply, reload_sessions(socket)}

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
      |> Map.update("start_datetime", nil, &string_to_datetime(&1, socket.assigns.timezone))
      |> Map.update("end_datetime", nil, &string_to_datetime(&1, socket.assigns.timezone))

    case Timetracker.update_session(session.id, params) do
      {:ok, session} ->
        {:noreply,
         socket
         |> reload_sessions()
         |> push_event("js-exec", %{
           to: "#edit-session-modal-#{session.id}",
           attr: "phx-remove"
         })}

      {:error, :overlap} ->
        LiveToast.send_toast(:error, "Sesja nachodzi na inną sesję.")
        {:noreply, socket}

      {:error, changeset} ->
        Enum.each(changeset.errors, fn {_field, {message, _}} ->
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
     |> assign(:sessions_after, socket.assigns.next_date)
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

  def format_time(%Time{} = time) do
    Calendar.strftime(time, "%H:%M")
  end

  def calculate_total_duration(sessions) do
    Enum.reduce(sessions, 0, fn session, acc ->
      acc +
        Session.calculate_session_duration(session)
    end)
  end

  defp string_to_datetime("", _timezone), do: nil
  defp string_to_datetime(nil, _timezone), do: nil

  defp string_to_datetime(string, timezone) do
    (string <> ":00")
    |> NaiveDateTime.from_iso8601!()
    |> DateTime.from_naive!(timezone)
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
