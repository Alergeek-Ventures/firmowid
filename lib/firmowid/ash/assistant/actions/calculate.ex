defmodule Firmowid.Ash.Assistant.Actions.Calculate do
  @moduledoc """
  Deterministic decimal arithmetic tool for the assistant.
  """

  use Jido.Action,
    name: "calculate",
    description: "Wykonuje działania matematyczne na liczbach dziesiętnych.",
    schema: [
      numbers: [type: {:list, {:or, [:string, :integer, :float]}}, required: true],
      operation: [type: :string, required: true]
    ],
    output_schema: [
      result: [type: :string, required: true]
    ]

  alias Firmowid.Ash.Assistant.Actions.SearchSupport

  @impl true
  def run(%{numbers: [first | rest], operation: operation}, _context) when operation in ["+", "-", "*", "/"] do
    with {:ok, numbers} <- parse_decimals([first | rest]) do
      result =
        case {operation, numbers} do
          {"+", numbers} ->
            Enum.reduce(numbers, &Decimal.add/2)

          {"-", numbers} ->
            Enum.reduce(numbers, fn elem, acc -> Decimal.sub(acc, elem) end)

          {"*", numbers} ->
            Enum.reduce(numbers, &Decimal.mult/2)

          {"/", numbers} ->
            if Enum.any?(tl(numbers), &Decimal.equal?(&1, 0)) do
              {:error, "Dzielenie przez zero"}
            else
              Enum.reduce(numbers, fn elem, acc -> Decimal.div(acc, elem) end)
            end
        end

      case result do
        {:error, _reason} = error -> error
        decimal -> {:ok, %{result: Decimal.to_string(decimal)}}
      end
    end
  end

  def run(_params, _context), do: {:error, "Podaj niepustą listę liczb i poprawne działanie."}

  defp parse_decimals(numbers) do
    numbers
    |> Enum.reduce_while({:ok, []}, fn number, {:ok, acc} ->
      case SearchSupport.parse_decimal(number) do
        {:ok, %Decimal{} = decimal} -> {:cont, {:ok, [decimal | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, decimals} -> {:ok, Enum.reverse(decimals)}
      error -> error
    end
  end
end
