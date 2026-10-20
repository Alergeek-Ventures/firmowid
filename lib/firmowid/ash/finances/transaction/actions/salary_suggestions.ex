defmodule Firmowid.Ash.Finances.Transaction.Actions.SalarySuggestions do
  @moduledoc "Finds recent unassigned salaries within the transfer's amount window, prioritizing the recipient's name, payroll month and amount."

  use Ash.Resource.Actions.Implementation

  alias Firmowid.Ash.Core.Member
  alias Firmowid.Ash.Finances
  alias Firmowid.Ash.Payroll
  alias Firmowid.Ash.Scope
  alias Firmowid.Ash.Timetracker

  @minimum_tolerance Decimal.new(300)
  @relative_tolerance Decimal.new("0.20")
  @lookback_months 6
  @partial_name_similarity 0.9

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
    recipient_parts = name_parts(transaction.creditor_name)
    member_id = member_id(arguments[:salary_user_id], scope)

    transaction
    |> candidate_months(arguments[:salary_month], member_id, scope)
    |> Enum.flat_map(fn month ->
      submitted_users =
        if arguments.submitted_hours_only? do
          %{
            month: month.month,
            year: month.year,
            member_id: member_id,
            submission_status: :submitted
          }
          |> Timetracker.list_hours_records!(load: [:member], scope: scope)
          |> MapSet.new(& &1.member.user_id)
        else
          :all
        end

      %{active_at: Date.end_of_month(month), user_id: arguments[:salary_user_id]}
      |> Payroll.list_salaries!(
        load: [:user, monthly_amount: [month: month]],
        query: [filter: [user: [organization_id: scope.tenant]]],
        scope: scope
      )
      |> Enum.filter(fn salary ->
        not MapSet.member?(assigned, {salary.user_id, month}) and
          (submitted_users == :all or MapSet.member?(submitted_users, salary.user_id))
      end)
      |> Enum.flat_map(&suggestion(&1, month, amount, recipient_parts))
    end)
    |> Enum.sort(fn {a_name_rank, a}, {b_name_rank, b} ->
      a_priority = {a_name_rank, a.month == expected_month}
      b_priority = {b_name_rank, b.month == expected_month}

      if a_priority == b_priority do
        case Decimal.compare(Money.to_decimal(a.difference), Money.to_decimal(b.difference)) do
          :lt -> true
          :gt -> false
          :eq -> Date.compare(a.month, b.month) != :lt
        end
      else
        a_priority > b_priority
      end
    end)
    |> Enum.map(fn {_name_rank, suggestion} -> suggestion end)
  end

  defp candidate_months(transaction, nil, member_id, scope) do
    next_month = transaction.booking_date |> Date.beginning_of_month() |> Date.shift(month: 1)

    first_month =
      transaction.booking_date
      |> Date.beginning_of_month()
      |> Date.shift(month: -@lookback_months)

    %{
      started_from: DateTime.new!(first_month, ~T[00:00:00], "Etc/UTC"),
      started_to: DateTime.new!(next_month, ~T[00:00:00], "Etc/UTC"),
      member_id: member_id
    }
    |> Timetracker.months_with_sessions(scope)
    |> Enum.map(&NaiveDateTime.to_date/1)
  end

  defp candidate_months(transaction, %Date{day: 1} = month, _member_id, _scope) do
    first_month =
      transaction.booking_date
      |> Date.beginning_of_month()
      |> Date.shift(month: -@lookback_months)

    if Date.before?(month, first_month) or Date.after?(month, transaction.booking_date),
      do: [],
      else: [month]
  end

  defp candidate_months(_transaction, _month, _member_id, _scope), do: []

  # Sessions and hours records belong to the member, salaries still to the user.
  defp member_id(nil, _scope), do: nil

  defp member_id(user_id, scope) do
    [member] = Member.list!(query: [filter: [user_id: user_id]], scope: scope)
    member.id
  end

  defp expected_salary_month(%Date{day: day} = date) when day <= 14 do
    date |> Date.beginning_of_month() |> Date.shift(month: -1)
  end

  defp expected_salary_month(date), do: Date.beginning_of_month(date)

  defp suggestion(%{user: nil}, _month, _amount, _recipient_parts), do: []

  defp suggestion(salary, month, amount, recipient_parts) do
    expected = Money.to_decimal(salary.monthly_amount)
    difference = Decimal.abs(Decimal.sub(amount, expected))
    tolerance = Decimal.max(@minimum_tolerance, Decimal.mult(expected, @relative_tolerance))

    if Decimal.compare(expected, 0) == :gt and Decimal.compare(difference, tolerance) != :gt do
      [
        {name_match_rank(salary.user.name, recipient_parts),
         %{
           user_id: salary.user_id,
           name: salary.user.name || to_string(salary.user.email),
           month: month,
           expected_amount: salary.monthly_amount,
           difference: Money.new!(:PLN, difference)
         }}
      ]
    else
      []
    end
  end

  defp name_match_rank(name, recipient_parts) do
    employee_parts = name_parts(name)

    cond do
      employee_parts == [] or recipient_parts == [] ->
        0

      length(employee_parts) >= 2 and
          MapSet.subset?(MapSet.new(employee_parts), MapSet.new(recipient_parts)) ->
        2

      Enum.any?(employee_parts, &(&1 in recipient_parts)) ->
        1

      true ->
        similarity =
          employee_parts
          |> Enum.join(" ")
          |> Akin.compare(Enum.join(recipient_parts, " "), algorithms: ["jaro_winkler"])
          |> Map.fetch!(:jaro_winkler)

        if similarity >= @partial_name_similarity, do: 1, else: 0
    end
  end

  defp name_parts(nil), do: []

  defp name_parts(name) do
    name
    |> AnyAscii.transliterate()
    |> IO.iodata_to_binary()
    |> String.downcase()
    |> String.split(~r/[^a-z]+/, trim: true)
    |> Enum.reject(&(String.length(&1) == 1))
    |> Enum.uniq()
    |> Enum.sort()
  end
end
