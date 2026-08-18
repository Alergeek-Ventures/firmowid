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
    test "converts gross unit prices to net unit prices and strips UI-only values" do
      params = %{
        "items" => %{
          "0" => %{
            "quantity" => "2",
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

    test "only converts targeted gross unit prices during validation" do
      params = %{
        "items" => %{
          "0" => %{
            "quantity" => "1",
            "unit_price" => "10.00",
            "gross_value" => "123.00",
            "vat_rate" => "23"
          },
          "1" => %{
            "quantity" => "2",
            "unit_price" => "20.00",
            "gross_value" => "246.00",
            "vat_rate" => "23"
          }
        }
      }

      indexes = MapSet.new(["1"])

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

  describe "gross_value_indexes/3" do
    test "returns indexes for rows that submitted or targeted gross line values" do
      params = %{
        "items" => %{
          "0" => %{"unit_price" => "10.00"},
          "1" => %{"gross_value" => "123.00"},
          "2" => %{"gross_value" => ""}
        }
      }

      assert PriceInput.gross_value_indexes(params, :items, ["items", "0", "gross_value"]) ==
               MapSet.new(["0", "1", "2"])
    end
  end

  describe "update_gross_value_inputs/4" do
    test "keeps submitted gross unit values for display" do
      params = %{
        "items" => %{
          "0" => %{"gross_value" => "100.00", "quantity" => ""}
        }
      }

      assert PriceInput.update_gross_value_inputs(%{}, params, :items, [
               "items",
               "0",
               "gross_value"
             ]) == %{
               "0" => "100.00"
             }
    end

    test "clears stale gross line values when the net price is edited" do
      params = %{
        "items" => %{
          "0" => %{"unit_price" => "10.00"}
        }
      }

      assert PriceInput.update_gross_value_inputs(%{"0" => "100.00"}, params, :items, [
               "items",
               "0",
               "unit_price"
             ]) == %{}
    end
  end
end
