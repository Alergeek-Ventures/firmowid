defmodule Firmowid.Ash.Invoicing.Calculations.EffectiveSnapshot do
  @moduledoc """
  Returns the effective snapshot for a sales invoice — the latest correction
  if one exists, otherwise the invoice itself.

  Module calc because it returns a full struct and needs relationship traversal.
  """
  use Ash.Resource.Calculation

  @impl true
  def load(_query, _opts, _context), do: [:latest_correction]

  @impl true
  def calculate(records, _opts, _context) do
    Enum.map(records, fn record ->
      case record.latest_correction do
        %{__struct__: _} = correction -> correction
        _ -> record
      end
    end)
  end
end
