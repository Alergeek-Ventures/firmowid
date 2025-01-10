defmodule Firmowid.NipTest do
  use Firmowid.DataCase

  alias Firmowid.Invoices.NipApiClient

  describe "nip api client" do
    test "fetches the org data by nip" do
      {:ok, org} = NipApiClient.fetch_org_data_by_nip("6793209719")

      assert org.name ==
               "ALERGEEK VENTURES SPÓŁKA Z OGRANICZONĄ ODPOWIEDZIALNOŚCIĄ"

      assert org.nip == "6793209719"
      assert org.address == "JANA KANTEGO FEDEROWICZA 5/96, 30-392 KRAKÓW"
    end

    test "returns not found when the nip is not found" do
      {:error, :not_found} = NipApiClient.fetch_org_data_by_nip("1234567890")
    end

    test "returns error when the nip is invalid" do
      {:error, :invalid_nip} = NipApiClient.fetch_org_data_by_nip("123")
    end
  end
end
