defmodule FirmowidWeb.Components.Session do
  @moduledoc false
  use FirmowidWeb, :live_component

  alias Firmowid.Timetracker.Session
  alias FirmowidWeb.Helpers.TimeFormatter

  attr :sessions, :list, required: true
  attr :projects, :list, required: true

  def render(assigns) do
    ~H"""
    <div class="odd:bg-greyButtonBg/50 flex rounded-md py-1 px-2 gap-12 w-full min-w-0 relative">
      <div class="flex gap-12 justify-between items-center flex-1 min-w-0 max-h-max">
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
        <div
          :for={session <- @sessions}
          class="flex items-center justify-end hover:bg-gray-50 gap-12 group"
        >
          <p class="w-[100px] text-right">
            {format_time(session.start_datetime)} - {format_time(session.end_datetime)}
          </p>
          <p
            class="font-bold w-12 text-right"
            id={"session-timer-#{session.id}"}
            phx-hook="Timer"
            data-start_time={session.start_datetime}
            data-format="short"
            data-disabled={session.end_datetime != nil}
          >
            {session |> Session.calculate_session_duration() |> TimeFormatter.format_timer()}
          </p>
          <div
            :if={not session.lockdown}
            class="pl-2 opacity-0 group-hover:opacity-100 transition absolute left-full"
          >
            <div class="flex gap-3 bg-greyButtonBg rounded-md py-1 px-2">
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
                <.render_trash_icon class="text-darkGrey" />
              </button>
            </div>
          </div>
          <div :if={not session.lockdown} class="absolute">
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
                  options={@projects |> Enum.map(&{&1.name, &1.id})}
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
                  phx-click={
                    JS.exec("data-cancel", to: "#delete-session-modal-#{session.id}")
                    |> JS.push("delete_session", value: %{id: session.id})
                  }
                  phx-disable-with="Usuwanie..."
                >
                  Usuń
                </.button>
              </div>
            </.modal>
          </div>
        </div>
      </div>
    </div>
    """
  end

  def render_trash_icon(assigns) do
    ~H"""
    <svg
      width="24"
      height="24"
      viewBox="0 0 24 24"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
      class={@class}
    >
      <path
        fill-rule="evenodd"
        clip-rule="evenodd"
        d="M14.5333 1.77734C14.9997 1.77745 15.4543 1.90963 15.8326 2.15515C16.2109 2.40067 16.4937 2.74709 16.6411 3.14534L17.2444 4.77734H20.8889C21.1836 4.77734 21.4662 4.8827 21.6746 5.07024C21.8829 5.25777 22 5.51213 22 5.77734C22 6.04256 21.8829 6.29691 21.6746 6.48445C21.4662 6.67199 21.1836 6.77734 20.8889 6.77734L20.8856 6.84834L19.9222 18.9913C19.8621 19.748 19.4858 20.456 18.8689 20.9729C18.2521 21.4898 17.4406 21.7773 16.5978 21.7773H7.40222C6.5594 21.7773 5.7479 21.4898 5.13107 20.9729C4.51425 20.456 4.1379 19.748 4.07778 18.9913L3.11444 6.84734L3.11111 6.77734C2.81643 6.77734 2.53381 6.67199 2.32544 6.48445C2.11706 6.29691 2 6.04256 2 5.77734C2 5.51213 2.11706 5.25777 2.32544 5.07024C2.53381 4.8827 2.81643 4.77734 3.11111 4.77734H6.75556L7.35889 3.14534C7.50633 2.74693 7.78937 2.4004 8.16789 2.15486C8.5464 1.90932 9.00119 1.77724 9.46778 1.77734H14.5333ZM8.66667 9.77734C8.39452 9.77738 8.13185 9.8673 7.92848 10.0301C7.7251 10.1928 7.59517 10.4171 7.56333 10.6603L7.55556 10.7773V16.7773C7.55587 17.0322 7.66431 17.2774 7.85872 17.4627C8.05313 17.648 8.31884 17.7596 8.60155 17.7745C8.88426 17.7895 9.16264 17.7067 9.37981 17.5431C9.59698 17.3795 9.73655 17.1474 9.77 16.8943L9.77778 16.7773V10.7773C9.77778 10.5121 9.66071 10.2578 9.45234 10.0702C9.24397 9.8827 8.96135 9.77734 8.66667 9.77734ZM15.3333 9.77734C15.0386 9.77734 14.756 9.8827 14.5477 10.0702C14.3393 10.2578 14.2222 10.5121 14.2222 10.7773V16.7773C14.2222 17.0426 14.3393 17.2969 14.5477 17.4845C14.756 17.672 15.0386 17.7773 15.3333 17.7773C15.628 17.7773 15.9106 17.672 16.119 17.4845C16.3274 17.2969 16.4444 17.0426 16.4444 16.7773V10.7773C16.4444 10.5121 16.3274 10.2578 16.119 10.0702C15.9106 9.8827 15.628 9.77734 15.3333 9.77734ZM14.5333 3.77734H9.46667L9.09667 4.77734H14.9033L14.5333 3.77734Z"
        fill="#4E4E4E"
      />
    </svg>
    """
  end

  def format_time(nil), do: "trwa"

  def format_time(%DateTime{} = datetime) do
    Calendar.strftime(datetime, "%H:%M")
  end

  defp format_datetime(nil), do: nil

  defp format_datetime(datetime) do
    datetime
    |> DateTime.to_iso8601()
    |> String.slice(0, 16)
  end
end
