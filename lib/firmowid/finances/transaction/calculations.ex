defmodule Firmowid.Finances.Transaction.Calculations do
  @moduledoc "Derived reconciliation, direction, amount, and counterparty fields for bank transactions."
  use Spark.Dsl.Fragment, of: Ash.Resource

  alias AshMoney.Types.Money
  alias Firmowid.Finances.Transaction.Calculations

  calculations do
    calculate :reconciliation_status,
              :atom,
              expr(
                cond do
                  exists(cost_invoices, true) or exists(sales_invoices, true) or has_salary? or
                      exists(expected_transactions, true) ->
                    :matched

                  skip_invoicing == true ->
                    :skipped

                  true ->
                    :pending
                end
              ) do
      public? true
      constraints one_of: [:pending, :matched, :skipped]

      description "Transaction reconciliation state derived from invoice, salary or expected transaction links " <>
                    "and the skip flag."
    end

    calculate :invoice_matchable?,
              :boolean,
              expr(
                reconciliation_status != :matched or
                  exists(cost_invoices, true) or exists(sales_invoices, true)
              ) do
      description "Allows manual invoice matching of unresolved transactions and existing multi-invoice payments."
    end

    calculate :expectation_matchable?,
              :boolean,
              expr(reconciliation_status != :matched or exists(expected_transactions, true)) do
      description "Allows fulfilling expectations with unresolved transactions and with payouts that already " <>
                    "fulfil others."
    end

    calculate :has_salary?, :boolean, expr(not is_nil(salary_month)) do
      public? true

      description "Whether the transaction is settled by a monthly salary assignment. " <>
                    "It stays so when the employee's account is deleted."
    end

    calculate :date, :date, expr(booking_date)

    calculate :direction, :atom, Calculations.Direction do
      public? true
      constraints one_of: [:income, :expense]

      description "Canonical transaction direction, preferring connected account ownership over amount sign."
    end

    calculate :signed_amount, Money, Calculations.SignedAmount do
      public? true
      description "Transaction amount signed according to its canonical direction."
    end

    calculate :counterparty_name, :string, Calculations.CounterpartyName do
      public? true
      description "Raw counterparty name selected according to transaction direction."
    end

    calculate :counterparty_display_name, :string, Calculations.CounterpartyDisplayName do
      public? true
      description "Useful counterparty name, with a Polish fallback when unavailable."
    end

    calculate :groupable?, :boolean, Calculations.Groupable do
      public? true
      description "Whether the transaction can be grouped for invoicing."
    end
  end
end
