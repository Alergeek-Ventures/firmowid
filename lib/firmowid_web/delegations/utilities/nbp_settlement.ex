defmodule FirmowidWeb.Delegations.Utilities.NbpSettlement do
  @moduledoc "Calculates NBP-based settlement amounts for delegation expense forms."

  alias Firmowid.Ash.Currencies.NbpApiClient

  @doc "Calculates a settlement amount in the requested target currency."
  @spec calculate(map(), map(), String.t(), String.t()) ::
          {:ok, map()} | {:error, :rate_unavailable}
  def calculate(expense_forms, expense_currencies, expense_id, target_currency) do
    with true <- target_currency == "PLN" or NbpApiClient.supported_currency?(target_currency),
         %{expense: form} <- Map.fetch!(expense_forms, expense_id),
         %Money{} = amount <- form[:expense_amount].value,
         source_currency = Map.get(expense_currencies, expense_id, "PLN"),
         date = Date.utc_today(),
         {:ok, source_rate} <- nbp_rate(source_currency, date),
         {:ok, target_rate} <- nbp_rate(target_currency, date) do
      rate = source_rate |> Decimal.div(target_rate) |> Decimal.round(4)

      {:ok,
       %{
         amount: Money.new(target_currency, Decimal.mult(Money.to_decimal(amount), rate)),
         rate: rate,
         date: date
       }}
    else
      _ -> {:error, :rate_unavailable}
    end
  end

  defp nbp_rate("PLN", _date), do: {:ok, Decimal.new(1)}

  defp nbp_rate(currency, date) do
    case NbpApiClient.get_exchange_rate(currency, date) do
      {:ok, %{rate: rate}} -> {:ok, Decimal.from_float(rate)}
      {:error, _reason} -> {:error, :rate_unavailable}
    end
  end
end
