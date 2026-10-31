defmodule Firmowid.Timetracker.Session.Calculations.Duration do
  @moduledoc """
  Session duration in seconds — elapsed time for a running session, or the
  distance between `end_datetime` and `start_datetime` otherwise.
  """
  use Ash.Resource.Calculation

  alias Firmowid.Timetracker.Workers.StopSessionWorker

  @doc """
  Builds the duration expression used for loading, filtering, and sorting.
  """
  @spec expression(keyword(), Ash.Resource.Calculation.Context.t()) :: any()
  def expression(_opts, _context) do
    max_running_seconds = StopSessionWorker.max_running_seconds()

    expr(
      if is_nil(end_datetime) do
        fragment(
          "GREATEST(0, LEAST(EXTRACT(EPOCH FROM (timezone('UTC', NOW()) - ?))::integer, ?, EXTRACT(EPOCH FROM (date_trunc('month', ?::timestamp) + interval '1 month' - interval '1 minute' - ?))::integer))",
          start_datetime,
          ^max_running_seconds,
          start_datetime,
          start_datetime
        )
      else
        fragment("EXTRACT(EPOCH FROM (? - ?))::integer", end_datetime, start_datetime)
      end
    )
  end
end
