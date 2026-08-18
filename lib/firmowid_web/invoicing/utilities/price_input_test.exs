defmodule FirmowidWeb.Invoicing.Utilities.PriceInputTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias FirmowidWeb.Invoicing.FormHelpers
  alias FirmowidWeb.Invoicing.Utilities.PriceInput

  describe "net_unit_price_from_gross/2" do
    test "keeps precision when deriving net from gross" do
      net = PriceInput.net_unit_price_from_gross(Decimal.new("100.00"), "23")

      refute Decimal.eq?(net, Decimal.new("81.30"))

      assert Decimal.eq?(
               Decimal.round(Decimal.mult(net, Decimal.new("1.23")), 2),
               Decimal.new("100.00")
             )
    end

    test "leaves zero-tax rates unchanged" do
      assert Decimal.eq?(
               PriceInput.net_unit_price_from_gross(Decimal.new("100.00"), "zw"),
               Decimal.new("100.00")
             )
    end
  end

  describe "normalize_items_params/4" do
    test "converts gross item unit prices to net and strips UI-only mode" do
      params = %{
        "price_input_mode" => "gross",
        "items" => %{
          "0" => %{"unit_price" => "100.00", "vat_rate" => "23"}
        }
      }

      normalized =
        PriceInput.normalize_items_params(params, :items, :gross, &FormHelpers.parse_decimal/1)

      net = normalized["items"]["0"]["unit_price"]

      refute Map.has_key?(normalized, "price_input_mode")
      refute Decimal.eq?(net, Decimal.new("81.30"))

      assert Decimal.eq?(
               Decimal.round(Decimal.mult(net, Decimal.new("1.23")), 2),
               Decimal.new("100.00")
             )
    end
  end
end
