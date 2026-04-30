defmodule Firmowid.Ash.Assistant.Actions.NormalizeToPln do
  @moduledoc """
  Currency normalization tool for invoice matching.
  """

  use Jido.Action,
    name: "normalize_to_pln",
    description: "Przelicza kwotę w dowolnej walucie na PLN dla wskazanej daty.",
    schema: [
      amount: [type: {:or, [:string, :integer, :float]}, required: true],
      currency: [type: :string, required: true],
      date: [type: :string, required: true]
    ],
    output_schema: [
      result: [type: :string, required: true]
    ]

  alias Firmowid.Ash.Assistant.Actions.SearchSupport
  alias Firmowid.Ash.Currencies.Converter

  @impl true
  def run(%{amount: amount, currency: currency, date: date}, _context) do
    with {:ok, parsed_date} <- Date.from_iso8601(date),
         {:ok, parsed_amount} <- SearchSupport.parse_decimal(amount) do
      normalized = Converter.normalize_amount_to_pln(parsed_amount, currency, parsed_date)
      {:ok, %{result: Decimal.to_string(normalized)}}
    end
  end
end
