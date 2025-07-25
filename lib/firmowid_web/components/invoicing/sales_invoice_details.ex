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

      <div class="flex flex-col justify-between px-8 gap-4 lg:gap-12 lg:flex-row min-w-0">
        <aside class="w-full lg:w-[400px] xl:w-[600px] flex-shrink-0 flex-grow-0 flex flex-col gap-4 order-last lg:order-none py-8">
          <div class="flex flex-row justify-end gap-2">
            <.link
              id="copy-invoice-link"
              phx-hook="Tippy"
              data-tippy-content="Skopiuj fakturę"
              data-tippy-delay="100"
              class={[
                "hover:text-white hover:bg-darkGrey text-darkGrey transition-all transition-duration-300",
                "px-2 py-1 flex items-center justify-center rounded"
              ]}
              navigate={~p"/sprzedazowe?skopiuj=#{@invoice.id}"}
            >
              <.icon name="hero-document-duplicate" class="w-5 h-5" />
            </.link>
            <.link
              id="edit-invoice-link"
              phx-hook="Tippy"
              data-tippy-content="Edytuj fakturę"
              data-tippy-delay="100"
              class={[
                "hover:text-white hover:bg-darkGrey text-darkGrey transition-all transition-duration-300",
                "px-2 py-1 flex items-center justify-center rounded"
              ]}
              navigate={~p"/sprzedazowe/#{@invoice.id}/edycja"}
            >
              <.icon name="hero-pencil-square-solid" class="w-5 h-5" />
            </.link>
            <button
              id="delete-invoice-button"
              phx-hook="Tippy"
              data-tippy-content="Usuń fakturę"
              data-tippy-delay="100"
              class={[
                "hover:text-white hover:bg-darkGrey text-darkGrey transition-all transition-duration-300",
                "px-2 py-1 flex items-center justify-center rounded"
              ]}
              phx-click={show_modal("delete-invoice-modal")}
            >
              <.icon name="hero-trash-solid" class="w-5 h-5" />
            </button>

            <div class="abosolute">
              <.modal id="delete-invoice-modal" on_cancel={hide_modal("delete-invoice-modal")}>
                <p>
                  Czy na pewno chcesz usunąć fakturę <span class="font-semibold">{@invoice.invoice_number}</span>?
                </p>
                <div class="mt-6 flex justify-end gap-3">
                  <.button
                    variant="outline"
                    color="black"
                    phx-click={hide_modal("delete-invoice-modal")}
                  >
                    Anuluj
                  </.button>
                  <.button
                    color="red"
                    phx-click={
                      JS.exec("data-cancel", to: "#delete-invoice-modal")
                      |> JS.push("delete")
                    }
                    phx-disable-with="Usuwanie..."
                  >
                    Usuń
                  </.button>
                </div>
              </.modal>
            </div>
          </div>
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
              <InvoiceDetails.skip_invoicing show_bank_transfer_modal={false} invoice={@invoice} />
            <% true -> %>
              <div class="flex flex-col gap-16">
                <InvoiceDetails.potential_transactions_list
                  potential_transactions={@potential_transactions}
                  name_field={:debtor_name}
                />
                <InvoiceDetails.skip_invoicing show_bank_transfer_modal={false} invoice={@invoice} />
              </div>
          <% end %>
        </main>
      </div>
    </div>
    """
  end
end
