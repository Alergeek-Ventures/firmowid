defmodule Firmowid.Taxes.TaxYear.Actions.SuggestSettings do
  @moduledoc """
  Suggests a tax year's settings from the company's transfers to its tax
  micro-account (mikrorachunek podatkowy), whose number always holds the NBP
  part `10100071222`.

  Banks show such a transfer's period and form symbol in its title, e.g.
  `1234567890 26M04 VAT` or `/OKR/26K01/SFP/PPL/`: `M` is a month and `K` a
  quarter. Income tax advances use `PIT` (tax scale), `PPL` (flat tax) and `PPE`
  (lump sum), or the annual form's symbol (PIT-36, PIT-36L, PIT-28). Annual
  settlements (`R` periods) are left out: they say nothing of how advances are
  paid. PIT-4 and other withholding forms are the company paying for its
  employees, so they are left out too.

  Only transfers for periods of the year count; a year without them falls back
  to the year before. Each suggestion carries when the bank sync brought its
  latest transfer, so a saved year can tell whether new transfers contradict it.
  Nothing here is binding: the suggestions only prefill what an admin confirms.
  """
  use Ash.Resource.Actions.Implementation

  alias Firmowid.Finances.AccountNumber
  alias Firmowid.Finances.Transaction

  require Ash.Query

  @tax_account "10100071222"

  @period ~r/(?<!\d)(\d{2})([MK])\d{2}(?!\d)/
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
      Transaction
      |> Ash.Query.filter(
        contains(
          fragment("regexp_replace(?, '[^0-9]', '', 'g')", creditor_account),
          ^@tax_account
        ) and
          booking_date >= ^Date.new!(year - 1, 1, 1) and
          booking_date <= ^Date.new!(year + 1, 12, 31)
      )
      |> Ash.Query.select([:creditor_account, :remittance_information_unstructured, :inserted_at])
      |> Ash.read!(Ash.Context.to_opts(context))
      |> Enum.filter(&tax_account?(&1.creditor_account))
      |> Enum.flat_map(&parse/1)

    {:ok, suggest(transfers, year)}
  end

  # The query narrows by the digits, as accounts may be written with spaces or dashes;
  # the account's place in the number decides, as in the analysis of public levies.
  defp tax_account?(account) do
    match?(
      <<_check::binary-size(2), @tax_account, _rest::binary-size(13)>>,
      AccountNumber.key(account)
    )
  end

  defp parse(%Transaction{remittance_information_unstructured: nil}), do: []

  defp parse(%Transaction{remittance_information_unstructured: title, inserted_at: synced_at}) do
    with [_period, year, kind] <- Regex.run(@period, title),
         [_symbol, symbol] <- Regex.run(@symbol, title) do
      symbol = String.upcase(symbol)

      [
        %{
          year: 2000 + String.to_integer(year),
          period: period(kind, symbol),
          symbol: symbol,
          tax: tax(symbol),
          synced_at: synced_at
        }
      ]
    else
      nil -> []
    end
  end

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
