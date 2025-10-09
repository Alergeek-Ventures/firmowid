defmodule FirmowidWeb.HoursRecordLive.UploadForm do
  @moduledoc false
  use FirmowidWeb, :live_component

  alias Firmowid.Helpers.TimeConverter
  alias Firmowid.Timetracker

  @impl true
  def mount(socket) do
    socket =
      socket
      |> assign(:state, :download)
      |> allow_upload(:hours_record,
        max_entries: 1,
        accept: ["application/pdf", "image/*"]
      )

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="w-full gap-6 flex flex-col">
      <div class="relative w-full">
        <div class="inset-x-[20px] absolute top-3">
          <div class="bg-greyButtonBg h-0.5 w-full absolute -translate-y-1/2" />
          <div
            class="bg-orangeText h-0.5 w-full absolute -translate-y-1/2 transition origin-left"
            style={"transform: scaleX(#{stage_order(@state) / 3})"}
          />
        </div>

        <div class="flex w-full justify-between relative">
          <div class="space-y-1 w-[60px]">
            <.render_dot stage={:download} state={@state} />
            <p class="text-center">Pobierz</p>
          </div>
          <div class="space-y-1 w-[60px]">
            <.render_dot stage={:sign} state={@state} />
            <p class="text-center">Podpisz</p>
          </div>
          <div class="space-y-1 w-[60px]">
            <.render_dot stage={:upload} state={@state} />
            <p class="text-center">Wgraj</p>
          </div>
          <div class="space-y-1 w-[60px]">
            <.render_dot stage={:send} state={@state} />
            <p class="text-center">Wyślij</p>
          </div>
        </div>
      </div>
      <%= case @state do %>
        <% :download -> %>
          <a
            href={~p"/czasosledz/ewidencja/#{@selected_date |> Date.to_iso8601()}/pdf"}
            download
            phx-click="download"
            phx-target={@myself}
            class={
              classes([
                button_styles(%{color: "orange", variant: "solid"}),
                "px-6 ml-auto max-w-32 w-full text-center"
              ])
            }
          >
            Pobierz
          </a>
        <% :sign -> %>
          <div class="flex justify-between items-center">
            <a
              href="https://moj.gov.pl/nforms/signer/upload?xFormsAppName=SIGNER"
              target="_blank"
              class="hover:underline"
            >
              Podpisz ewidencję<.icon
                name="hero-arrow-top-right-on-square"
                class="size-6 ml-1 mb-1 text-orangeText"
              />
            </a>
            <.button
              phx-click="sign"
              phx-target={@myself}
              color="orange"
              variant="outline"
              class="max-w-32 w-full text-center"
            >
              Podpisane!
            </.button>
          </div>
        <% value -> %>
          <form
            id="upload-form"
            phx-change="upload"
            phx-submit="send"
            phx-target={@myself}
            class="flex flex-col gap-6 items-end"
          >
            <label
              class="cursor-pointer flex justify-center rounded-md border-2 border-dashed border-orangeText px-6 py-8 w-full"
              phx-drop-target={@uploads.hours_record.ref}
            >
              <div class="flex text-sm text-orangeText">
                <div :if={Enum.empty?(@uploads.hours_record.entries)} class="font-medium">
                  Dodaj podpisaną ewidencję godzin
                </div>
                <.live_file_input upload={@uploads.hours_record} class="sr-only" />
                <div :if={!Enum.empty?(@uploads.hours_record.entries)}>
                  <%= for entry <- @uploads.hours_record.entries do %>
                    <p>{entry.client_name}</p>
                    <%= for err <- upload_errors(@uploads.hours_record, entry) do %>
                      <p>{error_to_string(err)}</p>
                    <% end %>
                  <% end %>
                </div>
              </div>
            </label>
            <.button disabled={value == :upload} color="orange" class="max-w-32 w-full">
              Wyślij
            </.button>
          </form>
      <% end %>
    </div>
    """
  end

  @impl true
  def handle_event("download", _params, socket) do
    Bodyguard.permit!(Timetracker, :read_user_hours_records, socket.assigns.current_user)
    {:noreply, assign(socket, :state, :sign)}
  end

  def handle_event("sign", _params, socket) do
    {:noreply, assign(socket, :state, :upload)}
  end

  def handle_event("upload", _params, socket) do
    {:noreply, assign(socket, :state, :send)}
  end

  def handle_event("send", _params, socket) do
    Bodyguard.permit!(Timetracker, :create_hours_record, socket.assigns.current_user)

    consume_uploaded_entries(socket, :hours_record, fn %{path: path}, entry ->
      %{
        user_id: socket.assigns.current_user.id,
        number_of_hours: TimeConverter.time_worked_in_seconds_to_hours(socket.assigns.total_duration),
        month: socket.assigns.selected_date.month,
        year: socket.assigns.selected_date.year
      }
      |> Timetracker.create_hours_record(
        path,
        entry.client_name
      )
      |> case do
        {:error, error} ->
          LiveToast.send_toast(:error, "Wystąpił błąd podczas zapisywania pliku.")
          {:ok, {:error, error}}

        {:ok, hours_record} ->
          LiveToast.send_toast(:info, "Plik został zapisany.")
          {:ok, {:ok, hours_record}}
      end
    end)

    send(self(), :upload_complete)

    {:noreply, socket}
  end

  defp stage_order(:download), do: 0
  defp stage_order(:sign), do: 1
  defp stage_order(:upload), do: 2
  defp stage_order(:send), do: 3
  defp stage_order(_), do: 0

  attr :stage, :atom, required: true
  attr :state, :atom, required: true

  defp render_dot(assigns) do
    ~H"""
    <div class={
      classes([
        "size-6 rounded-full mx-auto transition",
        cond do
          stage_order(@state) > stage_order(@stage) -> "bg-orangeText"
          stage_order(@state) == stage_order(@stage) -> "border-2 border-orangeText bg-orangeBg"
          stage_order(@state) < stage_order(@stage) -> "bg-greyButtonBg"
        end
      ])
    } />
    """
  end

  def error_to_string(:too_large), do: "Image too large"
  def error_to_string(:too_many_files), do: "Too many files"
  def error_to_string(:not_accepted), do: "Unacceptable file type"
end
