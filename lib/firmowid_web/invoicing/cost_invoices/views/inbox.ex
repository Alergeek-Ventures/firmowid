defmodule FirmowidWeb.Invoicing.CostInvoices.Views.Inbox do
  @moduledoc false
  use FirmowidWeb, :live_view

  alias Firmowid.Ash.Invoicing.InboundEmail

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.ash_scope

    emails = InboundEmail.list_all!(load: [cost_invoices: [:amount]], scope: scope)

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
      <div class="mb-6 sm:flex sm:items-center">
        <div class="sm:flex-auto">
          <h1 class="text-xl/6 font-bold text-black">Skrzynka odbiorcza</h1>
          <p class="mt-2 text-sm text-darkGrey">
            Lista wszystkich e-maili z fakturami kosztowymi
          </p>
        </div>
      </div>

      <table class="w-full table-fixed border-separate border-spacing-y-3">
        <col class="w-44" />
        <col />
        <col />
        <col class="w-36" />
        <col />
        <thead class="sticky top-[130px] z-1 bg-lightGreyBg">
          <tr>
            <th class="pt-4 pb-2 pl-5 text-left text-xs font-normal text-darkGrey uppercase">
              Data otrzymania
            </th>
            <th class="pt-4 pb-2 text-left text-xs font-normal text-darkGrey uppercase">
              Nadawca
            </th>
            <th class="pt-4 pb-2 text-left text-xs font-normal text-darkGrey uppercase">
              Temat
            </th>
            <th class="pt-4 pb-2 text-left text-xs font-normal text-darkGrey uppercase">
              Status
            </th>
            <th class="pt-4 pb-2 text-left text-xs font-normal text-darkGrey uppercase">
              Szczegóły
            </th>
          </tr>
        </thead>
        <tbody id="emails" phx-update="stream">
          <tr :for={{id, email} <- @streams.emails} id={id}>
            <td class="rounded-l-md bg-white py-4 pl-5 text-sm font-light transition-all duration-500">
              {Calendar.strftime(email.received_at, "%Y-%m-%d %H:%M")}
            </td>
            <td class="bg-white py-4 text-sm transition-all duration-500">
              <div class="w-full truncate">
                {email.sender_email}
              </div>
            </td>
            <td class="bg-white py-4 text-sm transition-all duration-500">
              <div class="w-full truncate">
                {email.subject || "(bez tematu)"}
              </div>
            </td>
            <td class="bg-white py-4 transition-all duration-500">
              <%= if is_nil(email.processed_at) do %>
                <div class="flex h-6 w-32 flex-row items-center justify-center rounded-md bg-greyButtonBg p-2 text-xs text-darkGrey">
                  <div class="font-normal uppercase">Przetwarzanie</div>
                </div>
              <% else %>
                <%= if is_nil(email.failure_reason) do %>
                  <div class="flex h-6 w-32 flex-row items-center justify-center rounded-md bg-greenBg p-2 text-xs text-greenText">
                    <div class="font-normal uppercase">Sukces</div>
                    <.icon name="hero-check-micro" class="ml-1 size-4" />
                  </div>
                <% else %>
                  <div class="flex h-6 w-32 flex-row items-center justify-center rounded-md bg-redBg p-2 text-xs text-redText">
                    <div class="font-normal uppercase">Błąd</div>
                  </div>
                <% end %>
              <% end %>
            </td>
            <td class="rounded-r-md bg-white py-2 pr-5 text-sm transition-all duration-500">
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
        <FirmowidUI.Components.Link.link
          kind="unstyled"
          navigate={~p"/kosztowe/#{@invoice.id}"}
          class="text-blueText hover:underline"
        >
          {@invoice.seller_display_name || @invoice.seller} - {Money.abs(@invoice.amount)}
        </FirmowidUI.Components.Link.link>
        """

      _ ->
        ~H"""
        <div class="relative" id={"invoice-dropdown-#{@email.id}"}>
          <FirmowidUI.Components.Button.button
            type="button"
            variant="unstyled"
            class="inline-flex items-center gap-1 text-blueText hover:underline"
            phx-click={JS.toggle(to: "#invoice-list-#{@email.id}")}
          >
            {length(@email.cost_invoices)} faktur <.icon name="hero-chevron-down" class="size-4" />
          </FirmowidUI.Components.Button.button>
          <div
            id={"invoice-list-#{@email.id}"}
            class="absolute z-10 mt-2 hidden w-56 rounded-md bg-white shadow-lg ring-1 ring-black/5"
          >
            <div class="py-1">
              <FirmowidUI.Components.Link.link
                :for={invoice <- @email.cost_invoices}
                kind="unstyled"
                navigate={~p"/kosztowe/#{invoice.id}"}
                class="block px-4 py-2 text-sm text-grey-700 hover:bg-grey-100"
              >
                {invoice.seller_display_name || invoice.seller} - {Money.abs(invoice.amount)}
              </FirmowidUI.Components.Link.link>
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
