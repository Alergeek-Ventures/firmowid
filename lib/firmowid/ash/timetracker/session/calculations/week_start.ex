defmodule Firmowid.Ash.Timetracker.Session.Calculations.WeekStart do
  @moduledoc """
  Monday of the ISO week a session belongs to (truncated `start_datetime`).
  """
  use Ash.Resource.Calculation

  @doc """
  Builds the week truncation expression.
  """
  @spec expression(keyword(), Ash.Resource.Calculation.Context.t()) :: any()
  def expression(_opts, _context) do
    expr(fragment("date_trunc('week', ?)", start_datetime))
  end
end
