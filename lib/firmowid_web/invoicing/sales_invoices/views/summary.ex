defmodule FirmowidWeb.Invoicing.SalesInvoices.Views.Summary do
  @moduledoc """
  LiveView for displaying the summary page after a sales invoice has been created.

  This page shows the invoice details and KSeF submission status, allowing users to:
  - View the created invoice
  - Monitor KSeF submission progress
  - Navigate to edit the invoice or create a new one
  """
  use FirmowidWeb, :live_view

  import FirmowidUI.Components.Link
  import Phoenix.Component, except: [link: 1]

  alias Firmowid.Invoicing
  alias Firmowid.Invoicing.SalesInvoice
  alias Firmowid.Ksef
  alias Firmowid.Ksef.SubmissionInfo
  alias FirmowidWeb.Invoicing.Utilities.Navigation

  @invoice_loads [
    :net_value,
    :vat_value,
    :gross_value,
    :amount,
    sales_invoice_items: [:net_value, :vat_value, :gross_value],
    corrections: [:amount, sales_invoice_items: [:net_value, :vat_value, :gross_value]],
    corrected_invoice: :corrections,
    latest_correction: [:amount, sales_invoice_items: [:net_value, :vat_value, :gross_value]]
  ]

  @impl true
  def mount(%{"id" => id} = params, _session, socket) do
    current_user = socket.assigns.current_user

    scope = socket.assigns.ash_scope
    return_to = Navigation.return_to_path(params["powrot_do"])

    invoice = load_invoice!(id, scope)

    logo_url = Invoicing.get_logo_url(invoice.organization_id, scope: scope)

    submission_info = Ksef.get_submission_info(invoice)

    # Subscribe to KSeF status updates if submission is in progress
    if SubmissionInfo.submitting?(submission_info) do
      Ksef.subscribe_ksef_status(current_user.member.organization_id)
    end

    currency_rate = Invoicing.get_currency_rate(invoice)

    {previous_invoices, invoice} = get_previous_invoices(invoice, scope)

    socket =
      socket
      |> assign(:invoice, invoice)
      |> assign(:logo_url, logo_url)
      |> assign(:previous_invoices, previous_invoices)
      |> assign(:submission_info, submission_info)
      |> assign(:currency_rate, currency_rate)
      |> assign(:return_to, return_to)
      |> assign(:page_title, gettext("Sales invoice"))

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto my-4 flex w-full max-w-6xl flex-col gap-4">
      <p class="text-sm text-grey-600">
        {gettext("Invoice wizard")} | <span class="text-grey-700">{gettext("Invoice issued")}</span>
      </p>
      <%= cond do %>
        <% SubmissionInfo.submitting?(@submission_info) -> %>
          <h1 class="flex items-baseline gap-1 text-2xl/tight font-medium">
            {gettext("Invoice is being sent")}
            <span class="inline-flex gap-1">
              <span class="size-1.5 animate-bounce rounded-full bg-grey-400 [animation-delay:-0.3s]"></span>
              <span class="size-1.5 animate-bounce rounded-full bg-grey-400 [animation-delay:-0.15s]"></span>
              <span class="size-1.5 animate-bounce rounded-full bg-grey-400"></span>
            </span>
          </h1>
        <% SubmissionInfo.submitted?(@submission_info) -> %>
          <h1 class="text-2xl/tight font-medium">{gettext("Invoice sent to KSeF")}</h1>
        <% SubmissionInfo.failed?(@submission_info) -> %>
          <h1 class="text-2xl/tight font-medium text-brick-600">
            {gettext("Sending to KSeF failed")}
          </h1>
        <% true -> %>
          <h1 class="text-2xl/tight font-medium">{gettext("Invoice issued")}</h1>
      <% end %>

      <div class="flex items-center justify-between">
        <div class="flex items-center gap-4">
          <%= if SubmissionInfo.editing_blocked?(@invoice, @submission_info) or
                  SubmissionInfo.outside_ksef?(@invoice, @submission_info) do %>
            <span
              id="edit-invoice-button-tooltip"
              phx-hook="Tippy"
              data-tippy-content={SubmissionInfo.edit_unavailable_reason(@invoice, @submission_info)}
              data-tippy-delay="100"
              class="inline-flex"
              tabindex="0"
            >
              <FirmowidUI.Components.Button.button
                id="edit-invoice-button"
                type="button"
                variant="secondary"
                size="small"
                disabled
                aria-describedby="edit-invoice-button-description"
              >
                <Lucideicons.pencil /> {gettext("Edit")}
              </FirmowidUI.Components.Button.button>
            </span>
            <span id="edit-invoice-button-description" class="sr-only">
              {SubmissionInfo.edit_unavailable_reason(@invoice, @submission_info)}
            </span>
          <% else %>
            <.link
              navigate={Navigation.sales_invoice_edit_path(@invoice, @return_to)}
              kind="button"
              variant="secondary"
              size="small"
            >
              <Lucideicons.pencil /> {gettext("Edit")}
            </.link>
          <% end %>
          <.link
            kind="button"
            variant="secondary"
            size="small"
            redirect={Navigation.sales_invoice_pdf_download_path(@invoice, true)}
            download
          >
            <Lucideicons.download /> {gettext("Download")}
          </.link>
        </div>

        <div class="flex items-center gap-4">
          <.link
            kind="unstyled"
            navigate={Navigation.sales_invoice_show_path(@invoice, @return_to)}
            class="text-sm text-grey-600 hover:text-grey-900"
          >
            {gettext("Go to the invoice")}
          </.link>
          <.link
            navigate={Navigation.sales_invoice_creator_path()}
            kind="button"
            variant="primary"
            accent="teal"
          >
            {gettext("Issue another")}
          </.link>
        </div>
      </div>
      <%= if SubmissionInfo.failed?(@submission_info) do %>
        <div class="flex flex-col items-center justify-center gap-4 rounded-md bg-brick-200 p-8 text-center text-brick-700">
          <Lucideicons.triangle_alert class="size-10 text-brick-600" />
          <h2 class="text-xl">{gettext("Sending to KSeF failed.")}</h2>
          <p :if={@submission_info.error} class="max-w-lg text-sm">
            {@submission_info.error}
          </p>
          <p id="returned-to-draft-notice" class="mt-2 text-sm text-grey-600">
            {gettext(
              "The invoice returned to a draft without a number. Correct the details and issue it again."
            )}
          </p>
          <.link
            navigate={Navigation.sales_invoice_edit_path(@invoice, @return_to)}
            kind="button"
            variant="primary"
            accent="teal"
            class="mt-4"
          >
            <Lucideicons.pencil class="size-4" /> {gettext("Correct and issue again")}
          </.link>
        </div>
      <% end %>

      <div class="invisible h-8" />

      <div class="grid grid-cols-[1fr_650px_1fr] items-start justify-center gap-8">
        <% list_width = 224 %>
        <% template_width = 595 %>
        <% template_height = 842 %>
        <% scale = list_width / template_width %>

        <div class="space-y-6" style={"width: #{list_width}px;"}>
          <div
            :for={previous_invoice <- @previous_invoices}
            class="space-y-2"
          >
            <p class="pl-1 text-sm/tight text-grey-700">
              {previous_invoice.invoice_number}
            </p>
            <div
              class="overflow-hidden rounded-lg border border-grey-200 bg-white shadow-sm"
              style={"width: #{template_width * scale}px; height: #{template_height * scale}px;"}
            >
              <div class="origin-top-left" style={"transform: scale(#{scale})"}>
                <FirmowidUI.Invoicing.Components.SalesInvoice.sales_invoice
                  sales_invoice={previous_invoice}
                  currency_rate={@currency_rate}
                  show_vat={@current_org.is_vat_payer}
                  reference_invoice={previous_invoice.reference_invoice}
                  logo_url={@logo_url}
                />
              </div>
            </div>
          </div>
        </div>

        <div class="relative">
          <%!-- Success state - behind invoice (z-0) --%>
          <div
            :if={SubmissionInfo.submitted?(@submission_info)}
            class="absolute inset-0 z-0 flex items-center justify-center"
          >
            <div class="text-center">
              <Lucideicons.circle_check class="mx-auto size-24 text-moss-700" />
              <p class="mt-4 text-xl font-medium text-grey-700">
                {gettext("Sent to KSeF!")}
              </p>
            </div>
          </div>

          <%!-- Invoice preview - above success (z-10) --%>
          <div
            id="invoice-preview"
            phx-hook="PaperPlane"
            class="relative z-10"
          >
            <div class="w-full max-w-[650px] overflow-hidden rounded-lg border border-grey-200 bg-white shadow-sm">
              <FirmowidUI.Invoicing.Components.SalesInvoice.sales_invoice
                sales_invoice={@invoice}
                currency_rate={@currency_rate}
                show_vat={@current_org.is_vat_payer}
                reference_invoice={@invoice.reference_invoice}
                logo_url={@logo_url}
              />
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def handle_info({:ksef_invoice_status, %{invoice_id: invoice_id, status: :failed}}, socket)
      when socket.assigns.invoice.id != invoice_id do
    {:noreply, socket}
  end

  def handle_info({:ksef_invoice_status, %{invoice_id: invoice_id, status: :failed}}, socket) do
    # The worker may have already deleted a failed unsent correction.
    # If the invoice is gone, redirect back to the original invoice edit page.
    # Existence check is intentionally sparse; reload with @invoice_loads before UI work.
    case SalesInvoice.by_id(invoice_id, scope: socket.assigns.ash_scope) do
      {:ok, _invoice} ->
        invoice = load_invoice!(invoice_id, socket.assigns.ash_scope)
        handle_existing_invoice_status(socket, invoice, invoice_id, :failed)

      {:error, _} ->
        # Correction was deleted by the worker — redirect to original invoice
        corrected_invoice_id = socket.assigns.invoice.corrected_invoice_id

        {:noreply,
         socket
         |> put_flash(:error, Ksef.failed_correction_deleted_message())
         |> push_navigate(to: Navigation.sales_invoice_edit_path(corrected_invoice_id, socket.assigns.return_to))}
    end
  end

  def handle_info({:ksef_invoice_status, %{invoice_id: invoice_id, status: _status}}, socket)
      when socket.assigns.invoice.id != invoice_id do
    {:noreply, socket}
  end

  def handle_info({:ksef_invoice_status, %{invoice_id: invoice_id, status: status}}, socket) do
    invoice = load_invoice!(invoice_id, socket.assigns.ash_scope)

    handle_existing_invoice_status(socket, invoice, invoice_id, status)
  end

  defp handle_existing_invoice_status(socket, invoice, _invoice_id, status) do
    submission_info = Ksef.get_submission_info(invoice)

    {previous_invoices, invoice} = get_previous_invoices(invoice, socket.assigns.ash_scope)

    invoice = ensure_template_ready_invoice(invoice, socket.assigns.ash_scope)

    previous_invoices =
      Enum.map(previous_invoices, &ensure_template_ready_invoice(&1, socket.assigns.ash_scope))

    socket =
      socket
      |> assign(:submission_info, submission_info)
      |> assign(:invoice, invoice)
      |> assign(:previous_invoices, previous_invoices)

    socket =
      if status == :submitted do
        push_event(socket, "paper-plane-fly", %{})
      else
        socket
      end

    {:noreply, socket}
  end

  defp get_previous_invoices(%{ksef_invoice_kind: :kor} = invoice, scope) do
    alias Firmowid.Invoicing.Calculations.AnnotatedCorrections

    # Re-fetch corrected invoice to ensure all attributes are loaded,
    # then annotate corrections directly (avoids Ash.load! re-fetch issue).
    # Use the FK attribute — :corrected_invoice may be NotLoaded on sparse reloads.
    original_invoice =
      invoice.corrected_invoice_id
      |> SalesInvoice.by_id!(
        scope: scope,
        load: [
          :net_value,
          :vat_value,
          :gross_value,
          :amount,
          sales_invoice_items: [:net_value, :vat_value, :gross_value],
          corrections: [
            :net_value,
            :vat_value,
            :gross_value,
            :amount,
            sales_invoice_items: [:net_value, :vat_value, :gross_value]
          ]
        ]
      )
      |> then(fn inv -> %{inv | corrections: AnnotatedCorrections.annotate(inv)} end)

    previous_invoices =
      original_invoice.corrections
      |> Enum.filter(&DateTime.before?(safe_timestamp(&1), safe_timestamp(invoice)))
      |> List.insert_at(0, original_invoice)
      |> Enum.reverse()

    invoice =
      case Enum.find(original_invoice.corrections, &(&1.id == invoice.id)) do
        nil ->
          raise "Correction invoice not found"

        # preserve preloaded fields
        found_invoice ->
          %{
            invoice
            | reference_invoice: Map.get(found_invoice, :reference_invoice),
              corrected_invoice: Map.get(found_invoice, :corrected_invoice)
          }
      end

    {previous_invoices, invoice}
  end

  defp get_previous_invoices(%{ksef_invoice_kind: :vat} = invoice, _scope), do: {[], invoice}

  defp load_invoice!(id, scope) do
    id
    |> SalesInvoice.by_id!(load: @invoice_loads, scope: scope)
    |> Ash.load!(@invoice_loads, scope: scope)
  end

  defp ensure_template_ready_invoice(invoice, scope) do
    Ash.load!(
      invoice,
      [
        :net_value,
        :vat_value,
        :gross_value,
        :amount,
        sales_invoice_items: [:net_value, :vat_value, :gross_value]
      ],
      scope: scope
    )
  end

  defp safe_timestamp(record) do
    case record do
      %{locked_at: %DateTime{} = ts} -> ts
      %{inserted_at: %DateTime{} = ts} -> ts
      _ -> ~U[1970-01-01 00:00:00Z]
    end
  end
end
