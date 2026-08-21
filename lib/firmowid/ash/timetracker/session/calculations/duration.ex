defmodule Firmowid.Ash.Timetracker.Session.Calculations.Duration do
  @moduledoc """
  Session duration in seconds — elapsed time for a running session, or the
  distance between `end_datetime` and `start_datetime` otherwise.
  """
  use Ash.Resource.Calculation

  @doc """
  Builds the duration expression used for loading, filtering, and sorting.
  """
  @spec expression(keyword(), Ash.Resource.Calculation.Context.t()) :: any()
  def expression(_opts, _context) do
    expr(
      if is_nil(end_datetime) do
        fragment("EXTRACT(EPOCH FROM (NOW() - ?))::integer", start_datetime)
      else
        fragment("EXTRACT(EPOCH FROM (? - ?))::integer", end_datetime, start_datetime)
      end
    )
  end
end
