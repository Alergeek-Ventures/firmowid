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
  Normalizes a date to the first day of its billing month.
  """
  @spec normalize(Date.t()) :: Date.t()
  def normalize(%Date{} = date), do: Date.beginning_of_month(date)

  @doc """
  Returns the UTC instants a billing month starts and ends at: the first one is
  inside the month, the second one starts the next month.
  """
  @spec utc_bounds(Date.t()) :: {DateTime.t(), DateTime.t()}
  def utc_bounds(%Date{} = month) do
    local_start =
      month |> NaiveDateTime.new!(~T[00:00:00]) |> DateTime.from_naive!(@warsaw_timezone)

    local_end =
      month
      |> Date.end_of_month()
      |> Date.add(1)
      |> NaiveDateTime.new!(~T[00:00:00])
      |> DateTime.from_naive!(@warsaw_timezone)

    {DateTime.shift_zone!(local_start, "Etc/UTC"), DateTime.shift_zone!(local_end, "Etc/UTC")}
  end
end
