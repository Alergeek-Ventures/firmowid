defmodule FirmowidWeb.Components.Invoicing.SalesInvoiceDetails do
  use FirmowidWeb, :live_component

  alias Firmowid.SalesInvoices.SalesInvoice
  alias FirmowidWeb.Components.Invoicing.InvoiceDetails, as: InvoiceDetails

  attr :invoice, SalesInvoice, required: true
  attr :preview_url, :string, required: true
  attr :preview_type, :atom, required: true
  attr :potential_transactions, :list, default: []
  attr :show_vat_for_sales_invoice, :boolean, default: true

  @impl true
  def render(assigns) do
    assigns =
      assigns
      |> assign(:is_cost_invoice, false)
      |> assign(
        :description,
        case assigns.invoice.sales_invoice_items do
          [first | _] -> Map.get(first, :name, "")
          _ -> ""
        end
      )

    ~H"""
    <div class="flex flex-col">
      <InvoiceDetails.invoice_header
        is_cost_invoice={false}
        issue_date={@invoice.issue_date}
        party_display_name={@invoice.buyer_display_name}
        description={@description}
      />

      <div class="flex flex-col justify-between px-8 gap-4 lg:gap-12 lg:flex-row">
        <aside class="min-w-[320px] lg:w-[600px] flex flex-col gap-4 order-last lg:order-none py-8">
          <div class="grid grid-cols-[130px_1fr] gap-2 py-4">
            <InvoiceDetails.invoice_metadata_piece
              label="Numer faktury"
              value={@invoice.invoice_number}
              piece_id="inv-id"
            />
            <InvoiceDetails.invoice_metadata_piece
              label="Kupujący"
              value={@invoice.buyer_display_name}
              piece_id="buyer"
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
            is_cost_invoice={false}
            total_amount={
              Money.new(
                @invoice.currency,
                Firmowid.SalesInvoices.SalesInvoice.get_gross_value(@invoice)
              )
            }
          />

          <h3 class="self-start text-sm uppercase text-darkGrey mt-8">Podgląd faktury</h3>
          <div class="mb-8 mt-4 transition-opacity transition-duration-300 hover:opacity-50">
            <%= if @preview_type == :html do %>
              <div class="w-full h-full max-h-[80vh] border-black border-2 rounded-lg overflow-hidden">
                <a href={~p"/sprzedazowe/#{@invoice.id}/pobierz"} target="_blank">
                  <FirmowidWeb.PdfHTML.sales_invoice
                    sales_invoice={@invoice}
                    currency_rate={
                      if @invoice.currency == "PLN",
                        do: nil,
                        else:
                          Firmowid.Nbp.ApiClient.get_exchange_rate(
                            @invoice.currency,
                            Firmowid.SalesInvoices.SalesInvoice.get_currency_conversion_date(@invoice)
                          )
                    }
                    show_vat={@show_vat_for_sales_invoice}
                  />
                </a>
              </div>
            <% end %>
          </div>
        </aside>

        <main class="flex-grow py-8 lg:pl-8 border-b lg:border-b-0 lg:border-l border-darkGrey/[.3]">
          <%= cond do %>
            <% @invoice.skip_invoicing -> %>
              <InvoiceDetails.invoice_skipped_view />
            <% length(@invoice.transactions) == 1 -> %>
              <InvoiceDetails.single_transaction_match
                is_cost_invoice={false}
                transaction={@invoice.transactions |> hd()}
              />
            <% length(@invoice.transactions) > 1 -> %>
              <InvoiceDetails.multiple_transactions_match
                is_cost_invoice={false}
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
              <h3 class="text-lg font-semibold my-10">Co możesz zrobić?</h3>
              <div class="text-darkGrey flex flex-col gap-8">
                <div class="flex flex-row justify-between gap-16">
                  <p>
                    Może żadna nie pasuje, bo zapłacono gotówką, lub na inne konto?
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
            <% true -> %>
              <div class="flex flex-col gap-16">
                <InvoiceDetails.potential_transactions_list
                  potential_transactions={@potential_transactions}
                  name_field={:debtor_name}
                />
                <InvoiceDetails.skip_invoicing />
              </div>
          <% end %>
        </main>
      </div>
    </div>
    """
  end
end
