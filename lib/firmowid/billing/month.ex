defmodule Firmowid.Billing.Month do
  @moduledoc """
  Helpers for billing month markers shared by snapshots and live previews.

  Billing months are always normalized to the first day of the month using
  Europe/Warsaw calendar semantics, so preview screens stay aligned with the
  snapshot month that ultimately drives invoicing.
  """

  @warsaw_timezone "Europe/Warsaw"

  @doc """
  Returns the current billing month marker.
  """
  @spec current() :: Date.t()
  def current do
    @warsaw_timezone
    |> DateTime.now!()
    |> DateTime.to_date()
    |> normalize()
  end

  @doc """
  Returns the marker of the month after the current one: the day a free month
  ends and the first charge falls.
  """
  @spec next() :: Date.t()
  def next, do: Date.shift(current(), month: 1)

  @doc """
  Normalizes a date to the first day of its billing month.
  """
  @spec normalize(Date.t()) :: Date.t()
  def normalize(%Date{} = date), do: Date.beginning_of_month(date)
end
