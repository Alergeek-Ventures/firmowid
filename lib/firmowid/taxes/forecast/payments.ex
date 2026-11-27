defmodule Firmowid.Taxes.Forecast.Payments do
  @moduledoc """
  Reads the company's payments of taxes and ZUS from its bank transfers: those to the tax
  micro-account (mikrorachunek podatkowy) and to the payer's ZUS contribution account, recognized
  by `Firmowid.Analysis.public_levy/1`.

  A tax transfer tells its kind and period in the title, as banks write it: `1234567890 26M04 VAT`,
  `/OKR/26K01/SFP/PPL/`, `CIT-8 K 01 2026`. `M` is a month and `K` a quarter. Annual settlements
  (`R` periods) and withholding forms (PIT-4 etc.) have no such title and are left out. A ZUS
  transfer has no period: one booked in a month pays the month before.

  `Firmowid.Taxes.TaxYear.Actions.SuggestSettings` reads the titles for the settings, and
  `Firmowid.Taxes.Forecast.PaymentHistory` compares the payments with a forecast.
  """
  alias Firmowid.Analysis
  alias Firmowid.Finances.Transaction

  require Ash.Query

  # The transfer form's own period field (`26M04`), and the period as banks write it out in a
  # title they compose (`M 04 2026`, `04 M - Miesiąc 2026`).
  @periods [
    ~r/(?<!\d)(?<year>\d{2})(?<kind>[MK])(?<number>\d{2})(?!\d)/,
    ~r/(?<![\w-])(?<kind>[MK])\s+(?<number>\d{2})\s+(?<year>\d{4})(?!\d)/,
    ~r/(?<!\d)(?<number>\d{2})\s+(?<kind>[MK])(?!\w).*?(?<!\d)(?<year>\d{4})(?!\d)/
  ]
  @symbol ~r/(?<![\w-])(VAT-7K|VAT-7D|VAT-7|VAT|PIT-36L|PIT-36|PIT-28|PPL|PPE|PIT|CIT-8|CIT)(?![\w-])/i

  @type payment :: %{
          kind: :vat | :cit | :pit | :zus,
          period: String.t(),
          amount: Decimal.t()
        }

  @doc """
  Returns the transfers to the accounts of `levy` (`:taxes` or `:payroll`) booked from `first` to
  `last`, read with the given Ash `opts`.
  """
  @spec transfers_to(:taxes | :payroll, Date.t(), Date.t(), keyword()) :: [Transaction.t()]
  def transfers_to(levy, first, last, opts) do
    account = Analysis.public_levy_account(levy)

    # The query narrows by the digits, as accounts may be written with spaces or dashes;
    # the recognition of the analysis of public levies decides.
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
    |> Ash.read!(opts)
    |> Enum.filter(&(Analysis.public_levy(&1) == levy))
  end

  @doc "Returns the booking date of the earliest transaction, nil without any."
  @spec history_start(keyword()) :: Date.t() | nil
  def history_start(opts), do: Ash.min!(Transaction, :booking_date, opts)

  @doc """
  Returns every payment of taxes (VAT, CIT, PIT) and ZUS booked from `first` to `last`, each for its
  kind and period key (`2026-11`, `2026-Q4`, as in `Firmowid.Taxes.Forecast.Period.of_year/2`).
  Whose payment it is stays unknown: with several owners the PIT and ZUS payments cannot be
  attributed, which `Firmowid.Taxes.Forecast.PaymentHistory` takes into account.
  """
  @spec history(Date.t(), Date.t(), keyword()) :: [payment()]
  def history(first, last, opts) do
    taxes =
      for transfer <- Enum.flat_map(transfers_to(:taxes, first, last, opts), &parse/1),
          do: %{kind: transfer.tax, period: key(transfer), amount: transfer.amount}

    zus =
      for transfer <- transfers_to(:payroll, first, last, opts) do
        payment = zus_payment(transfer)
        %{kind: :zus, period: previous_month(payment.date), amount: payment.amount}
      end

    taxes ++ zus
  end

  # A transfer to the ZUS account is a payment of its booking month, for the month before.
  @doc "Returns the date, the amount and the sync time of a transfer to the ZUS account."
  @spec zus_payment(Transaction.t()) :: %{
          date: Date.t(),
          amount: Decimal.t(),
          synced_at: DateTime.t()
        }
  def zus_payment(%Transaction{} = transaction) do
    %{
      date: transaction.booking_date,
      amount: paid(transaction),
      synced_at: transaction.inserted_at
    }
  end

  @doc """
  Reads the year, the period (`:monthly` or `:quarterly`), its number, the form symbol, the tax
  (`:vat`, `:cit` or `:pit`), the amount and the sync time from a tax transfer's title; `[]` for a
  title that tells no period or form.
  """
  @spec parse(Transaction.t()) :: [map()]
  def parse(%Transaction{remittance_information_unstructured: nil}), do: []

  def parse(%Transaction{remittance_information_unstructured: title, inserted_at: synced_at} = transaction) do
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

  defp paid(%Transaction{amount: amount}), do: amount |> Money.to_decimal() |> Decimal.abs()

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

  defp key(%{year: year, period: :monthly, number: month}), do: month_key(year, month)
  defp key(%{year: year, period: :quarterly, number: quarter}), do: "#{year}-Q#{quarter}"

  defp previous_month(date) do
    previous = date |> Date.beginning_of_month() |> Date.shift(month: -1)
    month_key(previous.year, previous.month)
  end

  defp month_key(year, month), do: "#{year}-#{String.pad_leading("#{month}", 2, "0")}"
end
