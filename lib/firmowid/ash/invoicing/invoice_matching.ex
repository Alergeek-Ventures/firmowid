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
    unmatched_cost_invoices =
      Invoicing.list_cost_invoices!(
        %{
          date_from: ~D[1970-01-01],
          date_to: ~D[2100-01-01],
          date_field: :due_date,
          reconciliation: :pending
        },
        scope: scope
      )

    Enum.each(unmatched_cost_invoices, &match_cost_invoice(&1.id, scope))
  end

  @doc """
  Auto-matches a single cost invoice to the best available transaction.
  """
  @spec match_cost_invoice(String.t(), Scope.t()) :: :ok
  def match_cost_invoice(cost_invoice_id, scope) do
    org_id = scope.tenant
    cost_invoice = Invoicing.get_cost_invoice!(cost_invoice_id, scope: scope)

    Logger.info("Matching cost invoice #{cost_invoice.id} for organization #{org_id}")

    unmatched_transactions =
      Finances.list_transactions!(
        %{date_from: ~D[2000-01-01], date_to: ~D[2100-12-30], reconciliation: :pending},
        scope: scope
      )

    Logger.info("Found #{length(unmatched_transactions)} unmatched transactions")

    case score_and_sort_transactions(cost_invoice, unmatched_transactions) do
      [{transaction, prediction_score} | _] ->
        Logger.info("Prediction score: #{prediction_score}")

        if Matching.RegressionPredictor.confident_match?(prediction_score) do
          Invoicing.connect_cost_invoice_transactions!(cost_invoice, [transaction.id], scope: scope)

          Logger.info("Matched cost invoice #{cost_invoice.id} with transaction #{transaction.id}")
        else
          Logger.info("No confident match for cost invoice #{cost_invoice.id}")
        end

      [] ->
        Logger.info("No match found for cost invoice #{cost_invoice.id}")
    end
  end

  @doc """
  Auto-matches all unmatched sales invoices for an organization.
  """
  @spec match_sales_invoices(Scope.t()) :: :ok
  def match_sales_invoices(scope) do
    unmatched_sales_invoices =
      Invoicing.list_sales_invoices!(
        %{kind: :vat, reconciliation: :pending, date_field: :due_date},
        scope: scope
      )

    Enum.each(unmatched_sales_invoices, &match_sales_invoice(&1.id, scope))
  end

  @doc """
  Auto-matches a single sales invoice to the best available transaction.
  """
  @spec match_sales_invoice(String.t(), Scope.t()) :: :ok
  def match_sales_invoice(sales_invoice_id, scope) do
    org_id = scope.tenant

    sales_invoice =
      Invoicing.get_sales_invoice!(sales_invoice_id,
        load: [:buyer_display_name_label, :gross_value],
        scope: scope
      )

    Logger.info("Matching sales invoice #{sales_invoice.id} for organization #{org_id}")

    unmatched_transactions =
      Finances.list_transactions!(
        %{date_from: ~D[2000-01-01], date_to: ~D[2100-12-30], reconciliation: :pending},
        scope: scope
      )

    Logger.info("Found #{length(unmatched_transactions)} unmatched transactions")

    case score_and_sort_transactions(sales_invoice, unmatched_transactions) do
      [{transaction, prediction_score} | _] ->
        Logger.info("Prediction score: #{prediction_score}")

        if Matching.RegressionPredictor.confident_match?(prediction_score) do
          Invoicing.connect_sales_invoice_transactions!(sales_invoice, [transaction.id], scope: scope)

          Logger.info("Matched sales invoice #{sales_invoice.id} with transaction #{transaction.id}")
        else
          Logger.info("No confident match for sales invoice #{sales_invoice.id}")
        end

      [] ->
        Logger.info("No match found for sales invoice #{sales_invoice.id}")
    end
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
