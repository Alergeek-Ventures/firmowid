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
                    1.003214,
                    0.531963,
                    0.437177,
                    -0.092445,
                    0.440371,
                    -4.901599,
                    3.688719,
                    1.0,
                    1.9359,
                    2.997234,
                    4.546816
                  ],
                  type: {:f, 32}
                )

  @bias -2.120088

  @auto_match_threshold 0.9965

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
