defmodule FirmowidWeb.HoursRecord.Components.UploadForm do
  @moduledoc "Guides downloading, signing and submitting a monthly hours record."
  use FirmowidWeb, :live_component

  import FirmowidUI.Components.Button
  import FirmowidUI.Components.Link
  import FirmowidWeb.DesignSystem.Components.CoreComponents
  import Phoenix.Component, except: [link: 1]

  alias Firmowid.Timetracker
  alias Firmowid.Timetracker.HoursRecord
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
          <div class="absolute h-0.5 w-full -translate-y-1/2 bg-grey-200" />
          <div
            class="absolute h-0.5 w-full origin-left -translate-y-1/2 bg-rust-700 transition"
            style={"transform: scaleX(#{stage_order(@state) / 3})"}
          />
        </div>

        <div class="relative flex w-full justify-between">
          <div class="w-[60px] space-y-1">
            <.render_dot stage={:download} state={@state} />
            <p class="text-center">{gettext("Download")}</p>
          </div>
          <div class="w-[60px] space-y-1">
            <.render_dot stage={:sign} state={@state} />
            <p class="text-center">{gettext("Sign")}</p>
          </div>
          <div class="w-[60px] space-y-1">
            <.render_dot stage={:upload} state={@state} />
            <p class="text-center">{gettext("Upload")}</p>
          </div>
          <div class="w-[60px] space-y-1">
            <.render_dot stage={:send} state={@state} />
            <p class="text-center">{gettext("Send")}</p>
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
            <span data-download-idle>{gettext("Download")}</span>
            <span data-download-loading class="hidden items-center gap-2">
              <Lucideicons.loader_circle class="size-4 animate-spin" /> {gettext("Downloading…")}
            </span>
          </.link>
        <% :sign -> %>
          <div class="flex items-center justify-between">
            <.button
              id="hours-record-sign"
              type="button"
              variant="outline"
              phx-click={show_modal("hours-record-sign-warning")}
            >
              {gettext("Sign timesheet")}
            </.button>
            <.button
              type="button"
              phx-click="sign"
              phx-target={@myself}
              variant="outline"
              class="w-full max-w-32 text-center"
            >
              {gettext("Signed!")}
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
              prompt={gettext("Add the signed timesheet")}
              content_class="flex"
              prompt_class="font-medium"
              error_formatter={&error_to_string/1}
            />
            <.button disabled={value == :upload} class="w-full max-w-32">
              {gettext("Send")}
            </.button>
          </form>
      <% end %>
      <.modal id="hours-record-sign-warning">
        <div class="flex flex-col gap-6">
          <h2 id="hours-record-sign-warning-title" class="font-bold">
            {gettext("Check your hours before signing")}
          </h2>
          <p id="hours-record-sign-warning-description">
            {gettext(
              "Check the month, hours and your details in the downloaded document. Submitting the signed record will lock editing of this month's hours. Later changes require a correction or cancellation request to your organization administrators."
            )}
          </p>
          <div class="flex flex-wrap justify-end gap-3">
            <.button
              type="button"
              variant="outline"
              phx-click={hide_modal("hours-record-sign-warning")}
            >
              {gettext("Go back and check")}
            </.button>
            <.link
              id="hours-record-confirm-sign"
              kind="button"
              external={ElectronicSignature.trusted_profile_url()}
              target="_blank"
              rel="noopener noreferrer"
              phx-click={hide_modal("hours-record-sign-warning")}
            >
              {gettext("Continue to signing")}
            </.link>
          </div>
        </div>
      </.modal>
    </div>
    """
  end

  @impl true
  def handle_event("download", _params, socket) do
    {:noreply, assign(socket, :state, :sign)}
  end

  def handle_event("pdf-download-error", _params, socket) do
    LiveToast.send_toast(:error, gettext("Could not download the timesheet."))
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
        HoursRecord.create(
          %{
            member_id: socket.assigns.current_user.member.id,
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
          LiveToast.send_toast(:error, gettext("An error occurred while saving the file."))
          {:ok, {:error, error}}

        {:ok, hours_record} ->
          LiveToast.send_toast(:info, gettext("The file has been saved."))
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
        stage_order(@state) > stage_order(@stage) -> "bg-rust-700"
        stage_order(@state) == stage_order(@stage) -> "border-2 border-rust-700 bg-rust-200"
        stage_order(@state) < stage_order(@stage) -> "bg-grey-200"
      end
    ]} />
    """
  end

  def error_to_string(:too_large), do: gettext("Image too large")
  def error_to_string(:too_many_files), do: gettext("Too many files")
  def error_to_string(:not_accepted), do: gettext("Unacceptable file type")
end
