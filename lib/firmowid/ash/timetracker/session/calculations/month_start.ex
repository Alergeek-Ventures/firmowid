defmodule Firmowid.Ash.Timetracker.Session.Calculations.MonthStart do
  @moduledoc """
  First day of the month a session belongs to (truncated `start_datetime`).
  """
  use Ash.Resource.Calculation

  @doc """
  Builds the month truncation expression.
  """
  @spec expression(keyword(), Ash.Resource.Calculation.Context.t()) :: any()
  def expression(_opts, _context) do
    expr(fragment("date_trunc('month', ?)", start_datetime))
  end
end
