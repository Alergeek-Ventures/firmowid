defmodule Firmowid.Invoicing.Matching.RegressionPredictor do
  @moduledoc """
  Frozen logistic-regression model for invoice↔transaction matching.

  ## Feature order (index ↔ param)

    0  difference_in_days
    1  amount_difference
    2  transaction_side_similarity_jaro_winkler
    3  bank_account_similarity_jaro_winkler
    4  bank_account_similarity_levenshtein
    5  bank_account_similarity_overlap_coefficient
    6  bank_account_similarity_tversky
    7  is_same_currency                      (1.0 / 0.0)
    8  amount_present_in_remittance_info     (1.0 / 0.0)
  """

  # ───── frozen weights for class 1 (“match”) ──────────────
  # (to re-train, use the Livebook notebook from this folder)

  @coefficients Nx.tensor(
                  [
                    0.936972,
                    0.224298,
                    0.03375,
                    0.732368,
                    0.344036,
                    -2.155922,
                    4.250373,
                    1.0,
                    1.908638,
                    2.5067,
                    4.453878
                  ],
                  type: {:f, 32}
                )

  @bias -2.072613

  @auto_match_threshold 0.9964

  # ──────────────────────────────────────────────────────────

  @doc """
  Returns **log-odds** (can be negative / positive) for a single feature vector.
  """
  @spec score(list(number()) | Nx.Tensor.t()) :: float()
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
