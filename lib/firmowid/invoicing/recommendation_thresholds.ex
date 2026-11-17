defmodule Firmowid.Invoicing.RecommendationThresholds do
  @moduledoc """
  Shared helpers and thresholds for invoice matching confidence recommendations.

  This module centralizes all magic numbers used across recommendation views so
  UI chips and indicators stay in sync.
  """

  @confidence_high_threshold 0.92
  @confidence_mid_threshold 0.87
  @highest_green_threshold 0.69

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
