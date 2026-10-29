defmodule Firmowid.Payroll.UserSalary.Calculations.MonthlyAmount do
  @moduledoc "Calculates monthly pay from the salary rate and recorded work, rounding total hours up."

  use Ash.Resource.Calculation

  alias Firmowid.Scope
  alias Firmowid.Timetracker

  @impl true
  def load(_query, _opts, _context), do: [:hourly_rate, :member_id]

  @impl true
  def calculate(records, _opts, context) do
    month = context.arguments.month
    scope = Scope.new!(context.actor, context.tenant)
    member_ids = Enum.map(records, & &1.member_id)

    seconds_by_member =
      %{month: month.month, year: month.year}
      |> Timetracker.list_sessions!(
        load: [:duration],
        query: [filter: [member_id: [in: member_ids]]],
        scope: scope
      )
      |> Enum.group_by(& &1.member_id, & &1.duration)
      |> Map.new(fn {member_id, durations} -> {member_id, Enum.sum(durations)} end)

    Enum.map(records, fn salary ->
      hours = seconds_by_member |> Map.get(salary.member_id, 0) |> Timetracker.seconds_to_hours()
      Money.new!(:PLN, Decimal.mult(salary.hourly_rate, Decimal.new(hours)))
    end)
  end
end
