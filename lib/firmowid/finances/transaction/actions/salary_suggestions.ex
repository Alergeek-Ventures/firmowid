defmodule Firmowid.Finances.Transaction.Actions.SalarySuggestions do
  @moduledoc """
  Finds recent unassigned salaries for an outgoing transfer and explains an empty result.

  When both the employee's stored bank account and the recipient's account are known, the account
  decides: a transfer to the employee's account is suggested whatever the amount and ranked first, and
  a transfer to another account is not suggested, unless that employee was chosen explicitly.
  Otherwise the amount has to fall within a tolerance window, and the recipient's name, payroll month
  and amount set the order.

  A month written in the transfer title, such as `Wynagrodzenie 09/26`, names the salary it pays:
  with the employee recognised by account or full name and the amount within the tolerance, that
  salary is a confident match.
  """

  use Ash.Resource.Actions.Implementation

  alias Firmowid.Core.Member
  alias Firmowid.Finances
  alias Firmowid.Finances.AccountNumber
  alias Firmowid.Finances.RecipientName
  alias Firmowid.Payroll
  alias Firmowid.Payroll.UserSalary.Calculations.PayoutEstimates
  alias Firmowid.Scope
  alias Firmowid.Timetracker

  @minimum_tolerance Decimal.new(1000)
  @relative_tolerance Decimal.new("0.20")
  @lookback_months 6
  # Ranks above a full name match, which is 2.
  @same_account_rank 3

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

    recipient = %{
      name_parts: RecipientName.parts(transaction.creditor_name),
      account: AccountNumber.key(transaction.creditor_account),
      # Assigning a chosen salary re-checks it here, and a different account must not block that.
      chosen?: not is_nil(arguments[:salary_user_id]),
      named_months: named_months(transaction.remittance_information_unstructured)
    }

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
         {:ok, payable} <-
           present(
             Enum.reject(submitted, fn {salary, _month} ->
               account_match(salary.member, recipient) == :different
             end),
             :different_account
           ),
         {:ok, suggestions} <-
           present(
             Enum.flat_map(payable, fn {salary, month} ->
               suggestion(salary, month, amount, recipient)
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
    |> Enum.sort(fn {a_rank, a}, {b_rank, b} ->
      a_priority = {a_rank, a.named_month?, a.month == expected_month}
      b_priority = {b_rank, b.named_month?, b.month == expected_month}

      # Recipient identity is an absolute priority, not a small score bonus:
      # neither an exact amount nor the preferred month can outrank a full name.
      # A month written in the title outranks the month guessed from the booking date.

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
    |> Enum.map(fn {_rank, suggestion} -> suggestion end)
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

  @month_names %{
    "styczen" => 1,
    "stycznia" => 1,
    "luty" => 2,
    "lutego" => 2,
    "marzec" => 3,
    "marca" => 3,
    "kwiecien" => 4,
    "kwietnia" => 4,
    "maj" => 5,
    "maja" => 5,
    "czerwiec" => 6,
    "czerwca" => 6,
    "lipiec" => 7,
    "lipca" => 7,
    "sierpien" => 8,
    "sierpnia" => 8,
    "wrzesien" => 9,
    "wrzesnia" => 9,
    "pazdziernik" => 10,
    "pazdziernika" => 10,
    "listopad" => 11,
    "listopada" => 11,
    "grudzien" => 12,
    "grudnia" => 12
  }

  # Months written as 09/26, 9/2026, 09.2026, 09-26 or październik 2026. A digit or a separator
  # before a numeric month rules out the middle of a full date, such as 12.09.2026.
  defp named_months(nil), do: []

  defp named_months(title) do
    title = title |> AnyAscii.transliterate() |> IO.iodata_to_binary() |> String.downcase()

    numeric =
      ~r/(?<![\d.\/-])(0?[1-9]|1[0-2]) ?[.\/-] ?(20\d{2}|\d{2})(?!\d|[.\/-]\d)/
      |> Regex.scan(title, capture: :all_but_first)
      |> Enum.map(fn [month, year] -> {String.to_integer(month), String.to_integer(year)} end)

    written =
      ~r/\b([a-z]+)\s+(20\d{2})\b/
      |> Regex.scan(title, capture: :all_but_first)
      |> Enum.flat_map(fn [name, year] ->
        if month = @month_names[name], do: [{month, String.to_integer(year)}], else: []
      end)

    numeric
    |> Enum.concat(written)
    |> Enum.map(fn {month, year} ->
      Date.new!(if(year < 100, do: 2000 + year, else: year), month, 1)
    end)
    |> Enum.uniq()
  end

  defp suggestion(%{member: %{user: user}} = salary, month, amount, recipient) do
    estimate = PayoutEstimates.closest(salary.payout_estimates, Money.new!(:PLN, amount))
    expected_amount = if estimate, do: estimate.amount, else: salary.monthly_amount
    expected = Money.to_decimal(expected_amount)
    difference = Decimal.abs(Decimal.sub(amount, expected))
    tolerance = Decimal.max(@minimum_tolerance, Decimal.mult(expected, @relative_tolerance))

    within_tolerance? =
      Decimal.compare(expected, 0) == :gt and Decimal.compare(difference, tolerance) != :gt

    if rank = rank(salary.member, recipient, within_tolerance?) do
      named_month? = month in recipient.named_months

      [
        {rank,
         %{
           user_id: user.id,
           name: salary.member.name || to_string(user.email),
           month: month,
           expected_amount: expected_amount,
           payout_variant: if(estimate, do: estimate.variant),
           difference: Money.new!(:PLN, difference),
           named_month?: named_month?,
           confidence: confidence(rank, named_month?, within_tolerance?, difference)
         }}
      ]
    else
      []
    end
  end

  # The title naming the month settles which salary it is, once the recipient is the employee,
  # by account or full name, and the amount is not far off. One shared word, such as a first
  # name, is not enough. An exact amount is confident when the recipient resembles the employee.
  defp confidence(rank, true = _named_month?, true = _within_tolerance?, _difference) when rank >= 2, do: :high

  defp confidence(rank, _named_month?, _within_tolerance?, difference) do
    if rank >= 1 and Decimal.eq?(difference, 0), do: :high, else: :mid
  end

  # Returns nil when the salary should not be suggested.
  defp rank(member, recipient, within_tolerance?) do
    cond do
      account_match(member, recipient) == :same -> @same_account_rank
      within_tolerance? -> RecipientName.rank(member.name, recipient.name_parts)
      true -> nil
    end
  end

  defp account_match(member, recipient) do
    case {AccountNumber.key(member.bank_account_number), recipient} do
      {nil, _recipient} -> :unknown
      {_employee_account, %{account: nil}} -> :unknown
      {account, %{account: account}} -> :same
      {_employee_account, %{chosen?: true}} -> :unknown
      {_employee_account, _recipient} -> :different
    end
  end
end
