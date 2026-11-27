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

  alias Firmowid.Core
  alias Firmowid.Scope
  alias Firmowid.Taxes
  alias Firmowid.Taxes.Forecast.Detection
  alias Firmowid.Taxes.Forecast.Documents
  alias Firmowid.Taxes.Forecast.Income
  alias Firmowid.Taxes.Forecast.Payments
  alias Firmowid.Taxes.TaxYear

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
      |> Payments.transfers_to(
        Date.new!(year - 1, 1, 1),
        Date.new!(year + 1, 12, 31),
        Ash.Context.to_opts(context)
      )
      |> Enum.flat_map(&Payments.parse/1)

    with {:ok, owner} <- owner_suggestions(year, transfers, context) do
      {:ok, suggest(transfers, year) ++ owner}
    end
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
        |> Payments.transfers_to(Date.new!(year, 1, 1), Date.new!(year, 12, 31), opts)
        |> Enum.map(&Payments.zus_payment/1)

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
