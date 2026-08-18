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

  describe "normalize_gross_value_params/4" do
    test "converts gross line values to net unit prices and strips UI-only values" do
      params = %{
        "items" => %{
          "0" => %{
            "quantity" => "1",
            "unit_price" => "0",
            "gross_value" => "100.00",
            "vat_rate" => "23"
          }
        }
      }

      normalized =
        PriceInput.normalize_gross_value_params(params, :items, &FormHelpers.parse_decimal/1)

      net = normalized["items"]["0"]["unit_price"]

      refute Map.has_key?(normalized["items"]["0"], "gross_value")
      refute Decimal.eq?(net, Decimal.new("81.30"))

      assert Decimal.eq?(
               Decimal.round(Decimal.mult(net, Decimal.new("1.23")), 2),
               Decimal.new("100.00")
             )
    end

    test "only converts targeted gross line values during validation" do
      params = %{
        "items" => %{
          "0" => %{
            "quantity" => "1",
            "unit_price" => "10.00",
            "gross_value" => "123.00",
            "vat_rate" => "23"
          },
          "1" => %{
            "quantity" => "1",
            "unit_price" => "20.00",
            "gross_value" => "246.00",
            "vat_rate" => "23"
          }
        }
      }

      indexes = PriceInput.gross_value_target_indexes(["items", "1", "gross_value"], :items)

      normalized =
        PriceInput.normalize_gross_value_params(
          params,
          :items,
          &FormHelpers.parse_decimal/1,
          indexes
        )

      assert Decimal.eq?(normalized["items"]["0"]["unit_price"], Decimal.new("10.00"))

      assert Decimal.eq?(
               Decimal.round(normalized["items"]["1"]["unit_price"], 2),
               Decimal.new("200.00")
             )

      refute Map.has_key?(normalized["items"]["0"], "gross_value")
      refute Map.has_key?(normalized["items"]["1"], "gross_value")
    end
  end

  describe "gross_value_param_indexes/2" do
    test "returns indexes for rows that submitted gross line values" do
      params = %{
        "items" => %{
          "0" => %{"unit_price" => "10.00"},
          "1" => %{"gross_value" => "123.00"},
          "2" => %{"gross_value" => ""}
        }
      }

      assert PriceInput.gross_value_param_indexes(params, :items) == MapSet.new(["1", "2"])
    end
  end
end
