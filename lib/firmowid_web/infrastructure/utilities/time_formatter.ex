defmodule FirmowidWeb.Infrastructure.Utilities.TimeFormatter do
  @moduledoc """
  Helper functions for formatting time durations.
  """

  def format_timer(duration, :with_seconds) when is_integer(duration) do
    hours = div(duration, 60 * 60)
    minutes = rem(div(duration, 60), 60)
    seconds = rem(duration, 60)

    "#{pad_time(hours)}:#{pad_time(minutes)}:#{pad_time(seconds)}"
  end

  def format_timer(duration) when is_integer(duration) do
    hours = div(duration, 3600)
    minutes = rem(div(duration, 60), 60)

    "#{pad_time(hours)}:#{pad_time(minutes)}"
  end

  defp pad_time(time), do: time |> Integer.to_string() |> String.pad_leading(2, "0")

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

  @doc """
  Formats a date range compactly, omitting repeated month and year parts.
  """
  @spec format_date_range(Date.t(), Date.t()) :: String.t()
  def format_date_range(%Date{} = start_date, %Date{} = end_date) do
    cond do
      start_date.year == end_date.year and start_date.month == end_date.month ->
        "#{Calendar.strftime(start_date, "%d")}-#{format_date(end_date)}"

      start_date.year == end_date.year ->
        "#{Calendar.strftime(start_date, "%d.%m")}-#{format_date(end_date)}"

      true ->
        "#{format_date(start_date)}-#{format_date(end_date)}"
    end
  end

  def format_date(date, format) do
    Cldr.Date.to_string!(date, Firmowid.Cldr, format: format, locale: "pl")
  end

  @doc """
  Format DateTime as relative Polish time, e.g. "2 dni temu".
  """
  def format_relative_time(datetime, now \\ DateTime.utc_now())

  def format_relative_time(%DateTime{} = datetime, now) do
    seconds =
      now
      |> DateTime.diff(datetime, :second)
      |> max(0)

    cond do
      seconds < 60 -> "przed chwilą"
      seconds < 3600 -> "#{div(seconds, 60)} min temu"
      seconds < 86_400 -> "#{div(seconds, 3600)} godz. temu"
      true -> "#{div(seconds, 86_400)} dni temu"
    end
  end

  def format_relative_time(%NaiveDateTime{} = datetime, now) do
    datetime
    |> DateTime.from_naive!("Etc/UTC")
    |> format_relative_time(now)
  end
end
