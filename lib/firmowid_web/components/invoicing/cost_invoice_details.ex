defmodule FirmowidWeb.Components.Invoicing.CostInvoiceDetails do
  use FirmowidWeb, :live_component

  alias Firmowid.CostInvoices.CostInvoice
  alias FirmowidWeb.Components.Invoicing.InvoiceDetails, as: InvoiceDetails

  attr :invoice, CostInvoice, required: true
  attr :preview_url, :string, required: true
  attr :preview_type, :atom, required: true
  attr :potential_transactions, :list, default: []

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :is_cost_invoice, true)

    ~H"""
    <div class="flex flex-col">
      <InvoiceDetails.invoice_header
        is_cost_invoice={true}
        issue_date={@invoice.issue_date}
        party_display_name={@invoice.seller_display_name}
        description={@invoice.description}
      />

      <div class="flex flex-col justify-between px-8 gap-4 lg:gap-12 lg:flex-row min-w-0">
        <aside class="w-full lg:w-[400px] xl:w-[600px] flex-shrink-0 flex-grow-0 flex flex-col gap-4 order-last lg:order-none py-8">
          <div class="grid grid-cols-[130px_1fr] gap-2 py-4">
            <InvoiceDetails.invoice_metadata_piece
              label="Numer faktury"
              value={@invoice.invoice_identifier}
              piece_id="invoice-identifier"
            />
            <InvoiceDetails.invoice_metadata_piece
              label="Sprzedawca"
              value={@invoice.seller}
              piece_id="seller"
            />
            <InvoiceDetails.invoice_metadata_piece
              label="Data wystawienia"
              value={@invoice.issue_date}
              piece_id="issue-date"
            />
            <InvoiceDetails.invoice_metadata_piece
              label="Data sprzedaży"
              value={@invoice.sale_date}
              piece_id="sale-date"
            />
            <InvoiceDetails.invoice_metadata_piece
              label="Termin płatności"
              value={@invoice.due_date}
              piece_id="due-date"
            />
          </div>

          <InvoiceDetails.invoice_amount
            is_cost_invoice={true}
            total_amount={Money.new(@invoice.currency, @invoice.total_amount)}
          />

          <h3 class="self-start text-sm uppercase text-darkGrey mt-8">Podgląd faktury</h3>
          <div class="mb-8 mt-4 transition-opacity transition-duration-300 hover:opacity-50">
            <%= case @preview_type do %>
              <% :pdf -> %>
                <a href={@preview_url} target="_blank">
                  <div
                    id="invoice-preview"
                    data-pdf-url={@preview_url}
                    phx-update="ignore"
                    phx-hook="PDFViewer"
                    class="w-full h-full max-h-[80vh] border-black border-2 rounded-lg overflow-x-hidden overflow-y-scroll bg-white"
                  >
                    <div class="min-w-[200px] min-h-[200px] flex items-center justify-center font-bold">
                      Ładowanie dokumentu...
                    </div>
                  </div>
                </a>
              <% :image -> %>
                <a href={@preview_url} target="_blank">
                  <div class="w-full h-full max-h-[80vh] border-black border-2 rounded-lg overflow-x-hidden overflow-y-scroll bg-black">
                    <img src={@preview_url} class="w-full h-full object-contain" />
                  </div>
                </a>
            <% end %>
          </div>
        </aside>

        <main class="flex-grow py-8 lg:pl-8 border-b lg:border-b-0 lg:border-l border-darkGrey/[.3]">
          <%= cond do %>
            <% @invoice.skip_invoicing -> %>
              <InvoiceDetails.invoice_skipped_view />
            <% length(@invoice.transactions) == 1 -> %>
              <InvoiceDetails.single_transaction_match
                is_cost_invoice={true}
                transaction={hd(@invoice.transactions)}
              />
            <% length(@invoice.transactions) > 1 -> %>
              <InvoiceDetails.multiple_transactions_match
                is_cost_invoice={true}
                transactions={@invoice.transactions}
              />
            <% @potential_transactions == [] -> %>
              <div class="flex flex-col gap-6 items-center text-center">
                <div class="gap-4 flex flex-col items-center border border-greyButtonBg p-4 rounded-md">
                  <.icon name="hero-face-frown" class="w-10 h-10 block" />
                  <h3 class="text-lg font-semibold">Brak rekomendacji</h3>
                  <p class="max-w-[400px]">
                    Firmowid nie znalazł żadnych transakcji, które potencjalnie pasowałyby do tej faktury.
                  </p>
                </div>
              </div>
              <InvoiceDetails.skip_invoicing show_bank_transfer_modal={true} invoice={@invoice} />
            <% true -> %>
              <div class="flex flex-col gap-16">
                <InvoiceDetails.potential_transactions_list
                  potential_transactions={@potential_transactions}
                  name_field={:creditor_name}
                />
                <InvoiceDetails.skip_invoicing show_bank_transfer_modal={true} invoice={@invoice} />
              </div>
          <% end %>
        </main>
      </div>
    </div>
    """
  end
end
