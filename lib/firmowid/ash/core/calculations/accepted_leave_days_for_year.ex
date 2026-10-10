defmodule Firmowid.Ash.Core.Calculations.AcceptedLeaveDaysForYear do
  @moduledoc """
  Sums accepted leave/absence days for a user that fall within a given calendar year.

  Requests that span year boundaries only contribute the days that lie inside
  `[year-01-01, year-12-31]` — not the full request length.
  """
  use Ash.Resource.Calculation

  alias Firmowid.Ash.Timetracker.LeaveRequest

  @impl true
  def load(_query, _opts, _context), do: []

  @impl true
  def calculate(records, _opts, %{arguments: %{year: year}} = context) do
    year_start = Date.new!(year, 1, 1)
    year_end = Date.new!(year, 12, 31)
    opts = Ash.Context.to_opts(context)

    Enum.map(records, fn user ->
      %{user_id: user.id, status: :accepted}
      |> LeaveRequest.list!(Keyword.put(opts, :load, clamped_days_in_year: %{year_start: year_start, year_end: year_end}))
      |> Enum.reduce(0, fn request, acc -> acc + (request.clamped_days_in_year || 0) end)
    end)
  end
end
