defmodule Firmowid.Taxes.Forecast.VatEntries do
  @moduledoc """
  Turns the company's invoices into the entries VAT is computed from
  (`Firmowid.Taxes.Forecast.Vat`): the VAT of each document in PLN, on the day
  it counts.

  Sales invoices count on their sale date, a correction as the change it makes
  on its issue date. Cost invoices count on the latest of their sale date,
  issue date and the day KSeF stored them. Cash accounting moves an invoice to
  the days of its linked bank transfers; an invoice in another currency
  converts at its NBP rate. A refund from the tax office is an incoming skipped
  transfer. See `Firmowid.Taxes.TaxYear.Actions.Forecast` for
  the rules and simplifications.
  """

  alias Firmowid.Invoicing
  alias Firmowid.Taxes.Forecast.Corrections
  alias Firmowid.Taxes.Forecast.Vat

  @doc """
  Builds the entries of the sales invoices, and of the cost invoices with a
  known VAT amount, of a VAT payer; `cash_accounting_costs?` is whether the
  company uses cash accounting for costs.
  """
  @spec build([struct()], [struct()], boolean()) :: [Vat.entry()]
  def build(sales_invoices, cost_invoices, cash_accounting_costs?) do
    Enum.flat_map(sales_invoices, &output_entries/1) ++
      Enum.flat_map(
        Enum.filter(cost_invoices, & &1.vat_amount),
        &input_entries(&1, cash_accounting_costs?)
      )
  end

  @doc """
  Builds the refund entries of the skipped transactions: incoming transfers from
  a tax office ("Urząd Skarbowy" as the debtor, in any letter case and with or
  without Polish diacritics) whose title mentions VAT, on their booking date.
  The tax office pays in PLN.
  """
  @spec refunds([struct()]) :: [Vat.entry()]
  def refunds(skipped_transactions) do
    for transaction <- skipped_transactions,
        Money.positive?(transaction.amount),
        tax_office?(transaction.debtor_name),
        vat_title?(transaction.remittance_information_unstructured) do
      %{
        side: :refund,
        amount: Money.to_decimal(transaction.amount),
        date: transaction.booking_date
      }
    end
  end

  defp tax_office?(name), do: String.contains?(plain(name), "urzad skarbowy")

  defp vat_title?(title), do: Regex.match?(~r/\bvat\b/, plain(title))

  # Lowercase without diacritics; ł has no decomposition.
  defp plain(nil), do: ""

  defp plain(text) do
    text
    |> String.downcase()
    |> :unicode.characters_to_nfd_binary()
    |> String.replace(~r/\p{Mn}/u, "")
    |> String.replace("ł", "l")
  end

  @doc "Returns the day a cost invoice's VAT counts on: the latest of its sale, issue and KSeF storage dates."
  @spec cost_date(struct()) :: Date.t()
  def cost_date(%{ksef_permanent_storage_date: nil} = invoice),
    do: Enum.max([invoice.sale_date, invoice.issue_date], Date)

  def cost_date(%{ksef_permanent_storage_date: stored_at} = invoice),
    do: Enum.max([invoice.sale_date, invoice.issue_date, NaiveDateTime.to_date(stored_at)], Date)

  defp output_entries(%{ksef_invoice_kind: :kor, corrected_invoice: nil}), do: []

  defp output_entries(%{ksef_invoice_kind: :kor} = correction) do
    change = Corrections.change(correction, :vat_value)

    [%{side: :output, amount: in_pln(change, correction), date: correction.issue_date}]
  end

  defp output_entries(invoice) do
    vat = invoice |> vat_value() |> in_pln(invoice)

    if invoice.is_cash_account,
      do: paid_entries(:output, vat, invoice.gross_value, invoice.currency, invoice.transactions),
      else: [%{side: :output, amount: vat, date: invoice.sale_date}]
  end

  # A linked correction is settled with its invoice and has no transfers of its own, and a
  # settlement invoice covered by its advances leaves nothing to pay.
  defp input_entries(%{original_invoice: nil, amount: amount} = invoice, true) do
    gross = amount |> Money.to_decimal() |> Decimal.abs()

    if Decimal.eq?(gross, 0) do
      input_entries(invoice, false)
    else
      currency = Atom.to_string(Money.to_currency_code(amount))
      paid_entries(:input, invoice.vat_amount, gross, currency, invoice.transactions)
    end
  end

  defp input_entries(invoice, _cash_accounting?),
    do: [%{side: :input, amount: invoice.vat_amount, date: cost_date(invoice)}]

  # A transfer in another currency cannot be compared with the amount, so it pays all that is left.
  defp paid_entries(side, vat, gross, currency, transactions) do
    if Decimal.eq?(vat, 0) do
      []
    else
      payments =
        Enum.map(transactions, fn %{amount: paid, booking_date: date} ->
          if Atom.to_string(Money.to_currency_code(paid)) == currency,
            do: {date, paid |> Money.to_decimal() |> Decimal.abs()},
            else: {date, gross}
        end)

      for {date, part} <- Vat.on_payment(vat, gross, payments),
          do: %{side: side, amount: part, date: date}
    end
  end

  # An invoice without lines has no VAT to sum.
  defp vat_value(invoice), do: invoice.vat_value || Decimal.new(0)

  defp in_pln(vat, %{currency: "PLN"}), do: vat

  defp in_pln(vat, invoice) do
    if Decimal.eq?(vat, 0) do
      vat
    else
      %{rate: rate} =
        Invoicing.get_currency_rate(invoice) ||
          raise "NBP exchange rate unavailable for #{invoice.currency} on #{invoice.issue_date}"

      vat |> Decimal.mult(Decimal.from_float(rate)) |> Decimal.round(2)
    end
  end
end
