defmodule Firmowid.Invoicing.EuVatNumberTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias Firmowid.Invoicing.EuVatNumber

  # Synthetic numbers only: 1234567897 is a Luhn-valid organisation number used as an example by python-stdnum.
  describe "Sweden" do
    test "accepts the organisation number followed by 01" do
      assert {:ok, "123456789701"} = EuVatNumber.check("SE", "123456789701")
    end

    test "rejects the organisation number alone and suggests the VAT number" do
      assert {:error, :format, [number: "123456789701"]} = EuVatNumber.check("SE", "1234567897")

      assert {:error, :format, [number: "123456789701"]} =
               EuVatNumber.check("SE", "SE 123456-7897")
    end

    test "rejects a wrong check digit without suggesting a number" do
      assert {:error, :checksum, []} = EuVatNumber.check("SE", "123456789101")
    end
  end

  describe "other countries" do
    test "follows each country's structure" do
      assert {:ok, _number} = EuVatNumber.check("DE", "123456789")
      assert {:ok, _number} = EuVatNumber.check("AT", "U12345678")
      assert {:ok, _number} = EuVatNumber.check("NL", "123456789B01")
      assert {:ok, _number} = EuVatNumber.check("GR", "123456789")
      assert {:error, :format, []} = EuVatNumber.check("NL", "123456789")
    end

    test "rejects separators and lowercase letters, which KSeF would receive as written" do
      assert {:error, :format, [number: "123456789"]} = EuVatNumber.check("DE", "123-456-789")
      assert {:error, :format, [number: "123456789B01"]} = EuVatNumber.check("NL", "123456789b01")
    end

    test "suggests removing the buyer country's prefix" do
      assert {:error, :format, [number: "123456789"]} = EuVatNumber.check("DE", "DE123456789")
      assert {:error, :format, [number: "123456789"]} = EuVatNumber.check("EL", "EL123456789")
    end

    test "suggests the country whose number it is" do
      assert {:error, :format, [{:country, "SE", "123456789701"}]} =
               EuVatNumber.check("DE", "SE123456789701")
    end

    test "leaves Poland and non-EU countries to other rules" do
      assert :not_applicable = EuVatNumber.check("PL", "1234567890")
      assert :not_applicable = EuVatNumber.check("US", "12-3456789")
    end
  end
end
