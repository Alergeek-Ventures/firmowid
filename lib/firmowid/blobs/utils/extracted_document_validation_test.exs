defmodule Firmowid.Blobs.Utils.ExtractedDocumentValidationTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias Firmowid.Blobs.Utils.ProcessCostInvoiceBlob
  alias Firmowid.Blobs.Utils.ProcessEmploymentContractBlob

  setup do
    previous_config = Application.get_env(:firmowid, :reducto_api_client)
    previous_client = Application.get_env(:firmowid, :reducto_api_client_module)
    previous_s3 = Application.get_env(:firmowid, :s3)
    Application.delete_env(:firmowid, :reducto_api_client_module)
    Application.put_env(:firmowid, :s3, host: "s3.example.com")
    Application.put_env(:firmowid, :reducto_api_client, extract: [plug: {Req.Test, __MODULE__}])

    on_exit(fn ->
      restore_env(:reducto_api_client, previous_config)
      restore_env(:reducto_api_client_module, previous_client)
      restore_env(:s3, previous_s3)
    end)
  end

  test "rejects incomplete contracts and invalid dates despite the document discriminator" do
    complete = %{
      "document_type" => "employment_contract",
      "starts_at" => "2026-08-10",
      "salary_amount" => 100,
      "salary_currency" => "PLN",
      "signed_at" => nil
    }

    for metadata <- [
          Map.put(complete, "starts_at", nil),
          Map.put(complete, "starts_at", "2026-02-30"),
          Map.put(complete, "signed_at", "not-a-date")
        ] do
      stub_extract(metadata)

      assert {:error, :invalid_document} =
               ProcessEmploymentContractBlob.run_processing("https://example.com/file", nil, [])
    end

    for field <- ~w(salary_amount salary_currency) do
      stub_extract(Map.put(complete, field, nil))

      assert {:error, :missing_salary_metadata} =
               ProcessEmploymentContractBlob.run_processing("https://example.com/file", nil, [])
    end
  end

  test "rejects missing invoice values and impossible calendar dates before persistence" do
    complete = %{
      "document_type" => "cost_invoice",
      "seller" => "Seller",
      "invoice_identifier" => "INV/1",
      "sale_date" => nil,
      "issue_date" => "2026-08-10",
      "due_date" => nil,
      "total_amount" => 100,
      "currency" => "PLN",
      "items_list" => []
    }

    for metadata <- [
          Map.put(complete, "issue_date", "2026-02-30"),
          Map.put(complete, "issue_date", nil),
          Map.put(complete, "seller", nil),
          Map.put(complete, "total_amount", nil)
        ] do
      stub_extract(metadata)

      assert {:error, :invalid_document} =
               ProcessCostInvoiceBlob.run_processing("https://example.com/file", nil, [])
    end
  end

  defp stub_extract(metadata) do
    Req.Test.stub(__MODULE__, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      schema = get_in(Jason.decode!(body), ["instructions", "schema"])
      refute Map.has_key?(schema, "if")
      refute Map.has_key?(schema, "then")
      Req.Test.json(conn, %{result: metadata})
    end)
  end

  defp restore_env(key, nil), do: Application.delete_env(:firmowid, key)
  defp restore_env(key, value), do: Application.put_env(:firmowid, key, value)
end
