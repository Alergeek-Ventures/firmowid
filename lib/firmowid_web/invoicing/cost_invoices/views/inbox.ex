defmodule FirmowidWeb.Invoicing.CostInvoices.Views.Inbox do
  @moduledoc false
  use FirmowidWeb, :live_view

  alias Firmowid.CostInvoices

  @impl true
  def mount(_params, _session, socket) do
    Bodyguard.permit!(CostInvoices, :read_inbox, socket.assigns.current_user)

    emails = CostInvoices.list_inbound_emails()

    socket =
      socket
      |> assign(:page_title, "Skrzynka odbiorcza")
      |> stream(:emails, emails)

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="px-4 sm:px-6 lg:px-8">
      <div class="sm:flex sm:items-center mb-6">
        <div class="sm:flex-auto">
          <h1 class="text-xl font-bold leading-6 text-black">Skrzynka odbiorcza</h1>
          <p class="mt-2 text-sm text-darkGrey">
            Lista wszystkich e-maili z fakturami kosztowymi
          </p>
        </div>
      </div>

      <table class="table-fixed border-separate border-spacing-y-3 w-full">
        <col class="w-44" />
        <col />
        <col />
        <col class="w-36" />
        <col />
        <thead class="sticky top-[130px] bg-lightGreyBg z-[1]">
          <tr>
            <th class="pt-4 font-normal text-left text-darkGrey text-xs uppercase pb-2 pl-5">
              Data otrzymania
            </th>
            <th class="pt-4 font-normal text-left text-darkGrey text-xs uppercase pb-2">
              Nadawca
            </th>
            <th class="pt-4 font-normal text-left text-darkGrey text-xs uppercase pb-2">
              Temat
            </th>
            <th class="pt-4 font-normal text-left text-darkGrey text-xs uppercase pb-2">
              Status
            </th>
            <th class="pt-4 font-normal text-left text-darkGrey text-xs uppercase pb-2">
              Szczegóły
            </th>
          </tr>
        </thead>
        <tbody id="emails" phx-update="stream">
          <tr :for={{id, email} <- @streams.emails} id={id}>
            <td class="transition-all duration-500 bg-white py-4 rounded-l-md pl-5 font-light text-sm">
              {Calendar.strftime(email.received_at, "%Y-%m-%d %H:%M")}
            </td>
            <td class="transition-all duration-500 bg-white py-4 text-sm">
              <div class="w-full whitespace-nowrap overflow-hidden text-ellipsis">
                {email.sender_email}
              </div>
            </td>
            <td class="transition-all duration-500 bg-white py-4 text-sm">
              <div class="w-full whitespace-nowrap overflow-hidden text-ellipsis">
                {email.subject || "(bez tematu)"}
              </div>
            </td>
            <td class="transition-all duration-500 bg-white py-4">
              <%= if is_nil(email.processed_at) do %>
                <div class="text-xs h-6 flex flex-row justify-center items-center py-2 px-2 rounded-md w-32 bg-greyButtonBg text-darkGrey">
                  <div class="font-normal uppercase">Przetwarzanie</div>
                </div>
              <% else %>
                <%= if is_nil(email.failure_reason) do %>
                  <div class="text-xs h-6 flex flex-row justify-center items-center py-2 px-2 rounded-md w-32 bg-greenBg text-greenText">
                    <div class="font-normal uppercase">Sukces</div>
                    <.icon name="hero-check-micro" class="w-4 h-4 ml-1" />
                  </div>
                <% else %>
                  <div class="text-xs h-6 flex flex-row justify-center items-center py-2 px-2 rounded-md w-32 bg-redBg text-redText">
                    <div class="font-normal uppercase">Błąd</div>
                  </div>
                <% end %>
              <% end %>
            </td>
            <td class="transition-all duration-500 bg-white py-2 rounded-r-md pr-5 text-sm">
              <%= if is_nil(email.processed_at) do %>
                <span class="text-darkGrey opacity-50">W trakcie...</span>
              <% else %>
                <%= if is_nil(email.failure_reason) do %>
                  <.render_invoice_links email={email} />
                <% else %>
                  <span class="text-darkGrey">{format_failure_reason(email.failure_reason)}</span>
                <% end %>
              <% end %>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  defp render_invoice_links(%{email: email} = assigns) do
    count = length(email.cost_invoices)

    case count do
      0 ->
        ~H"""
        <span class="text-darkGrey opacity-50">Brak załączników do przetworzenia</span>
        """

      1 ->
        invoice = hd(email.cost_invoices)
        assigns = assign(assigns, :invoice, invoice)

        ~H"""
        <.link navigate={~p"/kosztowe/#{@invoice.id}"} class="text-blueText hover:underline">
          {@invoice.seller_display_name || @invoice.seller} - {Money.new(
            @invoice.currency,
            Decimal.abs(@invoice.total_amount)
          )}
        </.link>
        """

      _ ->
        ~H"""
        <div class="relative" id={"invoice-dropdown-#{@email.id}"}>
          <button
            type="button"
            class="text-blueText hover:underline flex items-center gap-1"
            phx-click={JS.toggle(to: "#invoice-list-#{@email.id}")}
          >
            {length(@email.cost_invoices)} faktur <.icon name="hero-chevron-down" class="w-4 h-4" />
          </button>
          <div
            id={"invoice-list-#{@email.id}"}
            class="hidden absolute z-10 mt-2 w-56 rounded-md bg-white shadow-lg ring-1 ring-black/5"
          >
            <div class="py-1">
              <.link
                :for={invoice <- @email.cost_invoices}
                navigate={~p"/kosztowe/#{invoice.id}"}
                class="block px-4 py-2 text-sm text-zinc-700 hover:bg-zinc-100"
              >
                {invoice.seller_display_name || invoice.seller} - {Money.new(
                  invoice.currency,
                  Decimal.abs(invoice.total_amount)
                )}
              </.link>
            </div>
          </div>
        </div>
        """
    end
  end

  defp format_failure_reason(:unexpected_sender), do: "Nieznany nadawca"
  defp format_failure_reason(:no_attachment), do: "Brak załączników"
  defp format_failure_reason(:processing_failed), do: "Błąd przetwarzania"
  defp format_failure_reason(_), do: "Nieznany błąd"
end
