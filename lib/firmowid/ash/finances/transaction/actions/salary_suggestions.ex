defmodule Firmowid.Ash.Finances.Transaction.Actions.SalarySuggestions do
  @moduledoc "Finds recent unassigned salaries within the transfer's amount window, prioritizing its expected payroll month."

  use Ash.Resource.Actions.Implementation

  alias Firmowid.Ash.Finances
  alias Firmowid.Ash.Payroll
  alias Firmowid.Ash.Scope
  alias Firmowid.Ash.Timetracker

  @minimum_tolerance Decimal.new(300)
  @relative_tolerance Decimal.new("0.20")
  @lookback_months 6

  @impl true
  def run(input, _opts, context) do
    scope = Scope.new!(context.actor, context.tenant)

    with {:ok, transaction} <-
           Finances.get_transaction(input.arguments.transaction_id,
             load: [:direction, :reconciliation_status],
             scope: scope
           ) do
      if transaction.direction == :expense and Money.to_currency_code(transaction.amount) == :PLN and
           transaction.reconciliation_status == :pending do
        {:ok, suggestions(transaction, input.arguments, scope)}
      else
        {:ok, []}
      end
    end
  end

  defp suggestions(transaction, arguments, scope) do
    assigned =
      %{salary_assigned: true}
      |> Finances.list_transactions!(scope: scope)
      |> MapSet.new(&{&1.salary_user_id, &1.salary_month})

    amount = transaction.amount |> Money.to_decimal() |> Decimal.abs()
    expected_month = expected_salary_month(transaction.booking_date)

    transaction
    |> candidate_months(arguments[:salary_month], arguments[:salary_user_id], scope)
    |> Enum.flat_map(fn month ->
      %{active_at: Date.end_of_month(month), user_id: arguments[:salary_user_id]}
      |> Payroll.list_salaries!(
        load: [:user, monthly_amount: [month: month]],
        query: [filter: [user: [organization_id: scope.tenant]]],
        scope: scope
      )
      |> Enum.reject(&MapSet.member?(assigned, {&1.user_id, month}))
      |> Enum.flat_map(&suggestion(&1, month, amount))
    end)
    |> Enum.sort(fn a, b ->
      if a.month == expected_month == (b.month == expected_month) do
        case Decimal.compare(Money.to_decimal(a.difference), Money.to_decimal(b.difference)) do
          :lt -> true
          :gt -> false
          :eq -> Date.compare(a.month, b.month) != :lt
        end
      else
        a.month == expected_month
      end
    end)
  end

  defp candidate_months(transaction, nil, user_id, scope) do
    next_month = transaction.booking_date |> Date.beginning_of_month() |> Date.shift(month: 1)

    first_month =
      transaction.booking_date
      |> Date.beginning_of_month()
      |> Date.shift(month: -@lookback_months)

    %{
      started_from: DateTime.new!(first_month, ~T[00:00:00], "Etc/UTC"),
      started_to: DateTime.new!(next_month, ~T[00:00:00], "Etc/UTC"),
      user_id: user_id
    }
    |> Timetracker.months_with_sessions(scope)
    |> Enum.map(&NaiveDateTime.to_date/1)
  end

  defp candidate_months(transaction, %Date{day: 1} = month, _user_id, _scope) do
    first_month =
      transaction.booking_date
      |> Date.beginning_of_month()
      |> Date.shift(month: -@lookback_months)

    if Date.before?(month, first_month) or Date.after?(month, transaction.booking_date),
      do: [],
      else: [month]
  end

  defp candidate_months(_transaction, _month, _user_id, _scope), do: []

  defp expected_salary_month(%Date{day: day} = date) when day <= 14 do
    date |> Date.beginning_of_month() |> Date.shift(month: -1)
  end

  defp expected_salary_month(date), do: Date.beginning_of_month(date)

  defp suggestion(%{user: nil}, _month, _amount), do: []

  defp suggestion(salary, month, amount) do
    expected = Money.to_decimal(salary.monthly_amount)
    difference = Decimal.abs(Decimal.sub(amount, expected))
    tolerance = Decimal.max(@minimum_tolerance, Decimal.mult(expected, @relative_tolerance))

    if Decimal.compare(expected, 0) == :gt and Decimal.compare(difference, tolerance) != :gt do
      [
        %{
          user_id: salary.user_id,
          name: salary.user.name || to_string(salary.user.email),
          month: month,
          expected_amount: salary.monthly_amount,
          difference: Money.new!(:PLN, difference)
        }
      ]
    else
      []
    end
  end
end
