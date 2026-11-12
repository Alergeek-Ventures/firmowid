defmodule Firmowid.Invoicing.Matching.RegressionPredictorTest do
  use ExUnit.Case, async: true

  alias Firmowid.Invoicing.Matching.RegressionPredictor

  # A payment within three days of the invoice, for its exact amount and in its
  # currency, from its counterparty and bank account, quoting its amount and number.
  @good_match_features [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 1.0, 1.0, 1.0, 1.0, 1.0]

  describe "score/1" do
    test "returns a probability for list input" do
      score = RegressionPredictor.score(@good_match_features)

      assert is_float(score)
      assert RegressionPredictor.confident_match?(score)
    end
  end
end
