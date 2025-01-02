defmodule Firmowid.NipTest do
  use Firmowid.DataCase
  import Firmowid.Invoices.NipApiClient

  describe "nip api client" do
    test "fetches the org data by nip" do
      {:ok, org} = fetch_org_data_by_nip("6793209719")

      assert org.name ==
               "ALERGEEK VENTURES SPÓŁKA Z OGRANICZONĄ ODPOWIEDZIALNOŚCIĄ"
    end

    test "returns not found when the nip is not found" do
      {:error, :not_found} = fetch_org_data_by_nip("1234567890")
    end

    test "returns error when the nip is invalid" do
      {:error, :invalid_nip} = fetch_org_data_by_nip("123")
    end

    test "parses the address info" do
      response = generate_address_info("MARSZAŁKOWSKA 80/116, 00-517 WARSZAWA")

      assert response == %{
               "city" => "Warszawa",
               "postal_code" => "00-517",
               "street" => "Marszałkowska 80/116"
             }
    end

    test "fills missing info with empty strings" do
      response = generate_address_info("MARSZAŁKOWSKA 80/116")

      assert response == %{
               "city" => "",
               "postal_code" => "",
               "street" => "Marszałkowska 80/116"
             }
    end
  end
end
