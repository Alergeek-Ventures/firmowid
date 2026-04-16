defmodule Firmowid.Ash.Invoicing.Matching.RateDateTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias Firmowid.Ash.Invoicing.Matching.RateDate

  describe "normalize_rate_date/1" do
    test "keeps past dates unchanged" do
      date = ~D[2025-01-15]

      assert RateDate.normalize_rate_date(date) == date
    end

    test "caps future dates to yesterday" do
      future_date = Date.shift(Date.utc_today(), day: 10)
      yesterday = Date.shift(Date.utc_today(), day: -1)

      assert RateDate.normalize_rate_date(future_date) == yesterday
    end
  end
end
