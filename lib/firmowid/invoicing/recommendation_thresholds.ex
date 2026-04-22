defmodule Firmowid.Invoicing.RecommendationThresholds do
  @moduledoc """
  Shared helpers and thresholds for invoice matching confidence recommendations.

  This module centralizes all magic numbers used across recommendation views so
  UI chips and indicators stay in sync.
  """

  @confidence_high_threshold 0.92
  @confidence_mid_threshold 0.87
  @highest_green_threshold 0.69

  @type confidence_level :: :manual | :high | :mid | :low | nil

  @doc """
  Returns the confidence thresholds used for matching decisions.

  Returned values are in `0.0..1.0` form.
  """
  @spec thresholds :: %{high: float(), mid: float(), highest_green: float()}
  def thresholds do
    %{
      high: @confidence_high_threshold,
      mid: @confidence_mid_threshold,
      highest_green: @highest_green_threshold
    }
  end

  @doc """
  Classifies a match pair into a chip type and human-readable percentage.

  Manual matches return `{:manual, 100}` regardless of score.
  """
  @spec match_chip_type(float() | nil, atom() | nil) :: {confidence_level(), integer() | nil}
  def match_chip_type(nil, _source), do: {nil, nil}

  def match_chip_type(_score, :manual), do: {:manual, 100}

  def match_chip_type(score, _source) when is_number(score) do
    cond do
      score >= @confidence_high_threshold -> {:high, to_percent(score)}
      score >= @confidence_mid_threshold -> {:mid, to_percent(score)}
      true -> {:low, to_percent(score)}
    end
  end

  def match_chip_type(_score, _source), do: {nil, nil}

  @doc """
  Returns the prediction visual level for a potential transaction candidate.
  """
  @spec prediction_level(float() | nil, boolean()) :: :high | :mid | :low
  def prediction_level(score, is_highest_green) do
    cond do
      is_number(score) && score >= @confidence_high_threshold && is_highest_green -> :high
      is_number(score) && score >= @confidence_mid_threshold -> :mid
      true -> :low
    end
  end

  @doc """
  Returns index of the highest scoring candidate above the green threshold.

  Returns `-1` when no candidate reaches the threshold.
  """
  @spec highest_green_index(list({term(), number() | nil})) :: integer()
  def highest_green_index(candidates) do
    candidates
    |> Enum.with_index()
    |> Enum.filter(fn {{_candidate, score}, _index} ->
      is_number(score) and score >= @highest_green_threshold
    end)
    |> Enum.max_by(
      fn {{_candidate, score}, _index} ->
        score
      end,
      fn -> nil end
    )
    |> case do
      nil -> -1
      {_best, index} -> index
    end
  end

  @doc """
  Converts a 0..1 score to a rounded percent integer.
  """
  @spec to_percent(float()) :: integer()
  def to_percent(score) when is_number(score), do: round(score * 100)
end
