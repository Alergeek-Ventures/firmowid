defmodule Firmowid.Ash.Invoicing.Services.KsefInvoiceDigestWindow do
  @moduledoc """
  Computes the most recently closed KSeF invoice digest window.

  Windows are aligned to Firmowid business cutoffs in the Warsaw timezone:
  09:00, 12:00, 15:00, and 20:00.
  """

  @timezone "Europe/Warsaw"
  @cutoff_hours [9, 12, 15, 20]

  @type t :: %{window_start: DateTime.t(), window_end: DateTime.t()}

  @doc """
  Returns the most recently closed digest window in UTC.
  """
  @spec previous_window(DateTime.t()) :: t()
  def previous_window(now \\ DateTime.utc_now()) do
    local_now = DateTime.shift_zone!(now, @timezone)

    cutoff_datetimes =
      local_now
      |> relevant_dates()
      |> Enum.flat_map(&cutoffs_for_date/1)
      |> Enum.sort(DateTime)

    window_end =
      cutoff_datetimes
      |> Enum.filter(&(DateTime.compare(&1, local_now) in [:lt, :eq]))
      |> List.last() ||
        raise "No past cutoff found for #{DateTime.to_iso8601(local_now)}"

    window_start =
      cutoff_datetimes
      |> Enum.take_while(&DateTime.before?(&1, window_end))
      |> List.last() ||
        raise "No window start found before #{DateTime.to_iso8601(window_end)}"

    %{
      window_start: DateTime.shift_zone!(window_start, "Etc/UTC"),
      window_end: DateTime.shift_zone!(window_end, "Etc/UTC")
    }
  end

  defp relevant_dates(local_now) do
    today = DateTime.to_date(local_now)
    [Date.add(today, -1), today]
  end

  defp cutoffs_for_date(date) do
    Enum.map(@cutoff_hours, fn hour ->
      DateTime.new!(date, Time.new!(hour, 0, 0), @timezone)
    end)
  end
end
