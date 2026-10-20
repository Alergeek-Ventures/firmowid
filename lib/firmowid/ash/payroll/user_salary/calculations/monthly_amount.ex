defmodule Firmowid.Ash.Payroll.UserSalary.Calculations.MonthlyAmount do
  @moduledoc "Calculates monthly pay from the salary rate and recorded work, rounding total hours up."

  use Ash.Resource.Calculation

  alias Firmowid.Ash.Scope
  alias Firmowid.Ash.Timetracker

  @impl true
  def load(_query, _opts, _context), do: [:user_id, :hourly_rate]

  @impl true
  def calculate(records, _opts, context) do
    month = context.arguments.month
    scope = Scope.new!(context.actor, context.tenant)
    user_ids = Enum.map(records, & &1.user_id)

    seconds_by_user =
      %{month: month.month, year: month.year}
      |> Timetracker.list_sessions!(
        load: [:duration, :member],
        query: [filter: [member: [user_id: [in: user_ids]]]],
        scope: scope
      )
      |> Enum.group_by(& &1.member.user_id, & &1.duration)
      |> Map.new(fn {user_id, durations} -> {user_id, Enum.sum(durations)} end)

    Enum.map(records, fn salary ->
      hours = seconds_by_user |> Map.get(salary.user_id, 0) |> Timetracker.seconds_to_hours()
      Money.new!(:PLN, Decimal.mult(salary.hourly_rate, Decimal.new(hours)))
    end)
  end
end
