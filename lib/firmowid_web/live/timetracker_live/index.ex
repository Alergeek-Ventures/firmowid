defmodule FirmowidWeb.TimetrackerLive.Index do
  alias Firmowid.Timetracker.Session
  alias Firmowid.Timetracker
  use FirmowidWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:projects, Timetracker.list_user_projects(socket.assigns.current_user.id))
     |> assign(:sessions, Timetracker.list_user_sessions(socket.assigns.current_user.id))
     |> assign(:current_session, Timetracker.get_current_session(socket.assigns.current_user.id))
     |> assign(
       :form,
       to_form(
         Session.changeset(%Session{}, %{
           start_time: DateTime.now!("Europe/Warsaw") |> Calendar.strftime("%H:%M"),
           user_id: socket.assigns.current_user.id
         })
       )
     )
     |> assign(:is_form_extended, false)}
  end

  def handle_event("toggle_extended_form", _, socket) do
    {:noreply, socket |> update(:is_form_extended, &(!&1))}
  end

  def handle_event("validate", %{"session" => session} = params, socket) do
    {:noreply,
     socket
     |> assign(
       :form,
       to_form(Session.changeset(%Session{}, session))
     )}
  end

  def handle_event("save", %{"session" => session}, socket) do
    case Timetracker.start_session(
           session
           |> Map.put("user_id", socket.assigns.current_user.id)
           |> Map.put("start_time", DateTime.utc_now())
         ) do
      {:ok, _} ->
        {:noreply, socket |> assign(:form, to_form(Session.changeset(%Session{title: ""})))}

      {:error, changeset} ->
        dbg(changeset)
        {:noreply, socket |> assign(:form, to_form(changeset))}
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
    "teraz"
  end

  def format_time(datetime) do
    datetime
    |> DateTime.shift_zone!("Europe/Warsaw")
    |> Calendar.strftime("%H:%M")
  end

  def format_duration(duration) when is_integer(duration) do
    hours = div(duration, 60)
    minutes = rem(duration, 60)
    :io_lib.format("~2..0B:~2..0B", [hours, minutes])
  end

  def calculate_session_duration(session) do
    end_time =
      case session.end_time do
        nil -> DateTime.now!("Europe/Warsaw")
        end_time -> end_time |> DateTime.shift_zone!("Europe/Warsaw")
      end

    start_time = session.start_time |> DateTime.shift_zone!("Europe/Warsaw")

    DateTime.diff(end_time, start_time, :minute)
  end

  def calculate_total_duration(sessions) do
    Enum.reduce(sessions, 0, fn session, acc ->
      acc +
        calculate_session_duration(session)
    end)
  end

  attr :title, :string, required: true
  attr :start_time, :string, required: true
  attr :end_time, :string, required: true
  attr :duration, :string, required: true

  def render_row(assigns) do
    ~H"""
    <div class="flex items-center justify-between px-4 py-3 hover:bg-gray-50">
      <div>{@title}</div>
      <div class="flex items-center space-x-4">
        <div>{@start_time} - {@end_time}</div>
        <div class="font-bold">{@duration}</div>
        <div class="flex space-x-2">
          <button>
            <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z"
              />
            </svg>
          </button>
          <button>
            <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"
              />
            </svg>
          </button>
        </div>
      </div>
    </div>
    """
  end
end
