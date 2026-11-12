defmodule Firmowid.LocalDate do
  @moduledoc """
  Today's date in Poland (Europe/Warsaw), for documents and business days.

  The server clock runs in UTC, where the day changes one or two hours after Polish midnight.
  """

  @timezone "Europe/Warsaw"

  @doc "Returns today's date in Poland."
  @spec today() :: Date.t()
  def today, do: @timezone |> DateTime.now!() |> DateTime.to_date()
end
