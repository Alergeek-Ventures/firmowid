defmodule Firmowid.Finances.Transaction.Actions.StrongMatches do
  @moduledoc """
  Finds the confident suggestion of each of many pending transactions, so a list can point at
  the ones that only need confirming.

  Invoices and business trips are read once for all transactions. Salary suggestions run per
  transaction, so only outgoing transfers whose recipient looks like an employee, by account
  or name, are asked. Salaries and business trips are suggested to administrators only.
  """

  use Ash.Resource.Actions.Implementation

  alias Firmowid.Core.Member
  alias Firmowid.Finances
  alias Firmowid.Finances.AccountNumber
  alias Firmowid.Finances.RecipientName
  alias Firmowid.Finances.Transaction
  alias Firmowid.Finances.Transaction.Actions.DelegationSuggestions
  alias Firmowid.Invoicing.CostInvoice
  alias Firmowid.Invoicing.InvoiceMatching
  alias Firmowid.Invoicing.RecommendationThresholds
  alias Firmowid.Scope

  @impl true
  def run(input, _opts, context) do
    scope = Scope.new!(context.actor, context.tenant)

    transactions =
      Finances.list_transactions!(
        %{ids: input.arguments.transaction_ids, reconciliation: :pending},
        load: DelegationSuggestions.transaction_loads(),
        scope: scope
      )

    # Earlier finders win when one transaction has confident suggestions of several kinds.
    finders =
      if Ash.can?({Transaction, :salary_suggestions}, context.actor, tenant: context.tenant),
        do: [delegation_matches(transactions, scope), salary_matches(transactions, scope)],
        else: []

    finders = finders ++ [invoice_matches(transactions, scope)]

    {:ok,
     Enum.flat_map(transactions, fn transaction ->
       finders |> Enum.find_value(&Map.get(&1, transaction.id)) |> List.wrap()
     end)}
  end

  defp invoice_matches(transactions, scope) do
    for {transaction_id, {invoice, score}} <-
          InvoiceMatching.best_invoices_for_transactions(transactions, scope),
        RecommendationThresholds.high_confidence?(score),
        into: %{} do
      {name, reference} =
        case invoice do
          %CostInvoice{} -> {invoice.effective_seller_display_name, invoice.invoice_identifier}
          sales_invoice -> {sales_invoice.buyer_display_name_label, sales_invoice.invoice_number}
        end

      {transaction_id, %{transaction_id: transaction_id, kind: :invoice, name: name, reference: reference}}
    end
  end

  defp delegation_matches(transactions, scope) do
    delegations = DelegationSuggestions.candidates(scope)

    for transaction <- transactions,
        [%{confidence: :high} = suggestion | _] <- [
          DelegationSuggestions.suggestions(transaction, delegations)
        ],
        into: %{} do
      {transaction.id,
       %{
         transaction_id: transaction.id,
         kind: :delegation,
         name: suggestion.name,
         reference: suggestion.reference
       }}
    end
  end

  defp salary_matches(transactions, scope) do
    employees =
      Enum.map(
        Member.list!(scope: scope),
        &%{account: AccountNumber.key(&1.bank_account_number), name: &1.name}
      )

    for transaction <- transactions,
        transaction.direction == :expense,
        Money.to_currency_code(transaction.amount) == :PLN,
        employee_recipient?(transaction, employees),
        # A confident salary of another month may rank below the expected month's.
        %{confidence: :high} = suggestion <-
          [
            Enum.find(
              Finances.suggest_transaction_salaries!(transaction.id, scope: scope).suggestions,
              &(&1.confidence == :high)
            )
          ],
        [into: %{}] do
      {transaction.id,
       %{
         transaction_id: transaction.id,
         kind: :salary,
         name: suggestion.name,
         month: suggestion.month
       }}
    end
  end

  defp employee_recipient?(transaction, employees) do
    account = AccountNumber.key(transaction.creditor_account)
    name_parts = RecipientName.parts(transaction.creditor_name)

    Enum.any?(employees, fn employee ->
      (account != nil and employee.account == account) or
        RecipientName.rank(employee.name, name_parts) > 0
    end)
  end
end
