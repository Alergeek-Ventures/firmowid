defmodule FirmowidWeb.HoursRecord.Components.UploadForm do
  @moduledoc false
  use FirmowidWeb, :live_component

  import FirmowidWeb.DesignSystem.Components.Button
  import FirmowidWeb.DesignSystem.Components.CoreComponents, except: [button: 1]
  import FirmowidWeb.DesignSystem.Components.Link
  import Phoenix.Component, except: [link: 1]

  alias Firmowid.Ash.Timetracker
  alias Firmowid.Ash.Timetracker.HoursRecord, as: AshHoursRecord
  alias FirmowidWeb.Infrastructure.Utilities.ElectronicSignature

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
          <.link
            id={"hours-record-download-#{Date.to_iso8601(@selected_date)}"}
            kind="button"
            redirect={~p"/czasosledz/ewidencja/#{@selected_date |> Date.to_iso8601()}/pdf"}
            download
            phx-click="download"
            phx-target={@myself}
            phx-hook="DownloadPdf"
            data-download-url={~p"/czasosledz/ewidencja/#{@selected_date |> Date.to_iso8601()}/pdf"}
            data-download-success-event="download"
            data-download-target={@myself}
            class="ml-auto w-full max-w-32"
          >
            <span data-download-idle>Pobierz</span>
            <span data-download-loading class="hidden items-center gap-2">
              <Lucideicons.loader_circle class="size-4 animate-spin" /> Pobieranie…
            </span>
          </.link>
        <% :sign -> %>
          <div class="flex items-center justify-between">
            <.link
              kind="unstyled"
              external={ElectronicSignature.trusted_profile_url()}
              target="_blank"
              class="hover:underline"
            >
              Podpisz ewidencję<.icon
                name="hero-arrow-top-right-on-square"
                class="text-orangeText mb-1 ml-1 size-6"
              />
            </.link>
            <.button
              type="button"
              phx-click="sign"
              phx-target={@myself}
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
            <.file_upload
              upload={@uploads.hours_record}
              prompt="Dodaj podpisaną ewidencję godzin"
              content_class="flex"
              prompt_class="font-medium"
              error_formatter={&error_to_string/1}
            />
            <.button disabled={value == :upload} class="w-full max-w-32">
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

  def handle_event("pdf-download-error", _params, socket) do
    LiveToast.send_toast(:error, "Nie udało się pobrać ewidencji godzin.")
    {:noreply, socket}
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
