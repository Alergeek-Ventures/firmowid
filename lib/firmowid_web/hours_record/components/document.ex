defmodule FirmowidWeb.HoursRecord.Components.Document do
  @moduledoc """
  Parts of the "Dokument ewidencji" card (Figma "Ewidencja · dokument"): the
  month still in progress, the sent record, the step markers and the icons the
  card draws.
  """
  use FirmowidWeb, :html

  import FirmowidUI.Components.Button
  import FirmowidUI.Components.Link
  import Phoenix.Component, except: [link: 1]

  alias Phoenix.LiveView.Rendered

  @timezone "Europe/Warsaw"

  @doc "The month is not over yet: the record can be previewed, not signed."
  @spec in_progress(map()) :: Rendered.t()
  attr :selected_date, Date, required: true

  def in_progress(assigns) do
    ~H"""
    <p class="text-sm/[21px] text-grey-600">
      {gettext(
        "Download and sign the timesheet after the current month ends. Until then the hours may still change."
      )}
    </p>
    <.link
      id={"hours-record-download-#{Date.to_iso8601(@selected_date)}"}
      kind="button"
      variant="outline"
      redirect={~p"/czasosledz/ewidencja/#{Date.to_iso8601(@selected_date)}/pdf"}
      download
      phx-hook="DownloadPdf"
      data-download-url={~p"/czasosledz/ewidencja/#{Date.to_iso8601(@selected_date)}/pdf"}
      class="w-full"
    >
      <span data-download-idle class="flex items-center gap-1.5">
        <.cloud_download_icon class="size-5" stroke_width="2.4" /> {gettext("Download")}
      </span>
      <span data-download-loading class="hidden items-center gap-1.5">
        <Lucideicons.loader_circle class="size-5 animate-spin" /> {gettext("Downloading…")}
      </span>
    </.link>
    """
  end

  @doc """
  The signed record that was sent, with its file and a way to change it. While a
  change request waits for the administrators, the card says so and offers to
  take the request back.
  """
  @spec sent(map()) :: Rendered.t()
  attr :record, :any, required: true, doc: "the hours record with its blob loaded"
  attr :animate, :boolean, default: false, doc: "rises in, right after the record was sent"

  def sent(assigns) do
    record = assigns.record
    pending? = record.change_requested_at != nil and is_nil(record.change_request_decision)

    assigns =
      assign(assigns,
        pending?: pending?,
        sent_at: DateTime.shift_zone!(record.inserted_at, @timezone),
        requested_at:
          record.change_requested_at &&
            DateTime.shift_zone!(record.change_requested_at, @timezone)
      )

    ~H"""
    <div class={[
      "flex w-full flex-col gap-3",
      @animate &&
        "transition-[opacity,translate] duration-200 ease-out motion-reduce:transition-none starting:translate-y-2 starting:opacity-0"
    ]}>
      <p class="text-sm/[21px] text-grey-600">
        <%= if @pending? do %>
          {pending_description(@record.change_request_kind,
            date: format_date(@requested_at, "d MMMM"),
            time: Calendar.strftime(@requested_at, "%-H:%M")
          )}
        <% else %>
          {gettext("Sent on %{date} at %{time}.",
            date: format_date(@sent_at, "d MMMM"),
            time: Calendar.strftime(@sent_at, "%-H:%M")
          )}
        <% end %>
      </p>
      <div class="flex items-center gap-3 rounded-sm border border-grey-200 bg-grey-50 p-3">
        <.file_icon />
        <div class="flex min-w-0 flex-1 flex-col gap-1 font-medium">
          <p class="truncate text-sm/5 text-grey-900">{@record.blob.original_filename}</p>
          <p class="text-xs/[17px] text-grey-500">
            {gettext("sent %{date}", date: Calendar.strftime(@sent_at, "%-d.%-m"))}
          </p>
        </div>
        <.link
          redirect={~p"/czasosledz/ewidencja/#{@record.id}"}
          kind="unstyled"
          class="shrink-0 text-grey-700 hover:text-grey-900"
          aria-label={gettext("Download the sent file")}
        >
          <.cloud_download_icon class="size-4" />
        </.link>
      </div>
    </div>
    <.button
      :if={@pending?}
      id="hours-record-withdraw-change"
      type="button"
      variant="unstyled"
      class="flex cursor-pointer items-center gap-1 self-end text-sm/[18px] font-medium text-grey-700 hover:text-grey-900"
      phx-click="withdraw-change-request"
      phx-disable-with={gettext("Saving...")}
    >
      {withdraw_label(@record.change_request_kind)} <.arrow_back_icon />
    </.button>
    <.button
      :if={is_nil(@record.change_requested_at)}
      id="hours-record-request-change"
      type="button"
      variant="unstyled"
      class="flex cursor-pointer items-center gap-1 self-end text-sm/[18px] font-medium text-grey-700 hover:text-grey-900"
      phx-click={show_modal("hours-record-change-request")}
    >
      {gettext("Withdraw and upload another file")} <.arrow_back_icon />
    </.button>
    """
  end

  @doc "Badge text of a change request waiting for the administrators."
  @spec pending_label(atom()) :: String.t()
  def pending_label(:cancellation), do: pgettext("hours record badge", "Cancellation")
  def pending_label(:correction), do: pgettext("hours record badge", "Correction")

  defp pending_description(:cancellation, bindings) do
    gettext(
      "Cancellation request sent on %{date} at %{time}. Until the decision the timesheet stays sent. Once accepted, you will return to the “Download” step.",
      bindings
    )
  end

  defp pending_description(:correction, bindings) do
    gettext(
      "Correction request sent on %{date} at %{time}. Until the decision the timesheet stays sent. Once accepted, you will return to the “Download” step.",
      bindings
    )
  end

  defp withdraw_label(:cancellation), do: gettext("Take back the cancellation request")
  defp withdraw_label(:correction), do: gettext("Take back the correction request")

  @doc """
  Number of a step in the card: done (green tick), current (black) or still
  ahead (grey).
  """
  @spec step_marker(map()) :: Rendered.t()
  attr :number, :integer, required: true
  attr :state, :atom, values: [:done, :current, :todo], required: true

  def step_marker(assigns) do
    ~H"""
    <span class={[
      "flex size-6 shrink-0 items-center justify-center rounded-full text-xs/none font-semibold transition-colors duration-300 ease-out motion-reduce:transition-none",
      @state == :done && "bg-moss-200 text-moss-700",
      @state == :current && "bg-black text-white",
      @state == :todo && "bg-grey-200 text-grey-700"
    ]}>
      <%!-- Figma "Ikona / check": a tick narrower than Lucide's. --%>
      <svg
        :if={@state == :done}
        class="size-4 transition-[opacity,scale] duration-200 ease-out motion-reduce:transition-none starting:scale-50 starting:opacity-0"
        viewBox="0 0 16 16"
        fill="none"
        stroke="currentColor"
        stroke-width="1.33"
        stroke-linecap="round"
        stroke-linejoin="round"
        aria-hidden="true"
      >
        <path d="M3 8.5L7 12.5L13 3.5" />
      </svg>
      <span :if={@state == :done} class="sr-only">{gettext("Done")}</span>
      <span :if={@state != :done}>{@number}</span>
    </span>
    """
  end

  # Tabler icons as drawn in Figma: Lucide has no cloud with the arrow at its
  # corner, and its file and undo arrow are shaped differently.

  @doc "Tabler cloud with a download arrow at its corner."
  @spec cloud_download_icon(map()) :: Rendered.t()
  attr :class, :any, default: "size-4"
  attr :stroke_width, :string, default: "2"

  def cloud_download_icon(assigns) do
    ~H"""
    <svg
      class={["shrink-0", @class]}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width={@stroke_width}
      stroke-linecap="round"
      stroke-linejoin="round"
      aria-hidden="true"
    >
      <path d="M12 18.004h-5.343c-2.572 -.004 -4.657 -2.011 -4.657 -4.487c0 -2.475 2.085 -4.482 4.657 -4.482c.393 -1.762 1.794 -3.2 3.675 -3.773c1.88 -.572 3.956 -.193 5.444 1c1.488 1.19 2.162 3.007 1.77 4.769h.99c1.38 0 2.57 .811 3.128 1.986" />
      <path d="M19 16v6" />
      <path d="M22 19l-3 3l-3 -3" />
    </svg>
    """
  end

  @doc "Tabler cloud with an upload arrow at its corner."
  @spec cloud_upload_icon(map()) :: Rendered.t()
  attr :class, :any, default: "size-5"

  def cloud_upload_icon(assigns) do
    ~H"""
    <svg
      class={["shrink-0", @class]}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="2"
      stroke-linecap="round"
      stroke-linejoin="round"
      aria-hidden="true"
    >
      <path d="M12 18.004h-5.343c-2.572 -.004 -4.657 -2.011 -4.657 -4.487c0 -2.475 2.085 -4.482 4.657 -4.482c.393 -1.762 1.794 -3.2 3.675 -3.773c1.88 -.572 3.956 -.193 5.444 1c1.488 1.19 2.162 3.007 1.77 4.769h.99c1.38 0 2.57 .811 3.128 1.986" />
      <path d="M19 22v-6" />
      <path d="M22 19l-3 -3l-3 3" />
    </svg>
    """
  end

  @doc "Tabler file, 20 px in graphite."
  @spec file_icon(map()) :: Rendered.t()
  def file_icon(assigns) do
    ~H"""
    <svg
      class="size-5 shrink-0 text-grey-700"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="2"
      stroke-linecap="round"
      stroke-linejoin="round"
      aria-hidden="true"
    >
      <path d="M14 3v4a1 1 0 0 0 1 1h4" />
      <path d="M17 21h-10a2 2 0 0 1 -2 -2v-14a2 2 0 0 1 2 -2h7l5 5v11a2 2 0 0 1 -2 2z" />
    </svg>
    """
  end

  defp arrow_back_icon(assigns) do
    ~H"""
    <svg
      class="size-4 shrink-0"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="2"
      stroke-linecap="round"
      stroke-linejoin="round"
      aria-hidden="true"
    >
      <path d="M9 14l-4 -4l4 -4" />
      <path d="M5 10h11a4 4 0 1 1 0 8h-1" />
    </svg>
    """
  end

  defp format_date(datetime, format) do
    Cldr.DateTime.to_string!(datetime, Firmowid.Cldr, format: format)
  end
end
