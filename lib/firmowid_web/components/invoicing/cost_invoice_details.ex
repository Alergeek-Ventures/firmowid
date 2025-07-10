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

      <div class="flex flex-col justify-between px-8 gap-4 lg:gap-12 lg:flex-row">
        <aside class="min-w-[320px] lg:w-[600px] flex flex-col gap-4 order-last lg:order-none py-8">
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
          <%= case {@invoice.skip_invoicing, @invoice.transactions} do %>
            <% {true, _} -> %>
              <InvoiceDetails.invoice_skipped_view />
            <% {false, []} -> %>
              <%= if @potential_transactions == [] do %>
                <div class="flex flex-col gap-6 items-center text-center">
                  <div class="gap-4 flex flex-col items-center border border-greyButtonBg p-4 rounded-md">
                    <.icon name="hero-face-frown" class="w-10 h-10 block" />
                    <h3 class="text-lg font-semibold">Brak rekomendacji</h3>
                    <p class="max-w-[400px]">
                      Firmowid nie znalazł żadnych transakcji, które potencjalnie pasowałyby do tej faktury.
                    </p>
                  </div>
                </div>
                <h3 class="text-lg font-semibold my-10">Co możesz zrobić?</h3>
                <div class="text-darkGrey flex flex-col gap-8">
                  <div class="flex flex-row justify-between gap-16">
                    <p>
                      Możesz wykonać przelew teraz - kliknij przycisk, aby skopiować potrzebne dane.
                    </p>
                    <.live_component
                      id="bank-transfer-modal"
                      module={FirmowidWeb.Components.Invoicing.BankTransferModal}
                      invoice={@invoice}
                    />
                  </div>
                  <div class="flex flex-row justify-between gap-16">
                    <p>
                      A może żadna nie pasuje, bo zapłacono gotówką, lub na inne konto?
                      Pomiń jej szukanie. Firmowid oznaczy ją jako rozliczoną poza systemem.
                    </p>
                    <div class="flex shrink-0 flex-row gap-2 w-32 overflow-hidden">
                      <div class="text-xs h-6 flex flex-row justify-center items-center py-2 px-2 rounded-md transition-all duration-500 w-10 text-darkGrey bg-greyButtonBg">
                        <.icon name="hero-document-text-solid" class="h-4 w-4" />
                      </div>
                      <button
                        phx-click="toggle-invoicing"
                        class="transition-all duration-500 cursor-pointer w-20 h-6 uppercase text-xs text-darkGrey bg-greyButtonBg rounded-md"
                      >
                        Pomiń
                      </button>
                    </div>
                  </div>
                </div>
              <% else %>
                <div class="flex flex-col gap-16">
                  <div class="flex flex-col gap-5">
                    <div class="flex flex-row justify-between items-center">
                      <h2 class="text-lg font-semibold">Potencjalne transakcje dla dokumentu</h2>
                    </div>
                    <div class="grid grid-cols-[1fr_120px_120px_220px]">
                      <span class="text-xs uppercase text-darkGrey text-left">Informacje</span>
                      <span class="text-xs uppercase text-darkGrey text-right">Data</span>
                      <span class="text-xs uppercase text-darkGrey text-right">Kwota</span>
                    </div>
                    <%= for {tx, score} <- @potential_transactions do %>
                      <div
                        id={"potential-transaction-#{tx.id}"}
                        class="grid grid-cols-[1fr_120px_120px_220px]"
                      >
                        <div class="text-left">
                          <p class="font-semibold">{tx.creditor_name}</p>
                          <p class="text-sm text-darkGrey">
                            {tx.remittance_information_unstructured}
                          </p>
                        </div>
                        <div class="flex items-center justify-end">{tx.booking_date}</div>
                        <div class="text-right flex items-center justify-end">
                          {Money.new(tx.transaction_currency, tx.transaction_amount)}
                        </div>
                        <div class="flex items-center justify-end gap-4">
                          <InvoiceDetails.prediction_score_indicator
                            transaction_id={tx.id}
                            prediction_score={score}
                          />
                          <button
                            phx-click="connect"
                            phx-value-transaction_id={tx.id}
                            class="uppercase text-sm bg-darkGrey text-white h-7 px-2 rounded"
                          >
                            Zatwierdź
                          </button>
                        </div>
                      </div>
                    <% end %>
                  </div>
                  <InvoiceDetails.skip_invoicing />
                </div>
              <% end %>
            <% {false, [single]} -> %>
              <InvoiceDetails.single_transaction_match is_cost_invoice={true} transaction={single} />
            <% {false, multiple} -> %>
              <InvoiceDetails.multiple_transactions_match
                is_cost_invoice={true}
                transactions={multiple}
              />
          <% end %>
        </main>
      </div>
    </div>
    """
  end
end
