defmodule Firmowid.Ash.Payroll.SalaryMatching do
  @moduledoc "Proposes employee/month salary assignments using the existing management salary calculation."

  alias Firmowid.Ash.Core
  alias Firmowid.Ash.Finances
  alias Firmowid.Ash.Payroll
  alias Firmowid.Ash.Scope
  alias Firmowid.Ash.Timetracker

  @minimum_tolerance Decimal.new(300)
  @relative_tolerance Decimal.new("0.20")

  @type summary :: %{
          user_id: String.t(),
          name: String.t(),
          month: Date.t(),
          expected_amount: Money.t()
        }

  @doc "Returns the closest unassigned salaries for an eligible transaction, visible only to administrators."
  @spec suggestions(struct(), Scope.t()) :: [map()]
  def suggestions(transaction, %Scope{actor: %{role: :admin}} = scope) do
    if eligible?(transaction) do
      next_month = transaction.booking_date |> Date.beginning_of_month() |> Date.shift(month: 1)

      sessions =
        Timetracker.list_sessions!(
          %{started_to: DateTime.new!(next_month, ~T[00:00:00], "Etc/UTC")},
          load: [:duration],
          scope: scope
        )

      salaries = Payroll.list_salaries!(scope: scope)
      users = Map.new(Core.list_users!(scope: scope), &{&1.id, &1})

      assigned =
        %{salary_assigned: true}
        |> Finances.list_transactions!(scope: scope)
        |> MapSet.new(&{&1.salary_user_id, &1.salary_month})

      amount = transaction.amount |> Money.to_decimal() |> Decimal.abs()

      sessions
      |> Enum.group_by(&{&1.user_id, Date.beginning_of_month(DateTime.to_date(&1.start_datetime))})
      |> Enum.reject(fn {key, _sessions} -> MapSet.member?(assigned, key) end)
      |> Enum.flat_map(fn {{user_id, month}, month_sessions} ->
        case build_summary(Map.get(users, user_id), month, month_sessions, salaries) do
          nil -> []
          summary -> suggestion(summary, amount)
        end
      end)
      |> Enum.sort(fn a, b ->
        case Decimal.compare(Money.to_decimal(a.difference), Money.to_decimal(b.difference)) do
          :lt -> true
          :gt -> false
          :eq -> Date.compare(a.month, b.month) != :lt
        end
      end)
      |> Enum.take(5)
    else
      []
    end
  end

  def suggestions(_transaction, _scope), do: []

  @doc "Builds the short monthly summary with the same end-of-month rate and rounded hours used in management."
  @spec summary(String.t(), Date.t(), Scope.t()) :: summary() | nil
  def summary(user_id, month, %Scope{actor: %{role: :admin}} = scope) do
    user = Core.get_org_user!(%{id: user_id}, scope: scope, not_found_error?: false)

    sessions =
      Timetracker.list_sessions!(%{user_id: user_id, month: month.month, year: month.year},
        load: [:duration],
        scope: scope
      )

    salaries = Payroll.list_salaries!(%{user_id: user_id}, scope: scope)
    build_summary(user, month, sessions, salaries)
  end

  def summary(_user_id, _month, _scope), do: nil

  @doc "Tests the inclusive amount window: ±20%, with at least ±300 PLN and a nonnegative lower bound."
  @spec within_tolerance?(Decimal.t(), Decimal.t()) :: boolean()
  def within_tolerance?(amount, expected) do
    tolerance = Decimal.max(@minimum_tolerance, Decimal.mult(expected, @relative_tolerance))

    Decimal.compare(amount, 0) != :lt and
      Decimal.compare(Decimal.abs(Decimal.sub(amount, expected)), tolerance) != :gt
  end

  @doc "Checks whether the transaction is still an unskipped, unassigned outgoing PLN payment."
  @spec eligible?(struct()) :: boolean()
  def eligible?(transaction) do
    transaction.direction == :expense and Money.to_currency_code(transaction.amount) == :PLN and
      transaction.skip_invoicing == false and transaction.has_salary? == false and
      transaction.cost_invoices == [] and transaction.sales_invoices == []
  end

  defp suggestion(summary, amount) do
    expected = Money.to_decimal(summary.expected_amount)

    if within_tolerance?(amount, expected) do
      [
        Map.put(
          summary,
          :difference,
          Money.new!(:PLN, Decimal.abs(Decimal.sub(amount, expected)))
        )
      ]
    else
      []
    end
  end

  defp build_summary(nil, _month, _sessions, _salaries), do: nil

  defp build_summary(user, month, sessions, salaries) do
    month_end = Date.end_of_month(month)

    salary =
      Enum.find(salaries, fn salary ->
        salary.user_id == user.id and
          Date.compare(DateTime.to_date(salary.starts_at), month_end) != :gt
      end)

    hours = sessions |> Enum.map(& &1.duration) |> Enum.sum() |> Timetracker.seconds_to_hours()

    if salary && hours > 0 && Decimal.compare(salary.hourly_rate, 0) == :gt do
      %{
        user_id: user.id,
        name: user.name || to_string(user.email),
        month: month,
        expected_amount: Money.new!(:PLN, Decimal.mult(salary.hourly_rate, Decimal.new(hours)))
      }
    end
  end
end
