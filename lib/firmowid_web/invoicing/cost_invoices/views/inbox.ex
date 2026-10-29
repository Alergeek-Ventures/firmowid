defmodule FirmowidWeb.Invoicing.CostInvoices.Views.Inbox do
  @moduledoc false
  use FirmowidWeb, :live_view

  alias Firmowid.Invoicing.InboundEmail

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.ash_scope

    emails = InboundEmail.list_all!(load: [cost_invoices: [:amount]], scope: scope)

    socket =
      socket
      |> assign(:page_title, gettext("Inbox"))
      |> stream(:emails, emails)

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="px-4 sm:px-6 lg:px-8">
      <div class="mb-6 sm:flex sm:items-center">
        <div class="sm:flex-auto">
          <h1 class="text-xl/6 font-bold text-black">{gettext("Inbox")}</h1>
          <p class="mt-2 text-sm text-grey-700">
            {gettext("List of all emails with cost invoices")}
          </p>
        </div>
      </div>

      <div class="max-md:overflow-x-auto">
        <table class="w-full table-fixed border-separate border-spacing-y-3 max-md:min-w-3xl">
          <col class="w-44" />
          <col />
          <col />
          <col class="w-36" />
          <col />
          <thead class="sticky top-[130px] z-1 bg-grey-100">
            <tr>
              <th class="pt-4 pb-2 pl-5 text-left text-xs font-normal text-grey-700 uppercase">
                {pgettext("inbox column", "Received")}
              </th>
              <th class="pt-4 pb-2 text-left text-xs font-normal text-grey-700 uppercase">
                {pgettext("inbox column", "Sender")}
              </th>
              <th class="pt-4 pb-2 text-left text-xs font-normal text-grey-700 uppercase">
                {pgettext("inbox column", "Subject")}
              </th>
              <th class="pt-4 pb-2 text-left text-xs font-normal text-grey-700 uppercase">
                {gettext("Status")}
              </th>
              <th class="pt-4 pb-2 text-left text-xs font-normal text-grey-700 uppercase">
                {pgettext("inbox column", "Details")}
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
                  {email.subject || gettext("(no subject)")}
                </div>
              </td>
              <td class="bg-white py-4 transition-all duration-500">
                <%= if is_nil(email.processed_at) do %>
                  <div class="flex h-6 w-32 flex-row items-center justify-center rounded-md bg-grey-200 p-2 text-xs text-grey-700">
                    <div class="font-normal uppercase">{pgettext("inbox status", "Processing")}</div>
                  </div>
                <% else %>
                  <%= if is_nil(email.failure_reason) do %>
                    <div class="flex h-6 w-32 flex-row items-center justify-center rounded-md bg-moss-200 p-2 text-xs text-moss-700">
                      <div class="font-normal uppercase">{pgettext("inbox status", "Success")}</div>
                      <.icon name="hero-check-micro" class="ml-1 size-4" />
                    </div>
                  <% else %>
                    <div class="flex h-6 w-32 flex-row items-center justify-center rounded-md bg-brick-200 p-2 text-xs text-brick-700">
                      <div class="font-normal uppercase">{gettext("Error")}</div>
                    </div>
                  <% end %>
                <% end %>
              </td>
              <td class="rounded-r-md bg-white py-2 pr-5 text-sm transition-all duration-500">
                <%= if is_nil(email.processed_at) do %>
                  <span class="text-grey-700 opacity-50">{gettext("In progress...")}</span>
                <% else %>
                  <%= if is_nil(email.failure_reason) do %>
                    <.render_invoice_links email={email} />
                  <% else %>
                    <span class="text-grey-700">{format_failure_reason(email.failure_reason)}</span>
                  <% end %>
                <% end %>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
    """
  end

  defp render_invoice_links(%{email: email} = assigns) do
    count = length(email.cost_invoices)

    case count do
      0 ->
        ~H"""
        <span class="text-grey-700 opacity-50">{gettext("No attachments to process")}</span>
        """

      1 ->
        invoice = hd(email.cost_invoices)
        assigns = assign(assigns, :invoice, invoice)

        ~H"""
        <FirmowidUI.Components.Link.link
          kind="unstyled"
          navigate={~p"/kosztowe/#{@invoice.id}"}
          class="text-teal-800 hover:underline"
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
            class="inline-flex items-center gap-1 text-teal-800 hover:underline"
            phx-click={JS.toggle(to: "#invoice-list-#{@email.id}")}
          >
            {ngettext("%{count} invoice", "%{count} invoices", length(@email.cost_invoices))}
            <.icon name="hero-chevron-down" class="size-4" />
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

  defp format_failure_reason(:unexpected_sender), do: gettext("Unknown sender")
  defp format_failure_reason(:no_attachment), do: gettext("No attachments")
  defp format_failure_reason(:processing_failed), do: gettext("Processing error")
  defp format_failure_reason(_), do: gettext("Unknown error")
end
