defmodule Firmowid.Ash.Finances.Transaction.Calculations.CounterpartyDisplayName do
  @moduledoc "Returns a useful counterparty name or the Polish transaction fallback."

  use Ash.Resource.Calculation

  @impl true
  def load(_query, _opts, _context), do: [:counterparty_name]

  @impl true
  def calculate(records, _opts, _context) do
    Enum.map(records, fn transaction ->
      case transaction.counterparty_name do
        value when is_binary(value) ->
          trimmed = String.trim(value)

          if trimmed != "" and String.upcase(trimmed) != "N/A",
            do: trimmed,
            else: "Transakcja bankowa"

        _ ->
          "Transakcja bankowa"
      end
    end)
  end
end
