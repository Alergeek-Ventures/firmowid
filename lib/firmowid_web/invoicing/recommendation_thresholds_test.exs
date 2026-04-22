defmodule FirmowidWeb.Invoicing.RecommendationThresholdsTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias Firmowid.Invoicing.RecommendationThresholds

  describe "match_chip_type/2" do
    test "returns manual chip with 100 percent" do
      assert RecommendationThresholds.match_chip_type(0.5, :manual) == {:manual, 100}
    end

    test "uses high chip for values at or above the high threshold" do
      assert RecommendationThresholds.match_chip_type(0.92, :auto) == {:high, 92}
      assert RecommendationThresholds.match_chip_type(0.94, :auto) == {:high, 94}
    end

    test "uses mid chip for values at or above the mid threshold" do
      assert RecommendationThresholds.match_chip_type(0.87, :auto) == {:mid, 87}
      assert RecommendationThresholds.match_chip_type(0.90, :auto) == {:mid, 90}
    end

    test "uses low chip for values below the mid threshold" do
      assert RecommendationThresholds.match_chip_type(0.5, :auto) == {:low, 50}
    end

    test "returns nil when score is nil" do
      assert RecommendationThresholds.match_chip_type(nil, :auto) == {nil, nil}
    end
  end

  describe "prediction_level/2" do
    test "returns high only when highest green and above high threshold" do
      assert RecommendationThresholds.prediction_level(0.92, true) == :high
      assert RecommendationThresholds.prediction_level(0.92, false) == :mid
    end

    test "returns mid when score is between mid and high thresholds" do
      assert RecommendationThresholds.prediction_level(0.87, true) == :mid
    end

    test "returns low otherwise" do
      assert RecommendationThresholds.prediction_level(0.5, true) == :low
      assert RecommendationThresholds.prediction_level(nil, true) == :low
    end
  end

  describe "highest_green_index/1" do
    test "returns -1 when no candidate reaches green threshold" do
      assert RecommendationThresholds.highest_green_index([{"a", 0.1}, {"b", 0.4}, {"c", 0.68}]) ==
               -1
    end

    test "returns index of highest score candidate above green threshold" do
      candidates = [
        {"a", 0.70},
        {"b", 0.95},
        {"c", 0.81}
      ]

      assert RecommendationThresholds.highest_green_index(candidates) == 1
    end
  end

  describe "to_percent/1" do
    test "rounds score to nearest integer percent" do
      assert RecommendationThresholds.to_percent(0.875) == 88
      assert RecommendationThresholds.to_percent(0.874) == 87
    end
  end
end
