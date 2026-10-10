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
            class="relative mt-24 flex w-[95vw] max-w-3xl animate-fade-in flex-col overflow-hidden rounded-xl border border-darkGrey/10 bg-white shadow-xl"
            phx-hook="FocusTrap"
          >
            <div class="flex items-center gap-3 border-b border-lightGreyBg px-4 pt-4 pb-3">
              <.icon name="hero-magnifying-glass" class="size-5 text-darkGrey" />
              <form phx-change="update-search" phx-submit="update-search" class="grow">
                <input
                  type="text"
                  name="q"
                  value={@search_query}
                  placeholder="Szukaj faktur kosztowych lub sprzedażowych..."
                  autofocus
                  class="w-full bg-transparent text-sm outline-hidden placeholder:text-darkGrey/50"
                  phx-debounce="200"
                />
              </form>
              <FirmowidUI.Components.Button.button
                phx-click="close-search"
                type="button"
                variant="unstyled"
                class="inline-flex items-center justify-center text-darkGrey/60 transition-colors hover:text-darkGrey"
                aria-label="Zamknij"
              >
                <.icon name="hero-x-mark" class="size-5" />
              </FirmowidUI.Components.Button.button>
            </div>

            <div class="max-h-[60vh] overflow-y-auto">
              <%= if @search_query in [nil, ""] do %>
                <div class="px-6 py-8 text-center text-sm text-darkGrey/60">
                  Wpisz co chcesz wyszukać (np. kontrahenta, numer faktury, opis)...
                </div>
              <% else %>
                <%= if @search_results == [] do %>
                  <div class="px-6 py-8 text-center text-sm text-darkGrey/60">
                    Brak wyników dla: <span class="font-medium">"{@search_query}"</span>
                  </div>
                <% else %>
                  <ul class="divide-y divide-lightGreyBg">
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
                          %Firmowid.Ash.Invoicing.CostInvoice{} -> invoice.amount
                          %Firmowid.Ash.Invoicing.SalesInvoice{} -> invoice.amount
                        end %>
                      <li>
                        <FirmowidUI.Components.Button.button
                          type="button"
                          variant="unstyled"
                          class="group flex w-full cursor-pointer flex-col gap-1 px-5 py-3 text-left focus:bg-lightGreyBg"
                          phx-click="goto-invoice"
                          phx-value-id={invoice.id}
                          phx-value-type={type}
                        >
                          <div class="flex items-center justify-between">
                            <div class="flex items-center gap-2">
                              <span class={[
                                "rounded-md px-2 py-0.5 text-caps-sm tracking-wide uppercase",
                                type == "cost" && "bg-orangeBg text-orangeText",
                                type == "sales" && "bg-blueBg text-blueText"
                              ]}>
                                {if type == "cost", do: "Kosztowa", else: "Sprzedażowa"}
                              </span>
                              <span class="text-sm font-medium">
                                {case invoice do
                                  %Firmowid.Ash.Invoicing.CostInvoice{seller: n} ->
                                    n

                                  %Firmowid.Ash.Invoicing.SalesInvoice{} = si ->
                                    si.buyer_display_name_label ||
                                      "szkic faktury sprzedażowej"
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
                          <div class="line-clamp-1 text-caps-sm text-darkGrey/60">
                            {cond do
                              match?(%Firmowid.Ash.Invoicing.CostInvoice{}, invoice) ->
                                invoice.description || invoice.invoice_identifier

                              match?(%Firmowid.Ash.Invoicing.SalesInvoice{}, invoice) ->
                                invoice.item_names || invoice.invoice_number

                              true ->
                                ""
                            end}
                          </div>
                        </FirmowidUI.Components.Button.button>
                      </li>
                    <% end %>
                  </ul>
                <% end %>
              <% end %>
            </div>

            <div class="flex items-center justify-between border-t border-lightGreyBg px-4 py-2 text-caps-sm text-darkGrey/50">
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
