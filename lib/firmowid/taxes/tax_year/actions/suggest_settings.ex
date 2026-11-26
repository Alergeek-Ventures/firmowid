defmodule Firmowid.Taxes.TaxYear.Actions.SuggestSettings do
  @moduledoc """
  Suggests a tax year's settings from the company's transfers to its tax
  micro-account (mikrorachunek podatkowy), whose number always holds the NBP
  part `10100071222`.

  Banks show such a transfer's period and form symbol in its title, e.g.
  `1234567890 26M04 VAT`, `/OKR/26K01/SFP/PPL/`, `CIT-8 K 01 2026` or
  `CIT-8 04 K - Kwartał 2025`: `M` is a month and `K` a quarter. Income tax
  advances use `PIT` (tax scale), `PPL` (flat tax) and `PPE` (lump sum), or the
  annual form's symbol (PIT-36, PIT-36L, PIT-28). Annual settlements (`R`
  periods) are left out: they say nothing of how advances are paid. PIT-4 and
  other withholding forms are the company paying for its employees, so they are
  left out too.

  Only transfers for periods of the year count; a year without them falls back
  to the year before. Each suggestion carries when the bank sync brought its
  latest transfer, so a saved year can tell whether new transfers contradict it.
  Nothing here is binding: the suggestions only prefill what an admin confirms.

  For a sole proprietorship whose saved year has its one owner, the owner's
  payments tell more (`Firmowid.Taxes.Forecast.Detection`): the ZUS transfers
  (to the payer's contribution account) suggest `social_insurance` and
  `voluntary_sickness`, and the lump-sum advances to the tax micro-account
  suggest `lump_sum_rate`, when the amounts equal what the forecast calculates
  for that setting. The value of a suggestion is an atom, a boolean (sickness)
  or a decimal (the rate in percent); `transfers` counts the payments that
  match.
  """
  use Ash.Resource.Actions.Implementation

  alias Firmowid.Analysis
  alias Firmowid.Core
  alias Firmowid.Finances.Transaction
  alias Firmowid.Scope
  alias Firmowid.Taxes
  alias Firmowid.Taxes.Forecast.Detection
  alias Firmowid.Taxes.Forecast.Documents
  alias Firmowid.Taxes.Forecast.Income
  alias Firmowid.Taxes.TaxYear

  require Ash.Query

  # The transfer form's own period field (`26M04`), and the period as banks write it out in a
  # title they compose (`M 04 2026`, `04 M - Miesiąc 2026`).
  @periods [
    ~r/(?<!\d)(?<year>\d{2})(?<kind>[MK])(?<number>\d{2})(?!\d)/,
    ~r/(?<![\w-])(?<kind>[MK])\s+(?<number>\d{2})\s+(?<year>\d{4})(?!\d)/,
    ~r/(?<!\d)(?<number>\d{2})\s+(?<kind>[MK])(?!\w).*?(?<!\d)(?<year>\d{4})(?!\d)/
  ]
  @symbol ~r/(?<![\w-])(VAT-7K|VAT-7D|VAT-7|VAT|PIT-36L|PIT-36|PIT-28|PPL|PPE|PIT|CIT-8|CIT)(?![\w-])/i

  @income_tax %{
    "PIT" => :tax_scale,
    "PIT-36" => :tax_scale,
    "PPL" => :flat_tax,
    "PIT-36L" => :flat_tax,
    "PPE" => :lump_sum,
    "PIT-28" => :lump_sum
  }

  @impl true
  def run(input, _opts, context) do
    year = input.arguments.year

    transfers =
      :taxes
      |> transfers_to(Date.new!(year - 1, 1, 1), Date.new!(year + 1, 12, 31), context)
      |> Enum.flat_map(&parse/1)

    with {:ok, owner} <- owner_suggestions(year, transfers, context) do
      {:ok, suggest(transfers, year) ++ owner}
    end
  end

  # The query narrows by the digits, as accounts may be written with spaces or dashes;
  # the recognition of the analysis of public levies decides.
  defp transfers_to(levy, first, last, context) do
    account = Analysis.public_levy_account(levy)

    Transaction
    |> Ash.Query.filter(
      contains(fragment("regexp_replace(?, '[^0-9]', '', 'g')", creditor_account), ^account) and
        booking_date >= ^first and booking_date <= ^last
    )
    |> Ash.Query.select([
      :creditor_account,
      :remittance_information_unstructured,
      :amount,
      :booking_date,
      :inserted_at
    ])
    |> Ash.read!(Ash.Context.to_opts(context))
    |> Enum.filter(&(Analysis.public_levy(&1) == levy))
  end

  # The owner of a sole proprietorship pays from the company account, and a saved year with its one
  # owner tells which settings the payments are compared with. The documents behind the entries are
  # read only when two payments of a kind could match.
  defp owner_suggestions(year, transfers, context) do
    opts = Ash.Context.to_opts(context)

    with {:ok, %TaxYear{partners: [owner]} = tax_year} <-
           Taxes.get_tax_year(
             year,
             opts |> Keyword.put(:not_found_error?, false) |> Keyword.put(:load, [:partners])
           ),
         {:ok, %{legal_form: :sole_proprietorship} = organization} <-
           Core.get_organization(context.tenant, opts) do
      zus_payments =
        :payroll
        |> transfers_to(Date.new!(year, 1, 1), Date.new!(year, 12, 31), context)
        |> Enum.map(&zus_payment/1)

      advances =
        if owner.income_tax == :lump_sum, do: lump_sum_payments(transfers, year), else: []

      if match?([_, _ | _], zus_payments) or match?([_, _ | _], advances),
        do: {:ok, detect(year, tax_year, owner, organization, zus_payments, advances, context)},
        else: {:ok, []}
    else
      {:ok, _not_applicable} -> {:ok, []}
      {:error, _error} = error -> error
    end
  end

  defp detect(year, tax_year, owner, organization, zus_payments, advances, context) do
    scope = %Scope{actor: context.actor, tenant: context.tenant}

    entries =
      year
      |> Documents.read(Ash.Context.to_opts(context))
      |> Documents.income_entries(organization, scope)
      |> Income.scale(owner.profit_share)

    zus = Detection.zus(entries, owner, tax_year.accident_insurance_rate, year, zus_payments)
    # The advances deduct the contributions the payments confirm, else the saved ones.
    contributions_owner =
      if zus,
        do: %{
          owner
          | social_insurance: zus.social_insurance,
            voluntary_sickness: zus.voluntary_sickness
        },
        else: owner

    rate =
      if advances != [],
        do:
          Detection.lump_sum_rate(
            entries,
            contributions_owner,
            tax_year.accident_insurance_rate,
            year,
            advances
          )

    zus_suggestions(zus, year) ++ rate_suggestions(rate, year)
  end

  defp zus_suggestions(nil, _year), do: []

  defp zus_suggestions(%{payments: payments} = zus, year) do
    for setting <- [:social_insurance, :voluntary_sickness],
        do: from_payments(setting, Map.fetch!(zus, setting), payments, year)
  end

  defp rate_suggestions(nil, _year), do: []

  defp rate_suggestions(%{payments: payments} = match, year),
    do: [from_payments(:lump_sum_rate, match.lump_sum_rate, payments, year)]

  defp from_payments(setting, value, payments, year) do
    %{
      setting: setting,
      value: value,
      year: year,
      transfers: length(payments),
      latest_transfer_at: payments |> Enum.map(& &1.synced_at) |> Enum.max(DateTime)
    }
  end

  # A transfer to the ZUS account is a payment of its booking month, for the month before.
  defp zus_payment(%Transaction{} = transaction) do
    %{
      date: transaction.booking_date,
      amount: paid(transaction),
      synced_at: transaction.inserted_at
    }
  end

  defp lump_sum_payments(transfers, year) do
    for %{tax: :pit, year: ^year, symbol: symbol} = transfer <- transfers,
        Map.fetch!(@income_tax, symbol) == :lump_sum do
      %{
        frequency: transfer.period,
        number: transfer.number,
        amount: transfer.amount,
        synced_at: transfer.synced_at
      }
    end
  end

  defp paid(%Transaction{amount: amount}), do: amount |> Money.to_decimal() |> Decimal.abs()

  defp parse(%Transaction{remittance_information_unstructured: nil}), do: []

  defp parse(%Transaction{remittance_information_unstructured: title, inserted_at: synced_at} = transaction) do
    with {year, kind, number} <- read_period(title),
         [_symbol, symbol] <- Regex.run(@symbol, title) do
      symbol = String.upcase(symbol)

      [
        %{
          year: year,
          period: period(kind, symbol),
          number: number,
          symbol: symbol,
          tax: tax(symbol),
          amount: paid(transaction),
          synced_at: synced_at
        }
      ]
    else
      nil -> []
    end
  end

  defp read_period(title) do
    Enum.find_value(@periods, fn pattern ->
      with %{"year" => year, "kind" => kind, "number" => number} <-
             Regex.named_captures(pattern, title) do
        {full_year(year), kind, String.to_integer(number)}
      end
    end)
  end

  defp full_year(<<year::binary-size(2)>>), do: 2000 + String.to_integer(year)
  defp full_year(year), do: String.to_integer(year)

  # The quarterly VAT returns name the quarter even where a title's period says otherwise.
  defp period(_kind, symbol) when symbol in ["VAT-7K", "VAT-7D"], do: :quarterly
  defp period("M", _symbol), do: :monthly
  defp period("K", _symbol), do: :quarterly

  defp tax("VAT" <> _rest), do: :vat
  defp tax("CIT" <> _rest), do: :cit
  defp tax(_income_tax), do: :pit

  defp suggest(transfers, year) do
    transfers
    |> Enum.group_by(& &1.tax)
    |> Enum.flat_map(fn {tax, tax_transfers} ->
      case Enum.filter(tax_transfers, &(&1.year == year)) do
        [] -> tax_transfers |> Enum.filter(&(&1.year == year - 1)) |> suggestions(tax)
        of_year -> suggestions(of_year, tax)
      end
    end)
  end

  defp suggestions([], _tax), do: []

  defp suggestions(transfers, :vat), do: [suggestion(:vat_period, transfers, & &1.period)]
  defp suggestions(transfers, :cit), do: [suggestion(:cit_advances, transfers, & &1.period)]

  defp suggestions(transfers, :pit) do
    [
      suggestion(:income_tax, transfers, &Map.fetch!(@income_tax, &1.symbol)),
      suggestion(:pit_advances, transfers, & &1.period)
    ]
  end

  # The most frequent value wins, so a single late or corrected transfer does not decide.
  defp suggestion(setting, transfers, value) do
    {value, _count} = transfers |> Enum.frequencies_by(value) |> Enum.max_by(&elem(&1, 1))

    %{
      setting: setting,
      value: value,
      year: hd(transfers).year,
      transfers: length(transfers),
      latest_transfer_at: transfers |> Enum.map(& &1.synced_at) |> Enum.max(DateTime)
    }
  end
end
