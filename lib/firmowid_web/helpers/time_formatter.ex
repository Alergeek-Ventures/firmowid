defmodule FirmowidWeb.Helpers.TimeFormatter do
  @moduledoc """
  Helper functions for formatting time durations.
  """

  @doc """
  Format seconds into a human-readable string with hours and minutes.
  Example: "241 h 12 min"
  """
  def format_duration(seconds) do
    hours = div(seconds, 3600)
    minutes = div(rem(seconds, 3600), 60)

    [
      if(hours > 0, do: "#{hours} h"),
      if(minutes > 0, do: "#{minutes} min")
    ]
    |> Enum.filter(& &1)
    |> Enum.join(" ")
  end

  @doc """
  Format seconds into a human-readable string with days, hours, and minutes.
  Example: "2 dni 8 h 32 min"
  """
  def format_duration_with_days(seconds) do
    days = div(seconds, 86400)
    hours = div(rem(seconds, 86400), 3600)
    minutes = div(rem(seconds, 3600), 60)

    [
      if(days > 0, do: "#{days} #{if days == 1, do: "dzień", else: "dni"}"),
      if(hours > 0, do: "#{hours} h"),
      if(minutes > 0, do: "#{minutes} min")
    ]
    |> Enum.filter(& &1)
    |> Enum.join(" ")
  end
end
