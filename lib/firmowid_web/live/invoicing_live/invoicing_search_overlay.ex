defmodule FirmowidWeb.InvoicingLive.InvoiceSearchOverlay do
  @moduledoc false
  use FirmowidWeb, :live_component

  def render(assigns) do
    ~H"""
    <div id="invoice-search-overlay">
      <%= if @show_search and @invoicing_search_enabled do %>
        <div
          class="fixed inset-0 z-50 flex items-start justify-center"
          phx-window-keydown="close-search"
          phx-key="escape"
        >
          <!-- Backdrop -->
          <div class="absolute inset-0 bg-black/50 backdrop-blur-sm" phx-click="close-search" />
          <!-- Panel -->
          <div
            id="invoice-search-panel"
            class="relative mt-24 w-[95vw] max-w-3xl bg-white rounded-xl shadow-xl border border-darkGrey/10
                  flex flex-col overflow-hidden animate-fade-in"
            phx-hook="FocusTrap"
          >
            <div class="flex items-center gap-3 px-4 pt-4 pb-3 border-b border-lightGreyBg">
              <.icon name="hero-magnifying-glass" class="w-5 h-5 text-darkGrey" />
              <form phx-change="update-search" phx-submit="update-search" class="grow">
                <input
                  type="text"
                  name="q"
                  value={@search_query}
                  placeholder="Szukaj faktur kosztowych lub sprzedażowych..."
                  autofocus
                  class="w-full outline-none bg-transparent text-sm placeholder:text-darkGrey/50"
                  phx-debounce="200"
                />
              </form>
              <button
                phx-click="close-search"
                class="text-darkGrey/60 hover:text-darkGrey transition-colors"
                aria-label="Zamknij"
              >
                <.icon name="hero-x-mark" class="w-5 h-5" />
              </button>
            </div>

            <div class="max-h-[60vh] overflow-y-auto">
              <%= if @search_query in [nil, ""] do %>
                <div class="px-6 py-8 text-center text-darkGrey/60 text-sm">
                  Wpisz co chcesz wyszukać (np. kontrahenta, numer faktury, opis)...
                </div>
              <% else %>
                <%= if @search_results == [] do %>
                  <div class="px-6 py-8 text-center text-darkGrey/60 text-sm">
                    Brak wyników dla: <span class="font-medium">"{@search_query}"</span>
                  </div>
                <% else %>
                  <ul class="divide-y divide-lightGreyBg">
                    <%= for invoice <- @search_results do %>
                      <% type =
                        case invoice do
                          %Firmowid.CostInvoices.CostInvoice{} -> "cost"
                          %Firmowid.SalesInvoices.SalesInvoice{} -> "sales"
                        end %>
                      <% date =
                        case invoice do
                          %Firmowid.CostInvoices.CostInvoice{issue_date: d} -> d
                          %Firmowid.SalesInvoices.SalesInvoice{issue_date: d} -> d
                        end %>
                      <% amount =
                        case invoice do
                          %Firmowid.CostInvoices.CostInvoice{} ->
                            Money.new(invoice.currency, invoice.total_amount)

                          %Firmowid.SalesInvoices.SalesInvoice{} ->
                            Money.new(
                              invoice.currency,
                              Firmowid.SalesInvoices.SalesInvoice.get_gross_value(invoice)
                            )
                        end %>
                      <li>
                        <button
                          class="w-full text-left px-5 py-3 flex flex-col gap-1 hover:bg-lightGreyBg focus:bg-lightGreyBg
                                transition-colors group"
                          phx-click="goto-invoice"
                          phx-value-id={invoice.id}
                          phx-value-type={type}
                        >
                          <div class="flex items-center justify-between">
                            <div class="flex items-center gap-2">
                              <span class={[
                                "text-[11px] uppercase tracking-wide px-2 py-0.5 rounded-md",
                                type == "cost" && "bg-orangeBg text-orangeText",
                                type == "sales" && "bg-blueBg text-blueText"
                              ]}>
                                {if type == "cost", do: "Kosztowa", else: "Sprzedażowa"}
                              </span>
                              <span class="font-medium text-sm">
                                {case invoice do
                                  %Firmowid.CostInvoices.CostInvoice{seller: n} ->
                                    n

                                  %Firmowid.SalesInvoices.SalesInvoice{
                                    buyer_display_name: bd,
                                    buyer_name: bn,
                                    buyer_surname: bs
                                  } ->
                                    cond do
                                      bd not in [nil, ""] -> bd
                                      bn not in [nil, ""] && bs not in [nil, ""] -> "#{bn} #{bs}"
                                      bn not in [nil, ""] -> bn
                                      bs not in [nil, ""] -> bs
                                      true -> "szkic faktury sprzedażowej"
                                    end
                                end || "—"}
                              </span>
                            </div>
                            <div class="flex items-center gap-4 text-xs text-darkGrey/70">
                              <span>{date}</span>
                              <span class="font-medium text-black group-hover:underline">
                                {amount}
                              </span>
                            </div>
                          </div>
                          <div class="text-[11px] text-darkGrey/60 line-clamp-1">
                            {cond do
                              match?(%Firmowid.CostInvoices.CostInvoice{}, invoice) ->
                                invoice.description || invoice.invoice_identifier

                              match?(%Firmowid.SalesInvoices.SalesInvoice{}, invoice) ->
                                invoice.item_names || invoice.invoice_number

                              true ->
                                ""
                            end}
                          </div>
                        </button>
                      </li>
                    <% end %>
                  </ul>
                <% end %>
              <% end %>
            </div>

            <div class="px-4 py-2 border-t border-lightGreyBg flex items-center justify-between text-[11px] text-darkGrey/50">
              <div>
                Enter – otwórz • Esc – zamknij
              </div>
              <%= if @search_query not in [nil, ""] do %>
                <div>
                  Wyszukano: {length(@search_results)}
                </div>
              <% end %>
            </div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end
end
