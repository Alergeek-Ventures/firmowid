defmodule FirmowidWeb.HoursRecord.Components.UploadForm do
  @moduledoc false
  use FirmowidWeb, :live_component

  import FirmowidWeb.DesignSystem.Components.Link
  import Phoenix.Component, except: [link: 1]

  alias Firmowid.Ash.Timetracker
  alias Firmowid.Ash.Timetracker.HoursRecord, as: AshHoursRecord

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
    <div class="flex w-full flex-col gap-6">
      <div class="relative w-full">
        <div class="absolute inset-x-[20px] top-3">
          <div class="bg-greyButtonBg absolute h-0.5 w-full -translate-y-1/2" />
          <div
            class="bg-orangeText absolute h-0.5 w-full origin-left -translate-y-1/2 transition"
            style={"transform: scaleX(#{stage_order(@state) / 3})"}
          />
        </div>

        <div class="relative flex w-full justify-between">
          <div class="w-[60px] space-y-1">
            <.render_dot stage={:download} state={@state} />
            <p class="text-center">Pobierz</p>
          </div>
          <div class="w-[60px] space-y-1">
            <.render_dot stage={:sign} state={@state} />
            <p class="text-center">Podpisz</p>
          </div>
          <div class="w-[60px] space-y-1">
            <.render_dot stage={:upload} state={@state} />
            <p class="text-center">Wgraj</p>
          </div>
          <div class="w-[60px] space-y-1">
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
            class={[
              "ml-auto w-full max-w-32 px-6 text-center",
              button_styles(%{color: "orange", variant: "solid"})
            ]}
          >
            Pobierz
          </a>
        <% :sign -> %>
          <div class="flex items-center justify-between">
            <.link
              kind="unstyled"
              external="https://moj.gov.pl/nforms/signer/upload?xFormsAppName=SIGNER"
              target="_blank"
              class="hover:underline"
            >
              Podpisz ewidencję<.icon
                name="hero-arrow-top-right-on-square"
                class="text-orangeText mb-1 ml-1 size-6"
              />
            </.link>
            <.button
              phx-click="sign"
              phx-target={@myself}
              color="orange"
              variant="outline"
              class="w-full max-w-32 text-center"
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
            class="flex flex-col items-end gap-6"
          >
            <label
              class="border-orangeText flex w-full cursor-pointer justify-center rounded-md border-2 border-dashed px-6 py-8"
              phx-drop-target={@uploads.hours_record.ref}
            >
              <div class="text-orangeText flex text-sm">
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
            <.button disabled={value == :upload} color="orange" class="w-full max-w-32">
              Wyślij
            </.button>
          </form>
      <% end %>
    </div>
    """
  end

  @impl true
  def handle_event("download", _params, socket) do
    {:noreply, assign(socket, :state, :sign)}
  end

  def handle_event("sign", _params, socket) do
    {:noreply, assign(socket, :state, :upload)}
  end

  def handle_event("upload", _params, socket) do
    {:noreply, assign(socket, :state, :send)}
  end

  def handle_event("send", _params, socket) do
    scope = socket.assigns.ash_scope

    consume_uploaded_entries(socket, :hours_record, fn %{path: path}, entry ->
      result =
        AshHoursRecord.create(
          %{
            user_id: socket.assigns.current_user.id,
            number_of_hours: Timetracker.seconds_to_hours(socket.assigns.total_duration),
            month: socket.assigns.selected_date.month,
            year: socket.assigns.selected_date.year,
            upload_path: path,
            upload_filename: entry.client_name
          },
          scope: scope
        )

      case result do
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
    <div class={[
      "mx-auto size-6 rounded-full transition",
      cond do
        stage_order(@state) > stage_order(@stage) -> "bg-orangeText"
        stage_order(@state) == stage_order(@stage) -> "bg-orangeBg border-orangeText border-2"
        stage_order(@state) < stage_order(@stage) -> "bg-greyButtonBg"
      end
    ]} />
    """
  end

  def error_to_string(:too_large), do: "Image too large"
  def error_to_string(:too_many_files), do: "Too many files"
  def error_to_string(:not_accepted), do: "Unacceptable file type"
end
