defmodule Firmowid.LocalDate do
  @moduledoc """
  Today's date in Poland (Europe/Warsaw), for documents and business days.

  The server clock runs in UTC, where the day changes one or two hours after Polish midnight.
  """

  @timezone "Europe/Warsaw"

  @doc "Returns today's date in Poland."
  @spec today() :: Date.t()
  def today, do: @timezone |> DateTime.now!() |> DateTime.to_date()

  @doc "Returns the date in Poland at a moment in time."
  @spec of(DateTime.t()) :: Date.t()
  def of(%DateTime{} = moment), do: moment |> DateTime.shift_zone!(@timezone) |> DateTime.to_date()

  @doc "Returns the moment the date ends in Poland: midnight of the next day."
  @spec end_of(Date.t()) :: DateTime.t()
  def end_of(%Date{} = date), do: date |> Date.add(1) |> DateTime.new!(~T[00:00:00], @timezone)
end
