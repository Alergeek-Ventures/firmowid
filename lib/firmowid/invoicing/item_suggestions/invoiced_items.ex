defmodule Firmowid.Invoicing.ItemSuggestions.InvoicedItems do
  @moduledoc """
  The distinct items of the organization's sales invoices issued in the last
  year, of all its invoices or of those to one counterparty.
  """

  alias Firmowid.Invoicing
  alias Firmowid.Invoicing.SalesInvoice
  alias Firmowid.Invoicing.SalesInvoiceItem
  alias Firmowid.LocalDate
  alias Firmowid.Scope

  require Ash.Query

  @limit 100

  @type item :: %{
          name: String.t(),
          count: pos_integer(),
          quantity: Decimal.t() | nil,
          unit: String.t() | nil,
          unit_price: Decimal.t() | nil,
          currency: String.t(),
          vat_rate: String.t() | nil
        }

  @doc """
  Lists at most #{@limit} items, most used first and, among equally used ones,
  most recently used first. Items are told apart by their trimmed name in any
  letter case, and each carries the name, quantity, unit, net unit price,
  currency and VAT rate of its latest use. Corrections are left out: their lines
  say what changed, not what was sold.
  """
  @spec list(Scope.t(), Ash.UUID.t() | nil) :: [item()]
  def list(scope, counterparty_id \\ nil) do
    SalesInvoice
    |> Ash.Query.select([:id, :currency, :issue_date])
    |> Ash.Query.filter(ksef_invoice_kind != :kor)
    |> filter_counterparty(counterparty_id)
    |> Ash.Query.sort(issue_date: :desc)
    |> Ash.Query.load(
      sales_invoice_items: Ash.Query.select(SalesInvoiceItem, [:name, :quantity, :unit, :unit_price, :vat_rate])
    )
    |> then(
      &Invoicing.list_sales_invoices!(
        %{date_from: Date.shift(LocalDate.today(), year: -1), submission: :confirmed},
        scope: scope,
        query: &1
      )
    )
    |> Enum.flat_map(fn invoice ->
      Enum.map(invoice.sales_invoice_items, &%{item: &1, currency: invoice.currency})
    end)
    |> Enum.reject(&(String.trim(&1.item.name) == ""))
    |> Enum.with_index()
    |> Enum.group_by(fn {use, _recency} ->
      use.item.name |> String.trim() |> String.downcase()
    end)
    |> Enum.map(fn {_key, [{%{item: latest, currency: currency}, recency} | _older] = uses} ->
      {%{
         name: String.trim(latest.name),
         count: length(uses),
         quantity: latest.quantity,
         unit: latest.unit,
         unit_price: latest.unit_price,
         currency: currency,
         vat_rate: latest.vat_rate
       }, recency}
    end)
    |> Enum.sort_by(fn {item, recency} -> {-item.count, recency} end)
    |> Enum.take(@limit)
    |> Enum.map(fn {item, _recency} -> item end)
  end

  defp filter_counterparty(query, nil), do: query

  defp filter_counterparty(query, counterparty_id), do: Ash.Query.filter(query, counterparty_id == ^counterparty_id)
end
