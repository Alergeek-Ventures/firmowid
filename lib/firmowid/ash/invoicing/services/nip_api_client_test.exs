defmodule Firmowid.Ash.Invoicing.Services.NipApiClientTest do
  use Firmowid.DataCase

  alias Firmowid.Ash.Invoicing.Services.NipApiClient

  @legal_entity Application.compile_env!(:firmowid, :legal_entity)

  @moduletag capture_log: true

  describe "nip api client" do
    test "fetches the org data by nip" do
      {:ok, org} = NipApiClient.fetch_org_data_by_nip(@legal_entity.nip)

      assert org.name == String.upcase(@legal_entity.official_name)

      assert org.nip == @legal_entity.nip

      assert org.address ==
               @legal_entity.address
               |> String.replace_prefix("ul. ", "")
               |> String.upcase()
    end

    test "returns not found when the nip is not found" do
      {:error, :not_found} = NipApiClient.fetch_org_data_by_nip("1234567890")
    end

    test "returns error when the nip is invalid" do
      {:error, :invalid_nip} = NipApiClient.fetch_org_data_by_nip("123")
    end
  end
end
