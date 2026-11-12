defmodule Firmowid.Invoicing.Matching.RegressionPredictor do
  @moduledoc """
  Frozen logistic-regression model for invoice↔transaction matching.

  The coefficients follow the feature order of `score/1`; to re-train, use the
  Livebook notebook in `training/`.
  """

  alias Firmowid.Invoicing.Matching.ParametrizedResult

  # ───── frozen weights for class 1 ("match") ──────────────

  @coefficients Nx.tensor(
                  [
                    1.507323,
                    0.908488,
                    -0.327662,
                    -2.72797,
                    -0.187719,
                    -7.522048,
                    6.335346,
                    0.856923,
                    1.691756,
                    2.535432,
                    7.129755
                  ],
                  type: {:f, 32}
                )

  @bias -4.639821

  @auto_match_threshold 0.9989

  # ──────────────────────────────────────────────────────────

  @doc """
  Returns the match probability (0.0 to 1.0) of a pair's features, or of a
  feature vector in coefficient order.
  """
  @spec score(%ParametrizedResult{} | list(number()) | Nx.Tensor.t()) :: float()
  def score(%ParametrizedResult{} = features) do
    score([
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
  end

  def score(vec) when is_list(vec) do
    vec
    |> Nx.tensor(type: {:f, 32})
    |> score()
  end

  def score(%Nx.Tensor{} = vec) do
    vec
    |> Nx.dot(@coefficients)
    |> Nx.add(@bias)
    |> Nx.sigmoid()
    |> Nx.to_number()
  end

  @doc """
  Returns true if score ≥ `@auto_match_threshold`. More info in the Livebook notebook.
  """
  @spec confident_match?(float()) :: boolean()
  def confident_match?(score) do
    score >= @auto_match_threshold
  end
end
