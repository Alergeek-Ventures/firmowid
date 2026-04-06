defmodule Firmowid.Ash.Ksef.VatRateTest do
  @moduledoc """
  Tests for KSeF FA(3) VAT rate logic.

  Validates rate validity checking, numeric conversion, label rendering,
  context-aware rate selection, and VAT summary type derivation.
  """

  use ExUnit.Case, async: true

  alias Firmowid.Ash.Ksef.VatRate

  describe "valid?/1" do
    test "accepts all standard KSeF rates" do
      for rate <- VatRate.valid_rates() do
        assert VatRate.valid?(rate), "Expected #{inspect(rate)} to be valid"
      end
    end

    test "rejects unknown rates" do
      refute VatRate.valid?("25")
      refute VatRate.valid?("10")
      refute VatRate.valid?("")
      refute VatRate.valid?("vat")
    end
  end

  describe "to_numeric/1" do
    test "converts standard rates to Decimal" do
      assert Decimal.eq?(VatRate.to_numeric("23"), Decimal.new(23))
      assert Decimal.eq?(VatRate.to_numeric("8"), Decimal.new(8))
      assert Decimal.eq?(VatRate.to_numeric("5"), Decimal.new(5))
    end

    test "non-numeric rates return zero" do
      for rate <- ["0 KR", "0 WDT", "0 EX", "zw", "oo", "np I", "np II"] do
        assert Decimal.eq?(VatRate.to_numeric(rate), Decimal.new(0)),
               "Expected #{inspect(rate)} to return 0"
      end
    end
  end

  describe "label/1" do
    test "numeric rates include percent sign" do
      assert VatRate.label("23") == "23%"
      assert VatRate.label("8") == "8%"
    end

    test "special rates include description" do
      assert VatRate.label("zw") == "zw (zwolnione)"
      assert VatRate.label("oo") == "oo (odwrotne obciążenie)"
      assert VatRate.label("np I") == "np I (poza terytorium kraju)"
      assert VatRate.label("np II") == "np II (usługi B2B dla UE)"
    end

    test "unknown rate returns itself" do
      assert VatRate.label("unknown") == "unknown"
    end
  end

  describe "short_label/1" do
    test "numeric rates include percent sign" do
      assert VatRate.short_label("23") == "23%"
    end

    test "zero rates all show 0%" do
      assert VatRate.short_label("0 KR") == "0%"
      assert VatRate.short_label("0 WDT") == "0%"
      assert VatRate.short_label("0 EX") == "0%"
    end

    test "special rates show acronym only" do
      assert VatRate.short_label("zw") == "zw"
      assert VatRate.short_label("np II") == "np II"
    end
  end

  describe "available_rates/2" do
    test "Polish buyer gets domestic rates with 23% default" do
      assert {:select, ["23", "8", "5", "zw"], "23"} = VatRate.available_rates("PL", :nip)
    end

    test "EU B2B with VAT ID gets fixed np II" do
      assert {:fixed, "np II"} = VatRate.available_rates("DE", :eu_vat)
      assert {:fixed, "np II"} = VatRate.available_rates("FR", :eu_vat)
    end

    test "EU consumer without VAT ID gets domestic rates" do
      assert {:select, ["23", "8", "5", "zw"], "23"} = VatRate.available_rates("DE", :other)
    end

    test "non-EU buyer gets fixed np I" do
      assert {:fixed, "np I"} = VatRate.available_rates("US", :other)
      assert {:fixed, "np I"} = VatRate.available_rates("US", :eu_vat)
    end
  end

  describe "summary_type/1" do
    test "numeric rates are standard" do
      for rate <- ["23", "22", "8", "7", "5", "4", "3"] do
        assert VatRate.summary_type(rate) == :standard,
               "Expected #{inspect(rate)} to be :standard"
      end
    end

    test "zero rates map to specific types" do
      assert VatRate.summary_type("0 KR") == :zero_domestic
      assert VatRate.summary_type("0 WDT") == :zero_wdt
      assert VatRate.summary_type("0 EX") == :zero_export
    end

    test "special rates map to their types" do
      assert VatRate.summary_type("zw") == :exempt
      assert VatRate.summary_type("oo") == :reverse_charge
      assert VatRate.summary_type("np I") == :not_subject_i
      assert VatRate.summary_type("np II") == :not_subject_ii
    end

    test "raises ArgumentError for unknown rate" do
      assert_raise ArgumentError, ~r/Unknown VAT rate for summary_type/, fn ->
        VatRate.summary_type("99")
      end
    end
  end

  describe "select_options/1" do
    test "returns label-value tuples" do
      options = VatRate.select_options(["23", "8"])
      assert options == [{"23%", "23"}, {"8%", "8"}]
    end
  end

  describe "select_options_short/1" do
    test "returns short label-value tuples" do
      options = VatRate.select_options_short(["23", "zw"])
      assert options == [{"23%", "23"}, {"zw", "zw"}]
    end
  end
end
