defmodule FirmowidWeb.Invoicing.SalesInvoices.Components.InvoiceReview do
  @moduledoc "Shared final review of invoice numbering, notes and delivery options."
  use FirmowidWeb, :html

  import FirmowidUI.Components.Button

  attr :invoice, :map, required: true
  attr :preview_invoice, :map, required: true
  attr :invoice_number, :string, required: true
  attr :invoice_warnings, :list, required: true
  attr :invoice_number_errors, :list, default: []
  attr :series_suggestions, :map, required: true
  attr :organization, :map, required: true
  attr :currency_rate, :any, required: true
  attr :logo_url, :any, required: true
  attr :counterparty_check, :map, required: true
  attr :should_send_emails, :boolean, required: true
  attr :ksef_connected?, :boolean, required: true
  slot :back, required: true
  slot :header, required: true

  @doc "Renders the final review shared by the creator and saved invoice drafts."
  @spec invoice_review(map()) :: Phoenix.LiveView.Rendered.t()
  def invoice_review(assigns) do
    ~H"""
    <div id="invoice-review" class="relative mx-auto my-4 flex w-full max-w-6xl flex-1 flex-col">
      {render_slot(@back)}
      <div class="px-9">
        {render_slot(@header)}
        <div class="mbs-8 flex gap-6">
          <div class="max-w-[650px] flex-1">
            <div class="overflow-clip rounded-lg border border-grey-200 bg-white shadow-sm">
              <FirmowidUI.Invoicing.Components.SalesInvoice.sales_invoice
                sales_invoice={@preview_invoice}
                currency_rate={@currency_rate}
                show_vat={@organization.is_vat_payer}
                logo_url={@logo_url}
              />
            </div>
          </div>

          <div class="space-y-6">
            <h2 class="mbe-4 text-lg font-medium text-grey-700">Dane faktury</h2>
            <FirmowidUI.Invoicing.Components.InvoiceNumber.invoice_number
              invoice_number={@invoice_number}
              next_numbers_by_series={@series_suggestions}
              warnings={@invoice_warnings}
              errors={@invoice_number_errors}
              submit_event={if @ksef_connected?, do: "send_to_ksef", else: "update_invoice_number"}
            />

            <form id="invoice-notes-form" phx-change="update_notes">
              <label for="invoice-note" class="mbe-2 block text-sm text-grey-500">Notatka na fakturze</label>
              <textarea
                id="invoice-note"
                name="invoice_note"
                rows="3"
                class="w-full resize-none rounded-lg border border-grey-200 px-3 py-2 text-sm text-grey-700 placeholder:text-grey-400 focus:border-transparent focus:ring-2 focus:ring-turquoise-500"
                placeholder="Widoczna na fakturze i w KSeF (stopka faktury)"
              >{@invoice.invoice_note || ""}</textarea>

              <label for="internal-note" class="mbs-3 mbe-2 block text-sm text-grey-500">Komentarz</label>
              <textarea
                id="internal-note"
                name="internal_note"
                rows="3"
                class="w-full resize-none rounded-lg border border-grey-200 px-3 py-2 text-sm text-grey-700 placeholder:text-grey-400 focus:border-transparent focus:ring-2 focus:ring-turquoise-500"
                placeholder="Notatka wewnętrzna (niewidoczna na fakturze - tylko w Firmowidzie)"
              >{@invoice.internal_note || ""}</textarea>
            </form>

            <form id="invoice-email-form" phx-change="toggle_should_send_emails">
              <label
                class="flex items-center gap-3 text-sm font-medium text-grey-700"
                title={@counterparty_check.tooltip}
              >
                <input
                  type="checkbox"
                  name="should_send_emails"
                  value="true"
                  checked={@should_send_emails}
                  disabled={!@counterparty_check.valid}
                  class="size-4 rounded border-grey-300 text-turquoise-600 focus:ring-turquoise-500 disabled:cursor-not-allowed disabled:opacity-60"
                />
                <span>Wyślij fakturę e-mailem do kontrahenta po otrzymaniu numeru KSeF</span>
              </label>
            </form>

            <div class="flex flex-row gap-4 pbs-4">
              <.button
                type="button"
                phx-click="save_as_draft"
                phx-disable-with="Zapisywanie..."
                class="h-11 w-full"
                variant="secondary"
              >
                Zapisz wersję roboczą
              </.button>
              <.button
                id="confirm-invoice-button"
                type="button"
                phx-click="send_to_ksef"
                phx-disable-with="Wysyłanie..."
                class="h-11 w-full"
                disabled={not @ksef_connected? or String.trim(@invoice_number) == ""}
                variant="primary"
                accent="turquoise"
              >
                Zapisz i wyślij do KSeF
              </.button>
            </div>
            <p
              :if={not @ksef_connected?}
              id="ksef-required-notice"
              role="status"
              class="text-sm text-grey-500"
            >
              Wystawienie faktury wymaga połączenia z KSeF. Możesz zapisać ją jako wersję roboczą.
            </p>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
