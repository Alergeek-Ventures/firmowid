defmodule Firmowid.Ash.Invoicing.Matching.RegressionPredictorTest do
  use ExUnit.Case, async: true

  alias Firmowid.Ash.Invoicing.Matching.RegressionPredictor

  # Test feature vector that represents a good match
  @good_match_features [
    1.0,
    0.0,
    0.0,
    0.0,
    0.0,
    0.0,
    0.0,
    0.0,
    0.0,
    0.0,
    0.0
  ]

  describe "score/1" do
    test "returns log-odds for list input" do
      score = RegressionPredictor.score(@good_match_features)

      assert is_float(score)
      # Good match should have positive log-odds (higher probability)
      assert score > 0
    end
  end
end
