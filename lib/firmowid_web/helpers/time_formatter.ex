defmodule FirmowidWeb.Helpers.TimeFormatter do
  @moduledoc """
  Helper functions for formatting time durations.
  """

  def format_timer(duration, :with_seconds) when is_integer(duration) do
    hours = div(duration, 60 * 60)
    minutes = rem(div(duration, 60), 60)
    seconds = rem(duration, 60)
    :io_lib.format("~2..0B:~2..0B:~2..0B", [hours, minutes, seconds])
  end

  def format_timer(duration) when is_integer(duration) do
    hours = div(duration, 3600)
    minutes = rem(div(duration, 60), 60)

    :io_lib.format("~2..0B:~2..0B", [hours, minutes])
  end

  @doc """
  Format seconds into a human-readable string with hours and minutes.
  Example: "241 h 12 min"
  """
  def format_duration(seconds) when seconds < 60 do
    "#{seconds} s"
  end

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
  def format_duration(seconds, :with_days) do
    days = div(seconds, 86_400)
    hours = div(rem(seconds, 86_400), 3600)
    minutes = div(rem(seconds, 3600), 60)

    [
      if(days > 0, do: "#{days} #{if days == 1, do: "dzień", else: "dni"}"),
      if(hours > 0, do: "#{hours} h"),
      if(minutes > 0, do: "#{minutes} min")
    ]
    |> Enum.filter(& &1)
    |> Enum.join(" ")
  end

  def format_date(date) when is_binary(date) do
    date
    |> Date.from_iso8601!()
    |> format_date()
  end

  def format_date(date) do
    Calendar.strftime(date, "%d.%m.%Y")
  end

  def format_date(date, format) do
    Cldr.Date.to_string!(date, Firmowid.Cldr, format: format, locale: "pl")
  end
end
