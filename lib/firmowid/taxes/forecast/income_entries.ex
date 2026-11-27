defmodule Firmowid.Taxes.Forecast.IncomeEntries do
  @moduledoc """
  Turns the company's documents into the entries income taxes are computed
  from: revenue and costs in PLN, each on the day it counts, net of VAT where
  the document tells it (invoices) and gross where it does not (bank transfers).

  Revenue is the net value of issued sales invoices on their sale date; a
  correction counts the change it makes on its issue date, and one whose invoice
  Firmowid does not have is left out.

  Sales outside invoices (card terminal payouts, cash deposits) are incoming
  skipped transfers that the analysis put into a revenue category (`categories`,
  by transaction id; `:other_income` is not one, as it holds grants, refunds and
  interest), counted on their booking date and marked with `transfer?: true`.
  Transfers between the company's own accounts, entries tagged as internal or as
  taxes, and transfers from a tax office or ZUS never count, and neither does an
  unclassified one. Their amount is gross: a transfer carries VAT of an unknown
  rate, so the revenue of a VAT payer is overstated by it, and the VAT of such
  sales is not forecast.

  Costs are:

    * cost invoices on their sale date, without the VAT of a VAT payer; without
      a known VAT amount the gross amount counts, and a forecast should tell
      how many such invoices there are (corrections are separate documents with
      their own signed amounts);
    * transfers pinned to a salary, on the salary month;
    * skipped outgoing transfers on their booking date that the analysis put
      into a cost category other than taxes or `:other` (`categories`, by
      transaction id); `:other` is a catch-all for costs fitting no category,
      the way `:other_income` is for revenue. An unclassified transfer is not a
      cost, as most of such money is currency exchange, internal movements or
      dividends. Transfers between the
      company's own accounts and entries tagged as internal or as taxes never
      count, and neither do public levies: tax payments are never a cost, ZUS
      is one only for a limited company (payroll contributions; an owner's own
      are deducted separately).

  Amounts in another currency convert at the rate of their day, at the latest
  today's.
  """

  alias Firmowid.Analysis
  alias Firmowid.Analysis.OwnAccounts
  alias Firmowid.Core.Organization
  alias Firmowid.Currencies.Converter
  alias Firmowid.Taxes.Forecast.Corrections
  alias Firmowid.Taxes.Forecast.Income
  alias Firmowid.Taxes.Forecast.PublicOffices

  @revenue_categories Analysis.IndustryTemplate.all_categories(:income) -- [:other_income]

  @type documents :: %{
          sales_invoices: [struct()],
          cost_invoices: [struct()],
          salaries: [struct()],
          skipped_transactions: [struct()],
          categories: %{Ash.UUID.t() => atom()}
        }

  @doc """
  Builds the entries of `documents`, read with the amounts and relations the
  mapping needs, for an organization with the given legal form and VAT status.
  `categories` holds the analysis category of each classified skipped transaction.
  """
  @spec build(documents(), Organization.t(), OwnAccounts.t()) :: [Income.entry()]
  def build(documents, organization, own_accounts) do
    Enum.flat_map(documents.sales_invoices, &revenue/1) ++
      Enum.flat_map(documents.cost_invoices, &invoice_cost(&1, organization.is_vat_payer)) ++
      Enum.flat_map(documents.salaries, &salary_cost/1) ++
      for(
        transaction <- documents.skipped_transactions,
        revenue?(transaction, own_accounts, documents.categories),
        entry <- transfer_revenue(transaction),
        do: entry
      ) ++
      for(
        transaction <- documents.skipped_transactions,
        cost?(transaction, organization.legal_form, own_accounts, documents.categories),
        entry <- transfer_cost(transaction, transaction.booking_date),
        do: entry
      )
  end

  @doc "Returns the day a cost invoice counts on: its sale date, or its issue date when it has none."
  @spec cost_date(struct()) :: Date.t()
  def cost_date(invoice), do: invoice.sale_date || invoice.issue_date

  defp revenue(%{ksef_invoice_kind: :kor, corrected_invoice: nil}), do: []

  defp revenue(%{ksef_invoice_kind: :kor} = correction) do
    change = Corrections.change(correction, :net_value)

    entry(
      :revenue,
      to_pln(change, correction.currency, correction.issue_date),
      correction.issue_date
    )
  end

  defp revenue(invoice) do
    net = invoice.net_value || Decimal.new(0)

    entry(:revenue, to_pln(net, invoice.currency, invoice.sale_date), invoice.sale_date)
  end

  # A cost invoice's amount is negative, a refund's positive; its VAT is already in PLN.
  defp invoice_cost(%{amount: amount} = invoice, vat_payer?) do
    date = cost_date(invoice)
    gross = amount |> Money.to_decimal() |> Decimal.negate() |> to_pln(currency(amount), date)

    cost =
      if vat_payer? and invoice.vat_amount,
        do: Decimal.sub(gross, invoice.vat_amount),
        else: gross

    entry(:cost, cost, date)
  end

  defp salary_cost(transaction), do: transfer_cost(transaction, transaction.salary_month)

  defp transfer_cost(transaction, date), do: entry(:cost, transfer_pln(transaction), date)

  defp transfer_revenue(transaction) do
    for entry <- entry(:revenue, transfer_pln(transaction), transaction.booking_date),
        do: Map.put(entry, :transfer?, true)
  end

  defp transfer_pln(%{amount: amount} = transaction) do
    amount
    |> Money.to_decimal()
    |> Decimal.abs()
    |> to_pln(currency(amount), transaction.booking_date)
  end

  defp revenue?(transaction, own_accounts, categories) do
    Money.positive?(transaction.amount) and
      not OwnAccounts.transfer?(transaction, own_accounts) and
      not Enum.any?(transaction.entity_tags, &(&1.kind in [:internal, :taxes])) and
      not PublicOffices.tax_office?(transaction.debtor_name) and
      not PublicOffices.zus?(transaction.debtor_name) and
      Map.get(categories, transaction.id) in @revenue_categories
  end

  defp cost?(transaction, legal_form, own_accounts, categories) do
    Money.negative?(transaction.amount) and
      not OwnAccounts.transfer?(transaction, own_accounts) and
      not Enum.any?(transaction.entity_tags, &(&1.kind in [:internal, :taxes])) and
      case Analysis.public_levy(transaction) do
        nil -> cost_category?(Map.get(categories, transaction.id))
        :payroll -> legal_form == :limited_company
        :taxes -> false
      end
  end

  defp cost_category?(nil), do: false
  defp cost_category?(:taxes), do: false
  defp cost_category?(:other), do: false
  defp cost_category?(_category), do: true

  defp entry(side, amount, date) do
    if Decimal.eq?(amount, 0), do: [], else: [%{side: side, amount: amount, date: date}]
  end

  defp currency(%Money{} = amount), do: amount |> Money.to_currency_code() |> Atom.to_string()

  defp to_pln(amount, "PLN", _date), do: amount

  defp to_pln(amount, currency, date) do
    if Decimal.eq?(amount, 0),
      do: amount,
      else:
        Converter.normalize_amount_to_pln(
          amount,
          currency,
          Enum.min([date, Date.utc_today()], Date)
        )
  end
end
