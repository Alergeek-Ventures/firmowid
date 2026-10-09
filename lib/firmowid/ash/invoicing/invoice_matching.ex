defmodule Firmowid.Ash.Invoicing.InvoiceMatching do
  @moduledoc """
  Invoice-transaction matching orchestration.

  Handles automatic and manual matching of invoices (sales and cost)
  to bank transactions. Uses the ML-based scoring from
  `Firmowid.Ash.Invoicing.Matching` sub-modules for prediction.
  """

  alias Firmowid.Ash.Finances
  alias Firmowid.Ash.Invoicing
  alias Firmowid.Ash.Invoicing.Matching
  alias Firmowid.Ash.Scope

  require Logger

  @doc """
  Returns potential transactions for an invoice, scored and sorted by match likelihood.

  Combines unmatched transactions with already-attached ones and scores them
  using the ML regression predictor.
  """
  @spec get_potential_transactions_for_invoice(struct(), Scope.t()) :: [{struct(), float()}]
  def get_potential_transactions_for_invoice(invoice, scope) do
    unmatched_transactions =
      Finances.list_transactions!(
        %{date_from: ~D[2000-01-01], date_to: ~D[2100-12-30], reconciliation: :pending},
        load: [:amount],
        scope: scope
      )

    attached_transactions = Map.get(invoice, :transactions, [])

    # Combine and deduplicate by transaction id
    all_transactions = Enum.uniq_by(unmatched_transactions ++ attached_transactions, & &1.id)

    score_and_sort_transactions(invoice, all_transactions)
  end

  @doc """
  Auto-matches all unmatched cost invoices for an organization.
  """
  @spec match_cost_invoices(Scope.t()) :: :ok
  def match_cost_invoices(scope) do
    %{
      date_from: ~D[1970-01-01],
      date_to: ~D[2100-01-01],
      date_field: :due_date,
      reconciliation: :pending,
      corrections: :exclude
    }
    |> Invoicing.list_cost_invoices!(scope: scope)
    |> match_invoices(list_pending_transactions(scope), fn %{id: id}, transactions ->
      id
      |> Invoicing.get_cost_invoice!(load: [:effective_amount], scope: scope)
      |> match_invoice(
        transactions,
        &Invoicing.connect_cost_invoice_transactions_auto_match!/4,
        scope
      )
    end)
  end

  @doc """
  Auto-matches a single cost invoice to the best available transaction.
  """
  @spec match_cost_invoice(String.t(), Scope.t()) :: :ok
  def match_cost_invoice(cost_invoice_id, scope) do
    cost_invoice_id
    |> Invoicing.get_cost_invoice!(load: [:effective_amount], scope: scope)
    |> match_invoice(
      list_pending_transactions(scope),
      &Invoicing.connect_cost_invoice_transactions_auto_match!/4,
      scope
    )

    :ok
  end

  @doc """
  Auto-matches all unmatched sales invoices for an organization.
  """
  @spec match_sales_invoices(Scope.t()) :: :ok
  def match_sales_invoices(scope) do
    %{kind: :vat, reconciliation: :pending, submission: :confirmed, date_field: :due_date}
    |> Invoicing.list_sales_invoices!(scope: scope)
    |> match_invoices(list_pending_transactions(scope), fn %{id: id}, transactions ->
      id
      |> Invoicing.get_sales_invoice!(
        load: [:buyer_display_name_label, :effective_amount],
        scope: scope
      )
      |> match_invoice(
        transactions,
        &Invoicing.connect_sales_invoice_transactions_auto_match!/4,
        scope
      )
    end)
  end

  # Threads the still-available transactions through consecutive invoices, so
  # a whole organization pass reads pending transactions only once.
  defp match_invoices([], _transactions, _match_fun), do: :ok

  defp match_invoices([invoice | rest], transactions, match_fun) do
    match_invoices(rest, match_fun.(invoice, transactions), match_fun)
  end

  # Connects the invoice to its best candidate when the score is confident enough.
  # Returns the transactions that are still available for the next invoice.
  defp match_invoice(invoice, transactions, connect, scope) do
    case score_and_sort_transactions(invoice, transactions) do
      [{transaction, prediction_score} | _] ->
        if Matching.RegressionPredictor.confident_match?(prediction_score) do
          connect.(invoice, [transaction.id], prediction_score, scope)

          Logger.info("Matched invoice #{invoice.id} with transaction #{transaction.id} (score #{prediction_score})")

          Enum.reject(transactions, &(&1.id == transaction.id))
        else
          Logger.debug("No confident match for invoice #{invoice.id} (best score #{prediction_score})")

          transactions
        end

      [] ->
        transactions
    end
  end

  defp list_pending_transactions(scope) do
    Finances.list_transactions!(
      %{date_from: ~D[2000-01-01], date_to: ~D[2100-12-30], reconciliation: :pending},
      scope: scope
    )
  end

  @doc """
  Scores and sorts transactions by match likelihood against an invoice.
  """
  @spec score_and_sort_transactions(struct(), [struct()]) :: [{struct(), float()}]
  def score_and_sort_transactions(invoice, transactions) do
    invoice
    |> Matching.Windowing.pre_filter_invoice_transactions(transactions)
    |> Enum.map(fn transaction ->
      features = Matching.ParametrizedResult.generate_parametrized_result(invoice, transaction)

      prediction_score =
        Matching.RegressionPredictor.score([
          features.days_lag_le_3,
          features.days_lag_le_7,
          features.days_lag_le_30,
          features.days_lag_gt_30,
          features.signed_amount_match,
          features.relative_amount_difference,
          features.transaction_side_similarity,
          features.bank_account_similarity,
          features.is_same_currency,
          features.amount_present_in_remittance_information_unstructured,
          features.invoice_identifier_present_in_remittance_information_unstructured
        ])

      {transaction, prediction_score}
    end)
    |> Enum.sort_by(fn {_, prediction_score} -> prediction_score end, :desc)
  end
end
