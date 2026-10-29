defmodule Firmowid.Finances.Transaction.Actions.SalarySuggestions do
  @moduledoc "Finds recent unassigned salaries within the transfer's amount window, prioritizing the recipient's name, payroll month and amount, and explains an empty result."

  use Ash.Resource.Actions.Implementation

  alias Firmowid.Core.Member
  alias Firmowid.Finances
  alias Firmowid.Payroll
  alias Firmowid.Payroll.UserSalary.Calculations.PayoutEstimates
  alias Firmowid.Scope
  alias Firmowid.Timetracker

  @minimum_tolerance Decimal.new(1000)
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
      cond do
        transaction.direction != :expense or Money.to_currency_code(transaction.amount) != :PLN ->
          {:ok, %{suggestions: [], reason: :not_outgoing_pln}}

        transaction.reconciliation_status == :matched ->
          {:ok, %{suggestions: [], reason: :transaction_matched}}

        true ->
          {:ok, suggestions(transaction, input.arguments, scope)}
      end
    end
  end

  # Each step narrows the candidates; the first step that leaves none explains the empty result.
  defp suggestions(transaction, arguments, scope) do
    amount = transaction.amount |> Money.to_decimal() |> Decimal.abs()
    recipient_parts = name_parts(transaction.creditor_name)
    member_id = member_id(arguments[:salary_user_id], scope)
    no_months_reason = if arguments[:salary_month], do: :month_out_of_range, else: :no_logged_time

    with {:ok, months} <-
           present(
             candidate_months(transaction, arguments[:salary_month], member_id, scope),
             no_months_reason
           ),
         {:ok, candidates} <-
           present(salaries(months, arguments[:salary_user_id], scope), :no_salaries),
         {:ok, unpaid} <- present(reject_assigned(candidates, scope), :salaries_already_paid),
         {:ok, submitted} <-
           present(
             submitted(unpaid, months, member_id, arguments.submitted_hours_only?, scope),
             :hours_not_submitted
           ),
         {:ok, suggestions} <-
           present(
             Enum.flat_map(submitted, fn {salary, month} ->
               suggestion(salary, month, amount, recipient_parts)
             end),
             :amount_out_of_range
           ) do
      %{
        suggestions: sort(suggestions, expected_salary_month(transaction.booking_date)),
        reason: nil
      }
    else
      {:none, reason} -> %{suggestions: [], reason: reason}
    end
  end

  defp present([], reason), do: {:none, reason}
  defp present(list, _reason), do: {:ok, list}

  defp salaries(months, user_id, scope) do
    Enum.flat_map(months, fn month ->
      %{active_at: Date.end_of_month(month), user_id: user_id}
      |> Payroll.list_salaries!(
        load: [member: :user, monthly_amount: [month: month], payout_estimates: [month: month]],
        query: [filter: [member: [archived_at: [is_nil: true]]]],
        scope: scope
      )
      |> Enum.reject(&is_nil(&1.member.user))
      |> Enum.map(&{&1, month})
    end)
  end

  defp reject_assigned(candidates, scope) do
    assigned =
      %{salary_assigned: true}
      |> Finances.list_transactions!(scope: scope)
      |> MapSet.new(&{&1.salary_user_id, &1.salary_month})

    Enum.reject(candidates, fn {salary, month} ->
      MapSet.member?(assigned, {salary.member.user_id, month})
    end)
  end

  defp submitted(candidates, _months, _member_id, false, _scope), do: candidates

  defp submitted(candidates, months, member_id, true, scope) do
    submitted =
      months
      |> Enum.flat_map(fn month ->
        %{
          month: month.month,
          year: month.year,
          member_id: member_id,
          submission_status: :submitted
        }
        |> Timetracker.list_hours_records!(load: [:member], scope: scope)
        |> Enum.map(&{&1.member.user_id, month})
      end)
      |> MapSet.new()

    Enum.filter(candidates, fn {salary, month} ->
      MapSet.member?(submitted, {salary.member.user_id, month})
    end)
  end

  defp sort(suggestions, expected_month) do
    suggestions
    |> Enum.sort(fn {a_name_rank, a}, {b_name_rank, b} ->
      a_priority = {a_name_rank, a.month == expected_month}
      b_priority = {b_name_rank, b.month == expected_month}

      # Recipient identity is an absolute priority, not a small score bonus:
      # neither an exact amount nor the preferred month can outrank a full name.

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

  defp suggestion(%{member: %{user: user}} = salary, month, amount, recipient_parts) do
    estimate = PayoutEstimates.closest(salary.payout_estimates, Money.new!(:PLN, amount))
    expected_amount = if estimate, do: estimate.amount, else: salary.monthly_amount
    expected = Money.to_decimal(expected_amount)
    difference = Decimal.abs(Decimal.sub(amount, expected))
    tolerance = Decimal.max(@minimum_tolerance, Decimal.mult(expected, @relative_tolerance))

    if Decimal.compare(expected, 0) == :gt and Decimal.compare(difference, tolerance) != :gt do
      [
        {name_match_rank(salary.member.name, recipient_parts),
         %{
           user_id: user.id,
           name: salary.member.name || to_string(user.email),
           month: month,
           expected_amount: expected_amount,
           payout_variant: if(estimate, do: estimate.variant),
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
