defmodule FirmowidWeb.Delegations.Utilities.SettlementPresentation do
  @moduledoc "Pure presentation helpers for delegation settlement expenses."

  @type expense_kind :: :transport | :accommodation | :other

  @spec expenses_for([map()], expense_kind()) :: [map()]
  def expenses_for(expenses, kind), do: Enum.filter(expenses, &(&1.kind == kind))

  @spec sum([map()]) :: Money.t()
  def sum(expenses),
    do: Enum.reduce(expenses, Money.new(:PLN, 0), fn expense, total -> Money.add!(total, settlement_amount(expense)) end)

  @doc "Returns the amount used in the delegation settlement summary."
  @spec settlement_amount(map()) :: Money.t()
  def settlement_amount(%{settlement_amount: %Money{} = amount}), do: amount
  def settlement_amount(expense), do: expense.expense_amount

  @spec settlement_balance(Money.t(), Money.t()) :: {String.t(), Money.t()}
  def settlement_balance(total, advance) do
    if Money.compare(total, advance) in [:gt, :eq],
      do: {"Do dopłaty", Money.sub!(total, advance)},
      else: {"Pomniejszenie wypłaty", Money.sub!(advance, total)}
  end

  @spec transport_label(String.t()) :: String.t()
  def transport_label("railway"), do: "Kolej"
  def transport_label("airplane"), do: "Samolot"
  def transport_label("bus"), do: "Autobus"
  def transport_label("other"), do: "Inne"

  @spec transport_options() :: [{String.t(), String.t()}]
  def transport_options, do: Enum.map(~w(railway airplane bus other), &{transport_label(&1), &1})

  @spec present_value(term()) :: term()
  def present_value(value) when value in [nil, ""], do: "—"
  def present_value(value), do: value

  @spec format_date(Date.t() | nil) :: String.t()
  def format_date(nil), do: "—"
  def format_date(date), do: Calendar.strftime(date, "%d.%m.%Y")

  @spec format_time(DateTime.t() | nil, String.t()) :: String.t()
  def format_time(nil, _timezone), do: "—"

  def format_time(datetime, timezone) do
    datetime |> DateTime.shift_zone!(timezone) |> Calendar.strftime("%H:%M")
  end

  @spec datetime_date(DateTime.t() | nil, String.t()) :: Date.t() | nil
  def datetime_date(nil, _timezone), do: nil

  def datetime_date(datetime, timezone), do: datetime |> DateTime.shift_zone!(timezone) |> DateTime.to_date()

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
