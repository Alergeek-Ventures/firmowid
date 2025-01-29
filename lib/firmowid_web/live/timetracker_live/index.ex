defmodule FirmowidWeb.TimetrackerLive.Index do
  alias Firmowid.Timetracker.Session
  alias Firmowid.Timetracker
  use FirmowidWeb, :live_view

  def mount(_params, _session, socket) do
    if connected?(socket), do: :timer.send_interval(20000, self(), :tick)

    {:ok,
     socket
     |> assign(:projects, Timetracker.list_user_projects(socket.assigns.current_user.id))
     |> assign_sessions()
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

  def assign_sessions(socket) do
    socket
    |> assign(:sessions, Timetracker.list_user_sessions(socket.assigns.current_user.id))
    |> assign(:current_session, Timetracker.get_current_session(socket.assigns.current_user.id))
  end

  def handle_info(:tick, socket) do
    {:noreply, socket |> assign_sessions()}
  end

  def handle_event("toggle_extended_form", _, socket) do
    {:noreply, socket |> update(:is_form_extended, &(!&1))}
  end

  def handle_event("validate", %{"session" => session}, socket) do
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
        {:noreply,
         socket
         |> assign(:form, to_form(Session.changeset(%Session{title: ""})))
         |> assign_sessions()}

      {:error, changeset} ->
        dbg(changeset)
        {:noreply, socket |> assign(:form, to_form(changeset))}
    end
  end

  def handle_event("pause_session", _, socket) do
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
    case Timetracker.delete_session(id) do
      {:ok, _session} ->
        {:noreply,
         socket
         |> assign_sessions()}

      {:error, _changeset} ->
        {:noreply,
         socket
         |> put_flash(:error, "Nie udało się usunąć sesji")}
    end
  end

  def handle_event("edit_session", %{"session" => params}, socket) do
    session_id = params["id"]

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
        {:noreply,
         socket
         |> put_flash(:error, "Nie udało się zaktualizować sesji")}
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

  attr :session, :map, required: true
  attr :projects, :list, required: true

  def render_row(assigns) do
    ~H"""
    <div>
      <div class="flex items-center justify-between px-4 py-3 hover:bg-gray-50">
        <div>{@session.title}</div>
        <div class="flex items-center space-x-4">
          <div>{format_time(@session.start_time)} - {format_time(@session.end_time)}</div>
          <div class="font-bold">{format_duration(calculate_session_duration(@session))}</div>
          <div class="flex space-x-2">
            <button phx-click={show_modal("edit-session-modal-#{@session.id}")}>
              <.edit_icon class="text-darkGrey" />
            </button>
            <button phx-click={show_modal("delete-session-modal-#{@session.id}")}>
              <.icon name="hero-trash" class="text-darkGrey" />
            </button>
          </div>
        </div>
      </div>

      <.modal
        id={"edit-session-modal-#{@session.id}"}
        on_cancel={hide_modal("edit-session-modal-#{@session.id}")}
      >
        <.form
          for={Session.changeset(%Session{id: @session.id, title: @session.title})}
          phx-submit="edit_session"
          class="space-y-4"
        >
          <input type="hidden" name="session[id]" value={@session.id} />
          <.input
            type="select"
            label="Projekt"
            name="session[project_id]"
            value={@session.project_id}
            options={
              @projects
              |> Enum.map(fn project ->
                {project.name, project.id}
              end)
            }
          />
          <.input
            label="Tytuł"
            value={@session.title}
            name="session[title]"
            placeholder="Nad czym pracowałeś?"
          />
          <div class="flex gap-2">
            <div class="w-full">
              <.input
                type="datetime-local"
                label="Czas rozpoczęcia"
                value={format_datetime(@session.start_time)}
                name="session[start_time]"
              />
            </div>
            <div class="w-full">
              <.input
                type="datetime-local"
                label="Czas zakończenia"
                value={format_datetime(@session.end_time)}
                name="session[end_time]"
              />
            </div>
          </div>
          <div class="mt-6 flex justify-end gap-3">
            <.button
              type="button"
              variant="outline"
              color="black"
              phx-click={hide_modal("edit-session-modal-#{@session.id}")}
            >
              Anuluj
            </.button>
            <.button color="orange" phx-disable-with="Zapisywanie...">
              Zapisz
            </.button>
          </div>
        </.form>
      </.modal>

      <.modal
        id={"delete-session-modal-#{@session.id}"}
        on_cancel={hide_modal("delete-session-modal-#{@session.id}")}
      >
        <p>Czy na pewno chcesz usunąć sesję "<span class="font-semibold">{@session.title}</span>"?</p>
        <div class="mt-6 flex justify-end gap-3">
          <.button
            variant="outline"
            color="black"
            phx-click={hide_modal("delete-session-modal-#{@session.id}")}
          >
            Anuluj
          </.button>
          <.button
            color="red"
            phx-click={JS.push("delete_session", value: %{id: @session.id})}
            phx-disable-with="Usuwanie..."
          >
            Usuń
          </.button>
        </div>
      </.modal>
    </div>
    """
  end

  # Add this helper function for datetime formatting
  defp format_datetime(nil), do: nil

  defp format_datetime(datetime) do
    datetime
    |> DateTime.shift_zone!("Europe/Warsaw")
    |> DateTime.to_iso8601()
    |> String.slice(0, 16)
  end
end
