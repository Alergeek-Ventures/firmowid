defmodule Firmowid.Ash.Invoicing.Matching.RateDate do
  @moduledoc """
  Helpers for choosing exchange-rate dates during invoice matching.
  """

  @doc """
  Caps future matching dates to yesterday, because historic Open Exchange Rates
  are not available for future days.
  """
  @spec normalize_rate_date(Date.t()) :: Date.t()
  def normalize_rate_date(%Date{} = date) do
    yesterday = Date.shift(Date.utc_today(), day: -1)

    case Date.compare(date, yesterday) do
      :gt -> yesterday
      _ -> date
    end
  end
end
