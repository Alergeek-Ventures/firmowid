defmodule FirmowidWeb.Components.Session do
  alias Firmowid.Timetracker.Session
  use FirmowidWeb, :live_component

  attr :sessions, :list, required: true
  attr :projects, :list, required: true

  def render(assigns) do
    ~H"""
    <div class="odd:bg-greyButtonBg flex rounded-[5px] py-1 px-2 gap-12 w-full min-w-0">
      <div class="flex gap-2 justify-between items-center flex-1 min-w-0 max-h-max">
        <% session = hd(@sessions) %>
        <p class="truncate">{session.title}</p>
        <p class="text-sm text-darkGrey uppercase">
          {case Enum.find(@projects, &(&1.id == session.project_id)) do
            nil -> "Brak projektu"
            project -> project.name
          end}
        </p>
      </div>

      <div class="space-y-2 min-w-max">
        <div :for={session <- @sessions} class="flex items-center justify-end hover:bg-gray-50">
          <div class="flex items-center gap-12">
            <p class="line-clamp-1 w-[100px] text-right">
              {format_time(session.start_datetime)} - {format_time(session.end_datetime)}
            </p>
            <p class="font-bold w-12 text-right">
              {format_duration(Session.calculate_session_duration(session))}
            </p>
            <div class="flex gap-2">
              <button
                id={"edit-session-#{session.id}"}
                phx-click={show_modal("edit-session-modal-#{session.id}")}
              >
                <.edit_icon class="text-darkGrey" />
              </button>
              <button
                id={"delete-session-#{session.id}"}
                phx-click={show_modal("delete-session-modal-#{session.id}")}
              >
                <.icon name="hero-trash" class="text-darkGrey" />
              </button>
            </div>
          </div>
          <.modal
            id={"edit-session-modal-#{session.id}"}
            on_cancel={hide_modal("edit-session-modal-#{session.id}")}
          >
            <.form
              :let={edit_form}
              as={:session_form}
              id={"edit-session-form-#{session.id}"}
              for={Session.changeset(session)}
              phx-submit="edit_session"
              class="space-y-4"
            >
              <input type="hidden" name="session_form[id]" value={session.id} />
              <.input
                type="select"
                label="Projekt"
                field={edit_form[:project_id]}
                options={
                  @projects
                  |> Enum.map(fn project ->
                    {project.name, project.id}
                  end)
                }
              />
              <.input label="Tytuł" field={edit_form[:title]} placeholder="Nad czym pracowałeś?" />
              <div class="flex gap-2">
                <div class="w-full">
                  <.input
                    type="datetime-local"
                    label="Czas rozpoczęcia"
                    field={edit_form[:start_datetime]}
                    value={format_datetime(session.start_datetime)}
                  />
                </div>
                <div class="w-full">
                  <.input
                    type="datetime-local"
                    label="Czas zakończenia"
                    field={edit_form[:end_datetime]}
                    value={format_datetime(session.end_datetime)}
                  />
                </div>
              </div>
              <div class="mt-6 flex justify-end gap-3">
                <.button
                  type="button"
                  variant="outline"
                  color="black"
                  phx-click={hide_modal("edit-session-modal-#{session.id}")}
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
            id={"delete-session-modal-#{session.id}"}
            on_cancel={hide_modal("delete-session-modal-#{session.id}")}
          >
            <p>
              Czy na pewno chcesz usunąć sesję "<span class="font-semibold">{session.title}</span>"?
            </p>
            <div class="mt-6 flex justify-end gap-3">
              <.button
                variant="outline"
                color="black"
                phx-click={hide_modal("delete-session-modal-#{session.id}")}
              >
                Anuluj
              </.button>
              <.button
                id={"confirm-delete-session-#{session.id}"}
                color="red"
                phx-click={JS.push("delete_session", value: %{id: session.id})}
                phx-disable-with="Usuwanie..."
              >
                Usuń
              </.button>
            </div>
          </.modal>
        </div>
      </div>
    </div>
    """
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

  defp format_datetime(nil), do: nil

  defp format_datetime(datetime) do
    datetime
    |> DateTime.shift_zone!("Europe/Warsaw")
    |> DateTime.to_iso8601()
    |> String.slice(0, 16)
  end
end
