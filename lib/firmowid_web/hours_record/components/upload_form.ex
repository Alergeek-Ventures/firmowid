defmodule FirmowidWeb.HoursRecord.Components.UploadForm do
  @moduledoc """
  Guides downloading, signing and submitting a monthly hours record: the steps of
  the "Dokument ewidencji" card from download to sending the signed file.
  """
  use FirmowidWeb, :live_component

  import FirmowidUI.Components.Button
  import FirmowidUI.Components.Link
  import FirmowidWeb.DesignSystem.Components.CoreComponents
  import FirmowidWeb.HoursRecord.Components.Document
  import FirmowidWeb.Infrastructure.Hooks.RequireOrganization, only: [attach_access_hook: 2]
  import Phoenix.Component, except: [link: 1]

  alias Firmowid.Timetracker
  alias Firmowid.Timetracker.HoursRecord
  alias FirmowidWeb.HoursRecord.Controllers.Record
  alias FirmowidWeb.Infrastructure.Utilities.ElectronicSignature

  @impl true
  def mount(socket) do
    socket =
      socket
      |> attach_access_hook(:ash_scope)
      |> assign(step: 1, file_error?: false, touched?: false)
      |> assign_split(:sign, gettext("Sign it with %{link}", link: "__LINK__"))
      |> assign_split(:drop, gettext("Drag a file or %{link}", link: "__LINK__"))
      |> allow_upload(:hours_record,
        max_entries: 1,
        max_file_size: 10_000_000,
        accept: ~w(.pdf .jpg .jpeg .png),
        auto_upload: true
      )

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    entry = List.first(assigns.uploads.hours_record.entries)
    ready? = entry != nil and entry.done?

    assigns =
      assign(assigns,
        entry: entry,
        ready?: ready?,
        states: %{
          1 => step_state(1, assigns.step, ready?),
          2 => step_state(2, assigns.step, ready?),
          3 => step_state(3, assigns.step, ready?)
        }
      )

    ~H"""
    <div class="flex w-full flex-col gap-5">
      <ol class="flex flex-col gap-4">
        <li class="flex gap-3">
          <.step_marker number={1} state={@states[1]} />
          <div class="flex min-w-0 flex-1 flex-col items-start gap-2">
            <p class={[
              "text-sm/6 font-medium transition-colors duration-300 ease-out motion-reduce:transition-none",
              @states[1] == :done && "text-grey-500",
              @states[1] != :done && "text-grey-900"
            ]}>
              {gettext("Download the timesheet")}
            </p>
            <.link
              id={"hours-record-download-#{Date.to_iso8601(@selected_date)}"}
              kind="button"
              variant="outline"
              size="small"
              redirect={~p"/czasosledz/ewidencja/#{Date.to_iso8601(@selected_date)}/pdf"}
              download
              phx-click="download"
              phx-target={@myself}
              phx-hook="DownloadPdf"
              data-download-url={~p"/czasosledz/ewidencja/#{Date.to_iso8601(@selected_date)}/pdf"}
              data-download-success-event="download"
              data-download-target={@myself}
              class="max-w-full"
            >
              <span data-download-idle class="flex min-w-0 items-center gap-1.5">
                <.cloud_download_icon />
                <span class="truncate">{Record.pdf_filename(@selected_date)}</span>
              </span>
              <span data-download-loading class="hidden items-center gap-1.5">
                <Lucideicons.loader_circle class="size-4 animate-spin" /> {gettext("Downloading…")}
              </span>
            </.link>
          </div>
        </li>
        <li class="flex gap-3">
          <.step_marker number={2} state={@states[2]} />
          <p class={[
            "min-w-0 flex-1 text-sm/6 font-medium transition-colors duration-300 ease-out motion-reduce:transition-none",
            @states[2] == :done && "text-grey-500",
            @states[2] != :done && "text-grey-900"
          ]}>
            {@sign_before}<.button
              id="hours-record-sign"
              type="button"
              variant="unstyled"
              class="cursor-pointer text-grey-900 underline decoration-from-font hover:text-grey-700"
              phx-click={show_modal("hours-record-sign-warning")}
            >{pgettext("hours record signing link", "Trusted Profile")}</.button>{@sign_after}
          </p>
        </li>
        <li class="flex flex-col gap-3">
          <div class="flex items-center gap-3">
            <.step_marker number={3} state={@states[3]} />
            <p class={[
              "text-sm/6 font-medium transition-colors duration-300 ease-out motion-reduce:transition-none",
              @states[3] == :done && "text-grey-500",
              @states[3] != :done && "text-grey-900"
            ]}>
              {gettext("Upload the signed file")}
            </p>
          </div>
          <form id="upload-form" phx-change="upload" phx-submit="send" phx-target={@myself}>
            <.live_file_input upload={@uploads.hours_record} class="sr-only" />
            <%= if @entry do %>
              <.uploaded_file entry={@entry} ready?={@ready?} target={@myself} />
            <% else %>
              <.dropzone
                upload={@uploads.hours_record}
                error?={@file_error?}
                animate={@touched?}
                drop_before={@drop_before}
                drop_after={@drop_after}
              />
            <% end %>
          </form>
          <div
            :if={@file_error?}
            role="alert"
            class="flex gap-3 rounded-sm bg-brick-200 px-4 py-3 text-sm text-brick-700 transition-[opacity,translate] duration-200 ease-out motion-reduce:transition-none starting:-translate-y-1 starting:opacity-0"
          >
            <Lucideicons.circle_alert class="size-5 shrink-0" aria-hidden="true" />
            <div class="flex min-w-0 flex-1 flex-col gap-1">
              <p class="leading-5 font-medium">{gettext("Could not upload the file")}</p>
              <p class="leading-[21px]">{gettext("upload a PDF, JPG or PNG up to 10 MB.")}</p>
            </div>
          </div>
        </li>
      </ol>
      <.button
        type="submit"
        form="upload-form"
        variant="special"
        disabled={!@ready?}
        class="w-full"
      >
        {gettext("Send")}
      </.button>
      <.modal id="hours-record-sign-warning">
        <:header>
          <h2 id="hours-record-sign-warning-title" class="mb-6 font-bold">
            {gettext("Check your hours before signing")}
          </h2>
          <p id="hours-record-sign-warning-description">
            {gettext(
              "Check the month, hours and your details in the downloaded document. Submitting the signed record will lock editing of this month's hours. Later changes require a correction or cancellation request to your organization administrators."
            )}
          </p>
        </:header>
        <div class="flex flex-col gap-6">
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
              phx-click={
                "hours-record-sign-warning"
                |> hide_modal()
                |> JS.push("sign", target: @myself)
              }
            >
              {gettext("Continue to signing")}
            </.link>
          </div>
        </div>
      </.modal>
    </div>
    """
  end

  attr :upload, :any, required: true
  attr :error?, :boolean, required: true
  attr :animate, :boolean, required: true, doc: "rises in when it comes back after a file"
  attr :drop_before, :string, required: true
  attr :drop_after, :string, required: true

  # Figma "Dropzone": empty, "over" while a file is dragged above it (LiveView
  # sets `phx-drop-target-active`), and "error" after a rejected file.
  defp dropzone(assigns) do
    ~H"""
    <label
      for={@upload.ref}
      phx-drop-target={@upload.ref}
      class={[
        "group/drop flex w-full cursor-pointer flex-col items-center gap-1 rounded-sm border-dashed bg-grey-50 px-4 py-6 text-center transition-[background-color,opacity,translate] duration-200 ease-out hover:bg-grey-100 motion-reduce:transition-none [&.phx-drop-target-active]:border [&.phx-drop-target-active]:border-grey-700 [&.phx-drop-target-active]:bg-grey-100",
        @error? && "border border-brick-500",
        @animate && "starting:translate-y-2 starting:opacity-0"
      ]}
    >
      <.cloud_upload_icon class={[
        "size-5 group-[.phx-drop-target-active]/drop:text-grey-700",
        @error? && "text-brick-700",
        !@error? && "text-grey-700"
      ]} />
      <p class="text-sm/5 text-grey-700 group-[.phx-drop-target-active]/drop:hidden">
        {@drop_before}<span class={[
          "font-medium",
          !@error? && "text-grey-900 underline decoration-from-font"
        ]}>{gettext("choose from your computer")}</span>{@drop_after}
      </p>
      <p class="hidden text-sm/5 font-medium text-grey-900 group-[.phx-drop-target-active]/drop:block">
        {gettext("Drop the file to upload it")}
      </p>
      <p class="text-xs/[17px] font-medium text-grey-500">
        {gettext("PDF, JPG or PNG · up to 10 MB")}
      </p>
    </label>
    """
  end

  attr :entry, :any, required: true
  attr :ready?, :boolean, required: true
  attr :target, :any, required: true

  # Figma "Plik / uploading": the progress while the file uploads, then its size
  # once it is ready to send.
  defp uploaded_file(assigns) do
    ~H"""
    <div class="flex h-[115px] w-full items-center gap-4 rounded-sm border border-grey-200 bg-grey-50 px-6 py-3 transition-[opacity,translate] duration-200 ease-out motion-reduce:transition-none starting:translate-y-2 starting:opacity-0">
      <div class={["flex min-w-0 flex-1 flex-col", if(@ready?, do: "gap-1", else: "gap-2")]}>
        <div class="flex items-start gap-2">
          <Lucideicons.circle_check_big
            :if={@ready?}
            class="size-5 shrink-0 text-moss-700 transition-[opacity,scale] duration-200 ease-out motion-reduce:transition-none starting:scale-50 starting:opacity-0"
            aria-hidden="true"
          />
          <.file_icon :if={!@ready?} />
          <p class="min-w-0 truncate text-sm/5 font-medium text-grey-900">
            {@entry.client_name}
          </p>
        </div>
        <p
          :if={@ready?}
          class="ps-6 text-xs/[17px] font-medium text-grey-500 transition-opacity duration-200 ease-out motion-reduce:transition-none starting:opacity-0"
        >
          {gettext("%{size} · ready to send", size: file_size(@entry.client_size))}
        </p>
        <div :if={!@ready?} class="flex flex-col gap-1">
          <p class="text-xs/[17px] font-medium text-grey-500">
            {gettext("Uploading… %{progress}%", progress: @entry.progress)}
          </p>
          <div class="h-1 w-full overflow-hidden rounded-sm bg-grey-200">
            <div
              class="h-1 rounded-sm bg-grey-700 transition-[width] duration-200 ease-out motion-reduce:transition-none"
              style={"width: #{@entry.progress}%"}
            >
            </div>
          </div>
        </div>
      </div>
      <.button
        type="button"
        variant="unstyled"
        class="shrink-0 cursor-pointer text-grey-700 hover:text-grey-900"
        phx-click="cancel-upload"
        phx-value-ref={@entry.ref}
        phx-target={@target}
        aria-label={gettext("Remove the file")}
      >
        <Lucideicons.x class="size-4" aria-hidden="true" />
      </.button>
    </div>
    """
  end

  @impl true
  def handle_event("download", _params, socket) do
    {:noreply, assign(socket, step: max(socket.assigns.step, 2), touched?: true)}
  end

  def handle_event("pdf-download-error", _params, socket) do
    LiveToast.send_toast(:error, gettext("Could not download the timesheet."))
    {:noreply, socket}
  end

  def handle_event("sign", _params, socket) do
    {:noreply, assign(socket, step: 3, touched?: true)}
  end

  # A rejected file is removed at once, so the next one can be chosen; the card
  # keeps the error until then.
  def handle_event("upload", _params, socket) do
    upload = socket.assigns.uploads.hours_record
    rejected = Enum.reject(upload.entries, &(upload_errors(upload, &1) == []))

    socket =
      Enum.reduce(rejected, socket, &cancel_upload(&2, :hours_record, &1.ref))

    {:noreply,
     assign(socket,
       step: 3,
       touched?: true,
       file_error?: rejected != [] or upload_errors(upload) != []
     )}
  end

  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, socket |> assign(:touched?, true) |> cancel_upload(:hours_record, ref)}
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

  # A sentence with a link inside is translated whole; the link text is cut out of it.
  defp assign_split(socket, key, sentence) do
    [before, rest] = String.split(sentence, "__LINK__", parts: 2)
    assign(socket, [{:"#{key}_before", before}, {:"#{key}_after", rest}])
  end

  # Steps before the current one are done; the last one is done once its file is ready.
  defp step_state(3, _step, true), do: :done
  defp step_state(number, step, _ready?) when number < step, do: :done
  defp step_state(number, number, _ready?), do: :current
  defp step_state(_number, _step, _ready?), do: :todo

  defp file_size(bytes) when bytes < 1_000_000 do
    gettext("%{size} kB", size: max(div(bytes, 1000), 1))
  end

  defp file_size(bytes) do
    gettext("%{size} MB",
      size: Firmowid.Cldr.Number.to_string!(bytes / 1_000_000, format: "0.0")
    )
  end
end
