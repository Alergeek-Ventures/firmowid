defmodule Firmowid.Ash.Timetracker.Session.Calculations.Lockdown do
  @moduledoc """
  Whether an hours record has been submitted for the session's month,
  locking edits.
  """
  use Ash.Resource.Calculation

  @doc """
  Builds the lockdown expression based on the `hours_records` relationship.
  """
  @spec expression(keyword(), Ash.Resource.Calculation.Context.t()) :: any()
  def expression(_opts, _context) do
    expr(exists(hours_records, true))
  end
end
