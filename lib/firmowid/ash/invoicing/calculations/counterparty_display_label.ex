defmodule Firmowid.Ash.Invoicing.Calculations.CounterpartyDisplayLabel do
  @moduledoc """
  Computes the display label for a counterparty.

  Priority:
  1. `display_name` if set
  2. `full_name` for companies
  3. `"given_name surname"` for individuals
  """
  use Ash.Resource.Calculation

  alias Firmowid.Ash.Invoicing.Counterparty

  @impl true
  def load(_query, _opts, _context), do: [:display_name, :full_name, :given_name, :surname, :type]

  @impl true
  def calculate(records, _opts, _context) do
    Enum.map(records, &Counterparty.display_label/1)
  end
end
