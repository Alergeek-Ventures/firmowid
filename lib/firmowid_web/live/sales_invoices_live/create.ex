defmodule FirmowidWeb.SalesInvoicesLive.Create do
  use FirmowidWeb, :live_view

  alias Firmowid.SalesInvoices
  alias Firmowid.SalesInvoices.SalesInvoice

  def mount(params, _session, socket) do
    sales_invoices = SalesInvoices.search_sales_invoices("")

    socket =
      socket
      |> assign(:sales_invoices, sales_invoices)
      |> assign(:search_term, "")

    {:ok, socket}
  end

  def handle_event("search-term", %{"search-term" => search_term}, socket) do
    socket =
      socket
      |> assign(:sales_invoices, SalesInvoices.search_sales_invoices(search_term))
      |> assign(:search_term, search_term)

    {:noreply, socket}
  end

  def render(assigns) do
    ~H"""
    <main class="flex flex-col justify-center items-center pt-16">
      <h1 class="text-2xl font-bold">Wybierz sposób wystawienia faktury</h1>

      <.modal id="copy_previous_invoice_modal">
        <div class="flex flex-col gap-4 mb-8">
          <h2 class="text-lg font-bold">Znajdź odpowiednią fakturę</h2>
          <div class="flex flex-row gap-4 items-center justify-start mb-4">
            <.form phx-change="search-term">
              <label class="flex flex-row gap-2 items-center justify-start bg-greyButtonBg px-2 py-1 rounded max-w-[400px]">
                <.icon name="hero-magnifying-glass-solid" class="w-6 h-6" />
                <input
                  id="search"
                  class={[
                    "bg-transparent",
                    "border-none",
                    "rounded px-2 py-1",
                    "focus:outline-none focus:ring-0"
                  ]}
                  name="search-term"
                  value={@search_term}
                />
              </label>
            </.form>
            <p class="text-sm text-darkGrey">znaleziono faktur: {length(@sales_invoices)}</p>
          </div>
        </div>

        <div class="flex flex-row flex-wrap justify-center items-start gap-8 overflow-scroll h-[500px]">
          <%= case @sales_invoices do %>
            <% [] -> %>
              <div class="flex flex-col items-center justify-center gap-4 p-4 w-full h-64">
                <p class="text-darkGrey text-center">
                  Nie znaleziono faktur - spróbuj wpisac inne słowa kluczowe
                </p>
              </div>
            <% _ -> %>
              <%= for invoice <- @sales_invoices do %>
                <div class={[
                  "flex flex-col gap-4 pr-4 w-full border-b border-greyButtonBg pb-4"
                ]}>
                  <div class="flex flex-col gap-2">
                    <div class="flex flex-row gap-2 items-center">
                      <.icon name="hero-document-text" class="w-4 h-4" />
                      <p>{invoice.invoice_number} · {invoice.issue_date}</p>
                    </div>
                    <p class="text-lg">{invoice.buyer_display_name}</p>
                    <p class="text-darkGrey">
                      {invoice.sales_invoice_items |> Enum.at(0) |> Map.get(:name)}
                    </p>
                    <p class="font-bold">
                      {Money.new(
                        SalesInvoice.get_gross_value(invoice),
                        invoice.currency
                      )}
                    </p>
                  </div>
                  <.link
                    class={
                      button_styles(%{variant: "outline", class: "text-center w-[240px] self-end"})
                    }
                    navigate={~p"/sprzedazowe?skopiuj=#{invoice.id}"}
                  >
                    Wybierz
                  </.link>
                </div>
              <% end %>
          <% end %>
        </div>
        <div class="flex flex-row w-full justify-center mt-8">
          <.button
            variant="outline"
            class="border-none"
            phx-click={hide_modal("copy_previous_invoice_modal")}
          >
            Wróć
          </.button>
        </div>
      </.modal>

      <div class="flex flex-row items-center gap-4 mt-16">
        <%= for type <- [
          %{
            slug: "polski",
            name: "Kontrahent w Polsce",
            icon: "hero-flag",
            description: "Faktura wystawiana dla kontrahenta z Polski, zawiera VAT"
          },
          %{
            slug: "zagraniczny",
            name: "Kontrahent zagraniczny",
            icon: "hero-globe-americas",
            description: "Faktura wystawiana dla zagranicznego kontrahenta, korzysta z odwrotnego obciążenia"
          }
        ] do %>
          <.link
            class={[
              "flex flex-col text-center items-center justify-start gap-2 bg-white rounded px-4 py-8 w-80 h-56",
              "hover:bg-greyButtonBg transition-all duration-300"
            ]}
            navigate={~p"/sprzedazowe?typ=#{type[:slug]}"}
          >
            <.icon name={type[:icon]} class="w-12 h-12" />
            <span class="font-bold">{type[:name]}</span>
            <span class="text-sm text-darkGrey">{type[:description]}</span>
          </.link>
        <% end %>

        <button
          phx-click={show_modal("copy_previous_invoice_modal")}
          class={[
            "flex flex-col text-center items-center justify-start gap-2 bg-white rounded px-4 py-8 w-80 h-56",
            "hover:bg-greyButtonBg transition-all duration-300"
          ]}
        >
          <.icon name="hero-document-duplicate" class="w-12 h-12" />
          <span class="font-bold">Skopiuj poprzednią fakturę</span>
          <span class="text-sm text-darkGrey">
            Kliknij aby wyszukać poprzednią fakturę i wystawić nową na jej podstawie
          </span>
        </button>
      </div>

      <.link navigate={~p"/"} class="mt-16 text-darkGrey flex flex-row gap-2 items-center">
        <span>
          Wróć do listy faktur
        </span>
      </.link>
    </main>
    """
  end
end
