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

  # A date or a month, such as 01/10/2026, 2026-10-01 or 10.2026, and not dimensions,
  # versions or numbers such as 60-40-40, 1.2.34 or 2.5000.
  @day "(?:0?[1-9]|[12][0-9]|3[01])"
  @month "(?:0?[1-9]|1[0-2])"
  @year "(?:19|20)[0-9]{2}"
  @date ~r"\b(?:#{@day}[./-]#{@month}[./-]#{@year}|#{@year}-#{@month}-#{@day}|#{@month}[./]#{@year})\b"

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
  most recently used first. Items are told apart by their name without dates
  in any letter case, and each carries that name and the quantity, unit, net
  unit price, currency and VAT rate of its latest use. Corrections are left out:
  their lines say what changed, not what was sold.
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
      Enum.map(
        invoice.sales_invoice_items,
        &%{item: &1, name: general_name(&1.name), currency: invoice.currency}
      )
    end)
    |> Enum.reject(&(&1.name == ""))
    |> Enum.with_index()
    |> Enum.group_by(fn {use, _recency} -> String.downcase(use.name) end)
    |> Enum.map(fn {_key, [{%{item: latest, name: name, currency: currency}, recency} | _older] = uses} ->
      {%{
         name: name,
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

  # The item name without the dates and billing periods of one invoice, so that
  # "01/10/2026 - 31/10/2026 - Bookkeeping" and "01/11/2026 - 30/11/2026 - Bookkeeping"
  # are both "Bookkeeping". A name without dates, or of dates only, stays as it is.
  defp general_name(name) do
    general =
      name
      |> String.replace(@date, "")
      # Dashes that joined the removed dates, and those left at the ends.
      |> String.replace(~r/(?:\s*[-–—]\s*){2,}/u, " - ")
      |> String.replace(~r/^[\s\-–—:,]+|[\s\-–—:,]+$/u, "")
      |> String.replace(~r/\s+/u, " ")

    if general == "" or not Regex.match?(@date, name), do: String.trim(name), else: general
  end

  defp filter_counterparty(query, nil), do: query

  defp filter_counterparty(query, counterparty_id), do: Ash.Query.filter(query, counterparty_id == ^counterparty_id)
end
