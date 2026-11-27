defmodule Firmowid.Taxes.TaxYear.Actions.Forecast do
  @moduledoc """
  Forecasts a year's tax payments from its saved settings and the company's
  documents, read as the caller: VAT, CIT advances of a limited company, and
  PIT advances and ZUS contributions of the owners of a sole proprietorship or
  a civil partnership.

  VAT counts issued sales invoices on their sale date (art. 19a ust. 1 of the
  VAT Act) and cost invoices on the latest of their sale date, issue date and
  the day KSeF stored them, which is when they were received (art. 86 ust. 10
  and 10b). Cash accounting moves both to the days of the linked bank
  transfers: a sales invoice marked with it (art. 21 ust. 1), and every cost
  invoice once the company uses it (art. 86 ust. 10e). An invoice in another
  currency converts at its NBP rate.

  Simplifications:

    * a correction counts the change it makes on its issue date, under cash
      accounting too, and a sales correction whose invoice Firmowid does not
      have is left out, as the state before it is unknown;
    * an invoice read from a document counts as received when issued;
    * a cash accounting invoice counts only once paid: neither the 180 days
      after which a sale to a non-taxpayer counts anyway (art. 21 ust. 1
      pkt 2), nor a payment of an invoice older than the year before, nor the
      size of a transfer in another currency than the invoice;
    * input VAT is deducted in full, and the VAT of sales outside invoices, reverse-charge
      purchases and bad debt relief are not counted;
    * a skipped incoming transfer is revenue, at its gross amount, only when the
      analysis put it into a revenue category, and a skipped outgoing transfer
      is a cost only when the analysis put it into
      a category other than taxes and the catch-all `other` (see `Firmowid.Taxes.Forecast.IncomeEntries`);
    * a VAT surplus is carried forward and lowered by the refunds from a tax
      office (incoming skipped transfers titled with VAT), not refunded itself.

  CIT advances (see `Firmowid.Taxes.Forecast.Cit`) are forecast for a limited
  company whose year has a CIT rate and advance form, from the income entries
  of `Firmowid.Taxes.Forecast.IncomeEntries`, also when the company is outside
  VAT. For each partner of a sole proprietorship or a civil partnership the
  same entries, multiplied by their profit share, give their ZUS contributions
  (`Firmowid.Taxes.Forecast.Zus`) and PIT advances
  (`Firmowid.Taxes.Forecast.Pit`), which deduct them. Order: VAT, CIT, PIT, ZUS.
  The VAT entries are built by `Firmowid.Taxes.Forecast.VatEntries`.

  Documents and transfers are read from the year before as well: cash
  accounting, the previous month's health contribution base in January and
  Mały ZUS Plus need them; every calculation ignores entries outside its dates.

  Only when the documents explained less than half of what was paid for the last three periods of
  a kind, a forecast that is not past due, starts within the horizon (see below) and whose amount
  is under half of the typical payment (the median of those three payments, read from the
  transfers to the tax micro-account and to ZUS) takes that payment instead, and its `details` get
  `documents_amount` and `typical_payment` (see `Firmowid.Taxes.Forecast.PaymentHistory`). It
  covers companies that do not issue their invoices in Firmowid. The forecasts of those periods
  are computed unadjusted, from the year before as well when they fall in it. VAT and CIT payments
  always count; PIT and ZUS only for a sole proprietorship with one partner, who pays from the
  company account.

  Cost invoices without a VAT amount bring none to VAT and count at their gross
  amount in CIT costs, so each forecast tells how many its period has.

  The period that is still running would count only the documents dated so far,
  and the periods ahead none, so the entries get the typical rest of the running
  month and the typical month for each later one from the three months before
  (`Firmowid.Taxes.Forecast.Projection`), up to the horizon of
  `Firmowid.Taxes.Forecast.Period.horizon/1` (the end of the second month after
  today's): until the end of the VAT period that contains it, and for CIT and PIT
  until the end of the advance period that contains it. The horizon may reach the
  next year, whose forecast then projects too. An owner's entries are projected
  before they are multiplied by the profit share, and ZUS reads the same entries
  as PIT, so the contributions PIT deducts see every month of its period. Periods that ended count the
  booked documents only. The cumulative figures of the periods after the running
  one build on it, so they include its projection. `details` tells how
  much of each figure is projected: `projected_output_vat` and
  `projected_input_vat` of VAT, `projected_revenue` and `projected_costs` of CIT
  and PIT, zero where nothing is. "Today" is a private argument, the day in
  Poland unless a caller passes it.
  """
  use Ash.Resource.Actions.Implementation

  alias Firmowid.Core
  alias Firmowid.Scope
  alias Firmowid.Taxes
  alias Firmowid.Taxes.Forecast.Cit
  alias Firmowid.Taxes.Forecast.Documents
  alias Firmowid.Taxes.Forecast.Income
  alias Firmowid.Taxes.Forecast.IncomeEntries
  alias Firmowid.Taxes.Forecast.PaymentHistory
  alias Firmowid.Taxes.Forecast.Payments
  alias Firmowid.Taxes.Forecast.Period
  alias Firmowid.Taxes.Forecast.Pit
  alias Firmowid.Taxes.Forecast.Projection
  alias Firmowid.Taxes.Forecast.Vat
  alias Firmowid.Taxes.Forecast.VatEntries
  alias Firmowid.Taxes.Forecast.Zus

  @impl true
  def run(input, _opts, context) do
    year = input.arguments.year
    today = input.arguments.today
    opts = Ash.Context.to_opts(context)

    with {:ok, tax_year} <- get_tax_year(year, opts),
         {:ok, organization} <- Core.get_organization(context.tenant, opts),
         {:ok, forecasts} <- unadjusted(tax_year, organization, today, context, opts) do
      adjust_to_payments(forecasts, year, organization, tax_year, today, context, opts)
    end
  end

  defp get_tax_year(year, opts) do
    Taxes.get_tax_year(
      year,
      opts |> Keyword.put(:not_found_error?, false) |> Keyword.put(:load, [:partners])
    )
  end

  # A year without a saved tax year has no forecasts.
  defp unadjusted(nil, _organization, _today, _context, _opts), do: {:ok, []}

  defp unadjusted(tax_year, organization, today, context, opts) do
    documents = Documents.read(tax_year.year, opts)
    scope = %Scope{actor: context.actor, tenant: context.tenant}

    {:ok,
     vat(tax_year, organization, documents, today) ++
       cit(tax_year, organization, documents, scope, today) ++
       owners(tax_year, organization, documents, scope, today)}
  end

  defp adjust_to_payments([], _year, _organization, _tax_year, _today, _context, _opts), do: {:ok, []}

  defp adjust_to_payments(forecasts, year, organization, tax_year, today, context, opts) do
    owner_pays? =
      organization.legal_form == :sole_proprietorship and match?([_], tax_year.partners)

    case Payments.history(
           Date.new!(year - 1, 1, 1),
           Date.new!(year + 1, 12, 31),
           owner_pays?,
           opts
         ) do
      [] ->
        {:ok, forecasts}

      payments ->
        with {:ok, reference} <- reference(forecasts, year, organization, today, context, opts) do
          {:ok, PaymentHistory.adjust(forecasts, reference, payments, today)}
        end
    end
  end

  # The forecasts themselves plus those of the other year the reference periods fall in.
  defp reference(forecasts, year, organization, today, context, opts) do
    other_years = PaymentHistory.reference_years(forecasts, today) -- [year]

    Enum.reduce_while(other_years, {:ok, forecasts}, fn other_year, {:ok, acc} ->
      with {:ok, tax_year} <- get_tax_year(other_year, opts),
           {:ok, other} <- unadjusted(tax_year, organization, today, context, opts) do
        {:cont, {:ok, acc ++ other}}
      else
        error -> {:halt, error}
      end
    end)
  end

  # The years from today's to the horizon's have periods that are running or ahead; the entries get
  # the typical rest of them.
  defp project(entries, year, today, until) do
    if year in today.year..Period.horizon(today).year,
      do: entries ++ Projection.project(entries, today, until),
      else: entries
  end

  defp vat(%{vat_period: frequency, year: year}, %{is_vat_payer: true} = organization, documents, today)
       when frequency != nil do
    without_vat = Enum.reject(documents.cost_invoices, & &1.vat_amount)

    documents.sales_invoices
    |> VatEntries.build(documents.cost_invoices, organization.is_cash_account)
    |> Kernel.++(VatEntries.refunds(documents.skipped_transactions))
    |> project(year, today, Period.last_day(frequency, Period.horizon(today)))
    |> Vat.forecast(frequency, year)
    |> Enum.map(fn forecast ->
      missing =
        Enum.count(
          without_vat,
          &(VatEntries.cost_date(&1) in Date.range(forecast.period_start, forecast.period_end))
        )

      put_in(forecast.details[:cost_invoices_without_vat], missing)
    end)
  end

  defp vat(_tax_year, _organization, _documents, _today), do: []

  # The simplified form pays a fixed amount that Firmowid does not know.
  defp cit(%{cit_advances: :simplified}, _organization, _documents, _scope, _today), do: []

  defp cit(
         %{cit_rate: rate, cit_advances: advances, year: year},
         %{legal_form: :limited_company} = organization,
         documents,
         scope,
         today
       )
       when rate != nil and advances != nil do
    entries =
      documents
      |> Documents.income_entries(organization, scope)
      |> project(year, today, Period.last_day(advances, Period.horizon(today)))

    without_vat =
      if organization.is_vat_payer,
        do:
          for(
            %{vat_amount: nil} = invoice <- documents.cost_invoices,
            do: IncomeEntries.cost_date(invoice)
          ),
        else: []

    entries
    |> Cit.forecast(%{cit_rate: rate, cit_advances: advances}, year)
    |> Enum.map(fn forecast ->
      missing =
        Enum.count(without_vat, &(&1 in Date.range(Date.new!(year, 1, 1), forecast.period_end)))

      put_in(forecast.details[:cost_invoices_without_vat], missing)
    end)
  end

  defp cit(_tax_year, _organization, _documents, _scope, _today), do: []

  # The owners' PIT advances and ZUS contributions, all PIT first. The company's entries are
  # projected before the owner's share is taken, to the end of the PIT advance period that contains
  # the horizon: the contributions PIT deducts need the income of every month of that period.
  defp owners(
         %{partners: [_ | _] = partners, accident_insurance_rate: accident_rate, year: year},
         %{legal_form: legal_form} = organization,
         documents,
         scope,
         today
       )
       when legal_form in [:sole_proprietorship, :civil_partnership] do
    entries = Documents.income_entries(documents, organization, scope)

    {pit, zus} =
      partners
      |> Enum.map(fn partner ->
        partner_entries =
          entries
          |> project(year, today, Period.last_day(partner.pit_advances, Period.horizon(today)))
          |> Income.scale(partner.profit_share)

        contributions = Zus.contributions(partner_entries, partner, accident_rate, year)

        {Pit.forecast(partner_entries, partner, contributions, partner.member_id, year),
         Zus.forecast(contributions, partner.member_id)}
      end)
      |> Enum.unzip()

    Enum.concat(pit) ++ Enum.concat(zus)
  end

  defp owners(_tax_year, _organization, _documents, _scope, _today), do: []
end
