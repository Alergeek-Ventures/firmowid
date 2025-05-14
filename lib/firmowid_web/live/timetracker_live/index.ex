defmodule FirmowidWeb.TimetrackerLive.Index do
  alias FirmowidWeb.TimetrackerLive.SessionForm
  alias Firmowid.Timetracker.Session
  alias Firmowid.Timetracker
  alias Firmowid.Accounts
  use FirmowidWeb, :live_view
  import FirmowidWeb.Components.Timetracker.SubnavigationButtons

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

    if connected?(socket), do: :timer.send_interval(5000, self(), :tick)

    {:ok,
     socket
     |> assign(:projects, Timetracker.list_user_projects(socket.assigns.current_user.id))
     |> assign_sessions()
     |> assign(
       :form,
       to_form(
         SessionForm.changeset(%{
           date: Date.utc_today(),
           start_time: Time.utc_now()
         })
       )
     )
     |> assign(:is_form_extended, false)}
  end

  def assign_sessions(socket) do
    grouped_sessions =
      Timetracker.list_user_sessions(socket.assigns.current_user.id)
      |> Enum.sort_by(& &1.start_datetime, DateTime)
      |> Enum.group_by(&Date.to_string(&1.start_datetime))
      |> Enum.sort_by(fn {day, _sessions} -> day end, :desc)
      |> Enum.map(fn {day, sessions} ->
        {day, group_nearby(sessions)}
      end)

    socket
    |> assign(:grouped_sessions, grouped_sessions)
    |> assign(:current_session, Timetracker.get_current_session(socket.assigns.current_user.id))
    |> assign(:month_stats, calculate_month_stats(socket.assigns.current_user.id))
  end

  def group_nearby(enumarable) do
    Enum.reduce(enumarable, [], fn session, acc ->
      case acc do
        [] ->
          [[session]]

        [[last_session | _] = group | rest] ->
          if last_session.title === session.title and
               last_session.project_id === session.project_id do
            [[session | group] | rest]
          else
            [[session] | acc]
          end
      end
    end)
  end

  def handle_info(:tick, socket) do
    {:noreply, socket |> assign_sessions()}
  end

  def handle_event("toggle_extended_form", _, socket) do
    {:noreply, socket |> update(:is_form_extended, &(!&1))}
  end

  def handle_event("validate", %{"session_form" => session}, socket) do
    {:noreply,
     socket
     |> assign(
       :form,
       to_form(SessionForm.changeset(%SessionForm{}, session))
     )}
  end

  def handle_event("save", %{"session_form" => session}, socket) do
    Bodyguard.permit!(Timetracker, :create_session, socket.assigns.current_user)

    {:ok, validated_session} =
      session |> SessionForm.changeset() |> SessionForm.attributes(socket.assigns.current_user.id)

    case Timetracker.start_session(validated_session) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(
           :form,
           to_form(
             SessionForm.changeset(%{
               date: Date.utc_today(),
               start_time: Time.utc_now()
             })
           )
         )
         |> assign(:is_form_extended, false)
         |> assign_sessions()}

      {:error, changeset} ->
        {:noreply, socket |> assign(:form, to_form(changeset))}
    end
  end

  def handle_event("end_session", _, socket) do
    Bodyguard.permit!(
      Timetracker,
      :update_session,
      socket.assigns.current_user,
      Timetracker.get_session!(socket.assigns.current_session.id)
    )

    case Timetracker.end_session(socket.assigns.current_session.id) do
      {:ok, _session} ->
        {:noreply,
         socket
         |> assign_sessions()}

      {:error, _changeset} ->
        {:noreply, socket}
    end
  end

  def handle_event("delete_session", %{"id" => id}, socket) do
    Bodyguard.permit!(
      Timetracker,
      :delete_session,
      socket.assigns.current_user,
      Timetracker.get_session!(id)
    )

    case Timetracker.delete_session(id) do
      {:ok, _session} ->
        {:noreply,
         socket
         |> assign_sessions()}

      {:error, _changeset} ->
        LiveToast.send_toast(:error, "Nie udało się usunąć sesji")
        {:noreply, socket}
    end
  end

  def handle_event("edit_session", %{"session_form" => params}, socket) do
    session_id = params["id"]

    Bodyguard.permit!(
      Timetracker,
      :update_session,
      socket.assigns.current_user,
      Timetracker.get_session!(session_id)
    )

    params =
      params
      |> Map.update("start_datetime", nil, &string_to_datetime/1)
      |> Map.update("end_datetime", nil, &string_to_datetime/1)

    case Timetracker.update_session(session_id, params) do
      {:ok, _session} ->
        {:noreply,
         socket
         |> assign_sessions()
         |> push_event("js-exec", %{
           to: "#edit-session-modal-#{session_id}",
           attr: "phx-remove"
         })}

      {:error, _changeset} ->
        LiveToast.send_toast(:error, "Nie udało się zaktualizować sesji")
        {:noreply, socket}
    end
  end

  def format_day_header(day_string) do
    date = Date.from_iso8601!(day_string)

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

  def format_time(nil) do
    "trwa"
  end

  def format_time("") do
    nil
  end

  def format_time(%DateTime{} = datetime) do
    datetime
    |> DateTime.shift_zone!("Europe/Warsaw")
    |> Calendar.strftime("%H:%M")
  end

  def format_time(%Time{} = time) do
    time |> Calendar.strftime("%H:%M")
  end

  def format_duration(duration, :with_seconds) when is_integer(duration) do
    hours = div(duration, 60 * 60)
    minutes = rem(div(duration, 60), 60)
    seconds = rem(duration, 60)
    :io_lib.format("~2..0B:~2..0B:~2..0B", [hours, minutes, seconds])
  end

  def format_duration(duration) when is_integer(duration) do
    hours = div(duration, 3600)
    minutes = rem(div(duration, 60), 60)

    :io_lib.format("~2..0B:~2..0B", [hours, minutes])
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
    start_of_month = Date.beginning_of_month(now) |> DateTime.new!(~T[00:00:00], "Europe/Warsaw")
    end_of_month = Date.end_of_month(now) |> DateTime.new!(~T[23:59:59], "Europe/Warsaw")

    total_seconds =
      Timetracker.list_user_sessions(user_id)
      |> Enum.filter(fn session ->
        session_end = session.end_datetime || DateTime.now!("Europe/Warsaw")

        DateTime.compare(session.start_datetime, start_of_month) in [:eq, :gt] &&
          DateTime.compare(session_end, end_of_month) in [:eq, :lt]
      end)
      |> calculate_total_duration()

    hours = div(total_seconds, 60 * 60)
    minutes = rem(div(total_seconds, 60), 60)
    percentage = round(total_seconds / (160 * 3600) * 100)

    current_month =
      now
      |> Calendar.strftime("%B",
        month_names: fn month ->
          case month do
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
        end
      )

    %{
      hours: hours,
      minutes: minutes,
      percentage: percentage,
      month: current_month
    }
  end
end
