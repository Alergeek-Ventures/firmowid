defmodule FirmowidWeb.Delegations.Utilities.NbpSettlement do
  @moduledoc "Calculates NBP-based settlement amounts for delegation expense forms."

  alias Firmowid.Currencies.NbpApiClient

  @doc "Converts an expense amount to PLN at the NBP rate, dated with the table it comes from."
  @spec calculate(map(), map(), String.t()) :: {:ok, map()} | {:error, :rate_unavailable}
  def calculate(expense_forms, expense_currencies, expense_id) do
    with %{expense: form} <- Map.fetch!(expense_forms, expense_id),
         %Money{} = amount <- form[:expense_amount].value,
         source_currency = Map.get(expense_currencies, expense_id, "PLN"),
         {:ok, rate, date} <- nbp_rate(source_currency, Date.utc_today()) do
      rate = Decimal.round(rate, 4)

      {:ok,
       %{
         amount: Money.new("PLN", Decimal.mult(Money.to_decimal(amount), rate)),
         source_currency: source_currency,
         rate: rate,
         date: date
       }}
    else
      _ -> {:error, :rate_unavailable}
    end
  end

  defp nbp_rate("PLN", date), do: {:ok, Decimal.new(1), date}

  defp nbp_rate(currency, date) do
    case NbpApiClient.get_exchange_rate(currency, date) do
      {:ok, %{rate: rate, effective_date: effective_date}} ->
        {:ok, Decimal.from_float(rate), Date.from_iso8601!(effective_date)}

      {:error, _reason} ->
        {:error, :rate_unavailable}
    end
  end
end
