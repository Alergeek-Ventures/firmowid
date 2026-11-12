defmodule FirmowidWeb.Analysis.Utilities.Periods do
  @moduledoc "Months and periods of the analysis as its views and the assistant name them."

  use Gettext, backend: Firmowid.Gettext

  @doc "Names a period: a month, a calendar year or a run of months."
  @spec label({Date.t(), Date.t()}) :: String.t()
  def label({month, month}), do: month_name(month, "LLLL y")

  def label({%Date{month: 1, year: year}, %Date{month: 12, year: year}}), do: Integer.to_string(year)

  def label({%Date{year: year} = from, %Date{year: year} = to}),
    do: gettext("%{from} – %{to}", from: month_name(from, "LLLL"), to: month_name(to, "LLLL y"))

  def label({from, to}), do: gettext("%{from} – %{to}", from: month_name(from, "LLLL y"), to: month_name(to, "LLLL y"))

  @doc "A month's capitalized name in a CLDR `format`, such as `LLL` or `LLLL y`."
  @spec month_name(Date.t(), String.t()) :: String.t()
  def month_name(month, format), do: month |> Firmowid.Cldr.Date.to_string!(format: format) |> String.capitalize()
end
