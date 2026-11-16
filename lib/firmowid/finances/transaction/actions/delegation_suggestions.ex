defmodule Firmowid.Finances.Transaction.Actions.DelegationSuggestions do
  @moduledoc """
  Finds approved business trips a pending PLN transfer may belong to.

  An outgoing transfer may pay out the advance or the settlement, an incoming one may return the
  advance. A trip often takes two transfers, the advance before it and the settlement balance
  after it, so an amount already paid by a linked transfer is not expected again. The trip's
  reference in the title is a confident match on its own. Otherwise the
  counterparty has to be the employee, by account or name: an exact amount is then a confident
  match, and an amount within the tolerance or a title about a business trip, its advance,
  settlement balance or return a possible one.
  """

  use Ash.Resource.Actions.Implementation

  alias Firmowid.Delegations
  alias Firmowid.Delegations.Settlement
  alias Firmowid.Finances
  alias Firmowid.Finances.AccountNumber
  alias Firmowid.Finances.RecipientName
  alias Firmowid.Scope

  @approved [:in_progress, :awaiting_signature, :submitted, :complete]
  @prepared [:awaiting_signature, :submitted, :complete]
  # An advance may go out before the order date is set, a settlement months after the trip.
  @days_before_order 30
  @days_after_trip 180
  @relative_tolerance Decimal.new("0.20")
  # Ranks above a full name match, which is 2.
  @same_account_rank 3

  @transaction_loads [:direction, :reconciliation_status, :counterparty_name]

  @impl true
  def run(input, _opts, context) do
    scope = Scope.new!(context.actor, context.tenant)

    with {:ok, transaction} <-
           Finances.get_transaction(input.arguments.transaction_id,
             load: @transaction_loads,
             scope: scope
           ) do
      {:ok, if(suggestable?(transaction), do: suggestions(transaction, candidates(scope)), else: [])}
    end
  end

  @doc "Transaction fields `suggestions/2` reads besides the attributes."
  @spec transaction_loads() :: [atom()]
  def transaction_loads, do: @transaction_loads

  @doc """
  Reads the approved delegations with what scoring needs, each with the transfers already linked
  to it, once for any number of transactions.
  """
  @spec candidates(Scope.t()) :: [{Delegations.Delegation.t(), [Finances.Transaction.t()]}]
  def candidates(scope) do
    delegations =
      Delegations.list_delegations!(%{statuses: @approved},
        load: [:expenses, member: :user],
        scope: scope
      )

    linked =
      [
        query: [filter: [delegation_id: [in: Enum.map(delegations, & &1.id)]]],
        load: [:direction],
        scope: scope
      ]
      |> Finances.list_transactions!()
      |> Enum.group_by(& &1.delegation_id)

    Enum.map(delegations, &{&1, Map.get(linked, &1.id, [])})
  end

  @doc "Scores the delegations against one transaction, best match first."
  @spec suggestions(Finances.Transaction.t(), [
          {Delegations.Delegation.t(), [Finances.Transaction.t()]}
        ]) ::
          [map()]
  def suggestions(transaction, candidates) do
    if suggestable?(transaction) do
      title = transaction.remittance_information_unstructured || ""
      ascii_title = title |> AnyAscii.transliterate() |> IO.iodata_to_binary()

      counterparty = %{
        name_parts: RecipientName.parts(transaction.counterparty_name),
        account: AccountNumber.key(counterparty_account(transaction)),
        # Banks may drop diacritics, as in the initials of a reference such as ŁK-2026-11-1.
        title: String.upcase(ascii_title),
        about_trip?: String.match?(String.downcase(ascii_title), ~r/deleg|zalicz|rozlicz|wyrown|zwrot/)
      }

      amount = transaction.amount |> Money.to_decimal() |> Decimal.abs()

      candidates
      |> Enum.flat_map(&suggestion(&1, transaction, counterparty, amount))
      # Closest amount first among equals, as the second, stable sort keeps this order.
      |> Enum.sort_by(
        fn {_identity, suggestion} -> suggestion.difference || :none end,
        &closer?/2
      )
      |> Enum.sort_by(
        fn {identity, suggestion} ->
          {suggestion.confidence == :high, suggestion.reference_named?, identity}
        end,
        :desc
      )
      |> Enum.map(fn {_identity, suggestion} -> suggestion end)
    else
      []
    end
  end

  defp suggestable?(transaction),
    do: transaction.reconciliation_status == :pending and Money.to_currency_code(transaction.amount) == :PLN

  defp counterparty_account(%{direction: :income} = transaction), do: transaction.debtor_account
  defp counterparty_account(transaction), do: transaction.creditor_account

  defp suggestion({delegation, linked}, transaction, counterparty, amount) do
    reference_named? = reference_named?(delegation.reference, counterparty.title)
    identity = identity(delegation.member, counterparty)

    # Settling the expected amounts is the costly part, so a trip that can match neither by
    # reference nor by the employee is left out first.
    if in_window?(delegation, transaction.booking_date) and (reference_named? or identity > 0) do
      closest =
        delegation
        |> expected_amounts(transaction.direction)
        |> unpaid(Enum.filter(linked, &(&1.direction == transaction.direction)))
        |> closest(amount)

      case confidence(reference_named?, identity, closest, counterparty.about_trip?) do
        nil -> []
        confidence -> [{identity, build(delegation, closest, reference_named?, confidence)}]
      end
    else
      []
    end
  end

  defp in_window?(delegation, date) do
    not Date.before?(date, Date.shift(delegation.command_date, day: -@days_before_order)) and
      not Date.after?(date, Date.shift(delegation.end_date, day: @days_after_trip))
  end

  # A reference such as AB-2026-11-1 must not match inside AB-2026-11-12.
  defp reference_named?(reference, title) do
    reference = reference |> AnyAscii.transliterate() |> IO.iodata_to_binary() |> String.upcase()
    String.match?(title, ~r/(?<![A-Z0-9])#{Regex.escape(reference)}(?!\d)/)
  end

  defp identity(member, counterparty) do
    case {AccountNumber.key(member.bank_account_number), counterparty.account} do
      {account, account} when is_binary(account) -> @same_account_rank
      {employee_account, account} when is_binary(employee_account) and is_binary(account) -> 0
      _unknown -> RecipientName.rank(member.name, counterparty.name_parts)
    end
  end

  defp expected_amounts(delegation, :expense) do
    advance =
      if Money.positive?(delegation.advance_amount),
        do: [{:advance, delegation.advance_amount}],
        else: []

    case balance(delegation) do
      %Money{} = balance ->
        if Money.positive?(balance), do: advance ++ [{:settlement, balance}], else: advance

      nil ->
        advance
    end
  end

  defp expected_amounts(delegation, :income) do
    case balance(delegation) do
      %Money{} = balance ->
        if Money.negative?(balance), do: [{:return, Money.abs(balance)}], else: []

      nil ->
        []
    end
  end

  # Drops the parts a linked transfer in the same direction already paid. Each transfer pays one
  # part, so an advance and a settlement balance of the same amount need two transfers. One in
  # another currency pays none of the PLN amounts.
  defp unpaid([], _linked), do: []

  defp unpaid([{_kind, expected_amount} = part | rest], linked) do
    case Enum.split_with(linked, &pays?(&1, expected_amount)) do
      {[], _others} -> [part | unpaid(rest, linked)]
      {[_payment | payments], others} -> unpaid(rest, payments ++ others)
    end
  end

  defp pays?(transaction, expected_amount) do
    Money.to_currency_code(transaction.amount) == Money.to_currency_code(expected_amount) and
      Decimal.lt?(
        Decimal.abs(Money.to_decimal(Money.sub!(Money.abs(transaction.amount), expected_amount))),
        1
      )
  end

  # Positive when the company owes the employee, negative when the employee returns part of the advance.
  defp balance(%{status: status} = delegation) when status in @prepared,
    do: Money.sub!(Settlement.total(delegation), delegation.advance_amount)

  defp balance(_delegation), do: nil

  defp closest([], _amount), do: nil

  defp closest(expected, amount) do
    expected
    |> Enum.map(fn {kind, expected_amount} ->
      {kind, expected_amount, Decimal.abs(Decimal.sub(amount, Money.to_decimal(expected_amount)))}
    end)
    |> Enum.min_by(fn {_kind, _expected_amount, difference} -> difference end, Decimal)
  end

  defp confidence(true = _reference_named?, _identity, _closest, _about_trip?), do: :high

  defp confidence(_reference_named?, identity, {_kind, expected_amount, difference}, about_trip?) do
    # Per diems and NBP conversions leave cents that a transfer often rounds away.
    exact? = Decimal.lt?(difference, 1)

    cond do
      exact? and identity >= 2 -> :high
      exact? or about_trip? or within_tolerance?(expected_amount, difference) -> :mid
      true -> nil
    end
  end

  defp confidence(_reference_named?, _identity, nil = _closest, true = _about_trip?), do: :mid
  defp confidence(_reference_named?, _identity, nil = _closest, _about_trip?), do: nil

  defp within_tolerance?(expected_amount, difference) do
    Decimal.compare(
      difference,
      Decimal.mult(Money.to_decimal(expected_amount), @relative_tolerance)
    ) != :gt
  end

  defp build(delegation, closest, reference_named?, confidence) do
    {kind, expected_amount, difference} = closest || {nil, nil, nil}

    %{
      delegation_id: delegation.id,
      reference: delegation.reference,
      title: delegation.title,
      user_id: delegation.member.user_id,
      name: delegation.member.name || to_string(delegation.member.user.email),
      start_date: delegation.start_date,
      end_date: delegation.end_date,
      kind: kind,
      expected_amount: expected_amount,
      difference: difference && Money.new!(:PLN, difference),
      reference_named?: reference_named?,
      confidence: confidence
    }
  end

  defp closer?(:none, :none), do: true
  defp closer?(:none, _other), do: false
  defp closer?(_difference, :none), do: true
  defp closer?(a, b), do: Money.compare(a, b) != :gt
end
