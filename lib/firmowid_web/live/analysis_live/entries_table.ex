defmodule FirmowidWeb.AnalysisLive.EntriesTable do
  @moduledoc """
  Table component for listing analysis entries (sales invoices, cost invoices,
  and standalone transactions) in the analysis dashboard.

  Adapted from the invoicing entries table, stripped down to read-only display
  with party, sale/booking date, and amount columns.
  """
  use FirmowidWeb, :html

  alias Firmowid.CostInvoices.CostInvoice
  alias Firmowid.Finances.Transaction
  alias Firmowid.SalesInvoices
  alias Firmowid.SalesInvoices.SalesInvoice

  attr :entries, :list, required: true

  def table(%{entries: []} = assigns) do
    ~H"""
    <p class="text-center text-darkGrey py-8">Brak wpisów</p>
    """
  end

  def table(assigns) do
    ~H"""
    <table class="table-fixed border-separate border-spacing-y-2 w-full">
      <col />
      <col class="w-36" />
      <col class="w-44" />
      <thead>
        <tr>
          <th class="pt-2 font-normal text-left text-darkGrey text-xs uppercase pb-2 pl-5">
            Kontrahent
          </th>
          <th class="pt-2 font-normal text-left text-darkGrey text-xs uppercase pb-2">
            Data sprzedaży
          </th>
          <th class="pt-2 font-normal text-left text-darkGrey text-xs uppercase pb-2">
            Kwota
          </th>
        </tr>
      </thead>
      <tbody>
        <.row :for={entry <- @entries} entry={entry} />
      </tbody>
    </table>
    """
  end

  defp row(%{entry: %SalesInvoice{} = invoice} = assigns) do
    assigns =
      assigns
      |> assign(:party, SalesInvoices.buyer_display_name(invoice) || "")
      |> assign(:description, Enum.map_join(invoice.sales_invoice_items, ", ", & &1.name))
      |> assign(:date, invoice.sale_date || invoice.issue_date)
      |> assign(:amount, Money.new(invoice.currency, SalesInvoice.get_gross_value(invoice)))
      |> assign(:amount_decimal, SalesInvoice.get_gross_value(invoice))
      |> assign(:navigate, ~p"/sprzedazowe/#{invoice.id}")

    ~H"<.entry_row {assigns} />"
  end

  defp row(%{entry: %CostInvoice{} = invoice} = assigns) do
    assigns =
      assigns
      |> assign(:party, invoice.seller_display_name || invoice.seller || "")
      |> assign(:description, invoice.description)
      |> assign(:date, invoice.sale_date)
      |> assign(:amount, Money.new(invoice.currency, invoice.total_amount))
      |> assign(:amount_decimal, invoice.total_amount)
      |> assign(:navigate, ~p"/kosztowe/#{invoice.id}")

    ~H"<.entry_row {assigns} />"
  end

  defp row(%{entry: %Transaction{} = transaction} = assigns) do
    party =
      if Decimal.compare(transaction.transaction_amount, 0) == :gt do
        transaction.debtor_name
      else
        transaction.creditor_name
      end

    assigns =
      assigns
      |> assign(:party, party || "")
      |> assign(:description, transaction.remittance_information_unstructured)
      |> assign(:date, transaction.booking_date)
      |> assign(:amount, Money.new(transaction.transaction_currency, transaction.transaction_amount))
      |> assign(:amount_decimal, transaction.transaction_amount)
      |> assign(:navigate, nil)

    ~H"<.entry_row {assigns} />"
  end

  defp entry_row(assigns) do
    ~H"""
    <tr>
      <td class="bg-white py-2 rounded-l-md pl-5 pr-5">
        <div class="whitespace-nowrap overflow-hidden text-ellipsis max-w-[50vw]">
          <%= if @navigate do %>
            <.link navigate={@navigate} class="hover:underline">
              <.party_cell party={@party} description={@description} />
            </.link>
          <% else %>
            <.party_cell party={@party} description={@description} />
          <% end %>
        </div>
      </td>
      <td class="bg-white py-2 font-light">
        {@date}
      </td>
      <td class={[
        "py-2 rounded-r-md",
        if(Decimal.gte?(@amount_decimal, 0),
          do: "text-blueText bg-blueBg",
          else: "text-orangeText bg-orangeBg"
        )
      ]}>
        <div class="text-right pr-5 py-1">
          {@amount}
        </div>
      </td>
    </tr>
    """
  end

  defp party_cell(assigns) do
    ~H"""
    {@party}
    <span :if={@description != "" and @description != nil} class="text-darkGrey opacity-50 text-sm">
      {@description}
    </span>
    """
  end
end
