defmodule FirmowidWeb.Infrastructure.Utilities.TimeFormatterTest do
  use ExUnit.Case, async: true

  alias FirmowidWeb.Infrastructure.Utilities.TimeFormatter

  describe "format_date_range/2" do
    test "omits repeated month and year" do
      assert TimeFormatter.format_date_range(~D[2026-09-20], ~D[2026-09-26]) == "20-26.09.2026"
    end

    test "omits repeated year" do
      assert TimeFormatter.format_date_range(~D[2026-09-20], ~D[2026-10-01]) == "20.09-01.10.2026"
    end

    test "shows both years when they differ" do
      assert TimeFormatter.format_date_range(~D[2026-12-29], ~D[2027-01-03]) ==
               "29.12.2026-03.01.2027"
    end
  end
end
