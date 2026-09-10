defmodule Firmowid.Ash.Invoicing.Services.NipApiClientTest do
  use Firmowid.DataCase

  alias Firmowid.Ash.Invoicing.Services.NipApiClient

  @legal_entity Application.compile_env!(:firmowid, :legal_entity)

  @moduletag capture_log: true
  @nip "5261040828"

  describe "nip api client" do
    test "fetches the org data by nip" do
      Req.Test.stub(:nip_api, fn conn ->
        assert conn.request_path == "/api/search/nip/#{@nip}"

        Req.Test.json(conn, %{
          "result" => %{
            "subject" => %{
              "name" => String.upcase(@legal_entity.official_name),
              "nip" => @nip,
              "statusVat" => "Czynny",
              "workingAddress" => String.upcase(@legal_entity.address)
            }
          }
        })
      end)

      {:ok, org} =
        NipApiClient.fetch_org_data_by_nip("526-104-08-28",
          plug: {Req.Test, :nip_api}
        )

      assert org.name == String.upcase(@legal_entity.official_name)

      assert org.nip == @nip

      assert org.address == String.upcase(@legal_entity.address)
    end

    test "returns not found when the nip is not found" do
      nip = "5261040828"

      Req.Test.stub(:nip_api_not_found, fn conn ->
        Req.Test.json(conn, %{"result" => %{"subject" => nil}})
      end)

      assert {:error, :not_found} =
               NipApiClient.fetch_org_data_by_nip(nip, plug: {Req.Test, :nip_api_not_found})
    end

    test "returns error when the nip is invalid" do
      {:error, :invalid_nip} = NipApiClient.fetch_org_data_by_nip("123")
    end
  end
end
