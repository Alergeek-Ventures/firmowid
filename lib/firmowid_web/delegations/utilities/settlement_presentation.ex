defmodule FirmowidWeb.Delegations.Utilities.SettlementPresentation do
  @moduledoc "Pure presentation helpers for delegation settlement expenses."

  use Gettext, backend: Firmowid.Gettext

  @type expense_kind :: :transport | :accommodation | :other

  @spec expenses_for([map()], expense_kind()) :: [map()]
  def expenses_for(expenses, kind), do: Enum.filter(expenses, &(&1.kind == kind))

  @spec sum([map()]) :: Money.t() | nil
  def sum(expenses) do
    amounts = Enum.map(expenses, &settlement_amount/1)

    if Enum.all?(amounts, &(Money.to_currency_code(&1) == :PLN)) do
      Enum.reduce(amounts, Money.new(:PLN, 0), &Money.add!/2)
    end
  end

  @doc "Returns the amount used in the delegation settlement summary."
  @spec settlement_amount(map()) :: Money.t()
  def settlement_amount(%{settlement_amount: %Money{} = amount}), do: amount
  def settlement_amount(expense), do: expense.expense_amount

  @spec settlement_balance(Money.t() | nil, Money.t()) :: {String.t(), Money.t() | nil}
  def settlement_balance(nil, _advance), do: {gettext("Amount due"), nil}

  def settlement_balance(total, advance) do
    if Money.compare(total, advance) in [:gt, :eq],
      do: {gettext("Amount due"), Money.sub!(total, advance)},
      else: {gettext("Payout reduction"), Money.sub!(advance, total)}
  end

  @spec transport_label(String.t()) :: String.t()
  def transport_label("railway"), do: pgettext("means of transport", "Train")
  def transport_label("airplane"), do: pgettext("means of transport", "Airplane")
  def transport_label("bus"), do: pgettext("means of transport", "Bus")
  def transport_label("other"), do: pgettext("means of transport", "Other")

  @spec transport_options() :: [{String.t(), String.t()}]
  def transport_options, do: Enum.map(~w(railway airplane bus other), &{transport_label(&1), &1})

  @spec present_value(term()) :: term()
  def present_value(value) when value in [nil, ""], do: "—"
  def present_value(value), do: value

  @spec format_date(Date.t() | nil) :: String.t()
  def format_date(nil), do: "—"
  def format_date(date), do: Calendar.strftime(date, "%d.%m.%Y")

  @spec roman_numeral(pos_integer()) :: String.t()
  def roman_numeral(number) do
    [
      {1000, "M"},
      {900, "CM"},
      {500, "D"},
      {400, "CD"},
      {100, "C"},
      {90, "XC"},
      {50, "L"},
      {40, "XL"},
      {10, "X"},
      {9, "IX"},
      {5, "V"},
      {4, "IV"},
      {1, "I"}
    ]
    |> Enum.reduce({number, ""}, fn {value, numeral}, {remainder, result} ->
      count = div(remainder, value)
      {remainder - count * value, result <> String.duplicate(numeral, count)}
    end)
    |> elem(1)
  end
end
