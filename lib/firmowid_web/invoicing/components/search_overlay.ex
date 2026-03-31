defmodule FirmowidWeb.Invoicing.Components.SearchOverlay do
  @moduledoc false
  use FirmowidWeb, :live_component

  def render(assigns) do
    ~H"""
    <div id="invoice-search-overlay">
      <%= if @show_search do %>
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
            class="animate-fade-in border-darkGrey/10 relative mt-24 flex w-[95vw] max-w-3xl flex-col overflow-hidden rounded-xl border bg-white shadow-xl"
            phx-hook="FocusTrap"
          >
            <div class="border-lightGreyBg flex items-center gap-3 border-b px-4 pt-4 pb-3">
              <.icon name="hero-magnifying-glass" class="text-darkGrey size-5" />
              <form phx-change="update-search" phx-submit="update-search" class="grow">
                <input
                  type="text"
                  name="q"
                  value={@search_query}
                  placeholder="Szukaj faktur kosztowych lub sprzedażowych..."
                  autofocus
                  class="placeholder:text-darkGrey/50 w-full bg-transparent text-sm outline-hidden"
                  phx-debounce="200"
                />
              </form>
              <button
                phx-click="close-search"
                class="hover:text-darkGrey text-darkGrey/60 transition-colors"
                aria-label="Zamknij"
              >
                <.icon name="hero-x-mark" class="size-5" />
              </button>
            </div>

            <div class="max-h-[60vh] overflow-y-auto">
              <%= if @search_query in [nil, ""] do %>
                <div class="text-darkGrey/60 px-6 py-8 text-center text-sm">
                  Wpisz co chcesz wyszukać (np. kontrahenta, numer faktury, opis)...
                </div>
              <% else %>
                <%= if @search_results == [] do %>
                  <div class="text-darkGrey/60 px-6 py-8 text-center text-sm">
                    Brak wyników dla: <span class="font-medium">"{@search_query}"</span>
                  </div>
                <% else %>
                  <ul class="divide-lightGreyBg divide-y">
                    <%= for invoice <- @search_results do %>
                      <% type =
                        case invoice do
                          %Firmowid.Ash.Invoicing.CostInvoice{} -> "cost"
                          %Firmowid.Ash.Invoicing.SalesInvoice{} -> "sales"
                        end %>
                      <% date =
                        case invoice do
                          %Firmowid.Ash.Invoicing.CostInvoice{issue_date: d} -> d
                          %Firmowid.Ash.Invoicing.SalesInvoice{issue_date: d} -> d
                        end %>
                      <% amount =
                        case invoice do
                          %Firmowid.CostInvoices.CostInvoice{} ->
                            Money.new(invoice.currency, invoice.total_amount)

                          %Firmowid.Ash.Invoicing.SalesInvoice{} ->
                            Money.new(
                              invoice.currency,
                              Firmowid.Ash.Invoicing.SalesInvoice.get_gross_value(invoice)
                            )
                        end %>
                      <li>
                        <button
                          class="focus:bg-lightGreyBg group hover:bg-lightGreyBg flex w-full flex-col gap-1 px-5 py-3 text-left transition-colors"
                          phx-click="goto-invoice"
                          phx-value-id={invoice.id}
                          phx-value-type={type}
                        >
                          <div class="flex items-center justify-between">
                            <div class="flex items-center gap-2">
                              <span class={[
                                "rounded-md px-2 py-0.5 text-[11px] tracking-wide uppercase",
                                type == "cost" && "bg-orangeBg text-orangeText",
                                type == "sales" && "bg-blueBg text-blueText"
                              ]}>
                                {if type == "cost", do: "Kosztowa", else: "Sprzedażowa"}
                              </span>
                              <span class="text-sm font-medium">
                                {case invoice do
                                  %Firmowid.CostInvoices.CostInvoice{seller: n} ->
                                    n

                                  %Firmowid.Ash.Invoicing.SalesInvoice{} = si ->
                                    Firmowid.Ash.Invoicing.SalesInvoice.buyer_display_name(si) ||
                                      "szkic faktury sprzedażowej"
                                end || "—"}
                              </span>
                            </div>
                            <div class="text-darkGrey/70 flex items-center gap-4 text-xs">
                              <span>{date}</span>
                              <span class="font-medium text-black group-hover:underline">
                                {amount}
                              </span>
                            </div>
                          </div>
                          <div class="text-darkGrey/60 line-clamp-1 text-[11px]">
                            {cond do
                              match?(%Firmowid.CostInvoices.CostInvoice{}, invoice) ->
                                invoice.description || invoice.invoice_identifier

                              match?(%Firmowid.Ash.Invoicing.SalesInvoice{}, invoice) ->
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

            <div class="border-lightGreyBg text-darkGrey/50 flex items-center justify-between border-t px-4 py-2 text-[11px]">
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
