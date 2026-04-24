defmodule Firmowid.Ash.Blobs.BlobsTest do
  use Firmowid.DataCase

  import Firmowid.AccountsFixtures

  alias Firmowid.Ash.Blobs
  alias Firmowid.Ash.Blobs.Blob

  setup do
    user = admin_fixture()
    scope = %Firmowid.Ash.Scope{actor: user, tenant: user.organization_id}
    %{user: user, scope: scope}
  end

  describe "create_blob" do
    test "uploads file to S3 and creates a blob record", %{user: user, scope: scope} do
      {:ok, path} = Briefly.create()
      File.write!(path, "hello from blob test")

      assert {:ok, blob} = Blobs.create_blob(path, "text/plain", "test.txt", scope: scope)

      assert blob.original_filename == "test.txt"
      assert blob.blob_path =~ ~r"^#{user.organization_id}/.+\.txt$"
      assert blob.blob_checksum
    end

    test "computes correct SHA-256 checksum", %{scope: scope} do
      content = "deterministic content for checksum"
      {:ok, path} = Briefly.create()
      File.write!(path, content)

      expected_checksum =
        :sha256
        |> :crypto.hash(content)
        |> Base.encode16()
        |> String.downcase()

      assert {:ok, blob} =
               Blobs.create_blob(path, "application/pdf", "invoice.pdf", scope: scope)

      assert blob.blob_checksum == expected_checksum
    end
  end

  describe "get_blob" do
    test "retrieves an uploaded blob", %{scope: scope} do
      {:ok, path} = Briefly.create()
      File.write!(path, "get blob test")

      {:ok, blob} = Blobs.create_blob(path, "text/plain", "get-me.txt", scope: scope)

      fetched = Blobs.get_blob!(blob.id, scope: scope)
      assert fetched.id == blob.id
      assert fetched.original_filename == "get-me.txt"
    end
  end

  describe "destroy_blob" do
    test "deletes blob record and S3 object", %{scope: scope} do
      {:ok, path} = Briefly.create()
      File.write!(path, "delete me")

      {:ok, blob} = Blobs.create_blob(path, "text/plain", "delete-me.txt", scope: scope)

      assert :ok = Blobs.destroy_blob(blob, scope: scope)

      assert_raise Ash.Error.Invalid, fn ->
        Blobs.get_blob!(blob.id, scope: scope)
      end
    end
  end

  describe "url calculation" do
    test "returns a presigned URL for the blob", %{scope: scope} do
      {:ok, path} = Briefly.create()
      File.write!(path, "url test")

      {:ok, blob} = Blobs.create_blob(path, "text/plain", "url-test.txt", scope: scope)

      blob_with_url = Blobs.get_blob!(blob.id, load: [:url], scope: scope)
      assert blob_with_url.url =~ "firmowid-uploads"
      assert blob_with_url.url =~ blob.blob_path
      assert blob_with_url.url =~ "X-Amz-Signature"
    end
  end

  describe "create_or_retry_cost_invoice_blob" do
    test "requeues processing for a duplicate failed cost invoice blob", %{scope: scope} do
      previous_extract_result = Application.get_env(:firmowid, :reducto_extract_result)
      previous_reducto_config = Application.get_env(:firmowid, :reducto_api_client)

      configure_reducto_test_client()

      on_exit(fn ->
        restore_env(:reducto_extract_result, previous_extract_result)
        restore_env(:reducto_api_client, previous_reducto_config)
      end)

      {:ok, path} = Briefly.create()
      File.write!(path, "requeue me")

      Application.put_env(
        :firmowid,
        :reducto_extract_result,
        {:ok, %{"document_type" => "invalid"}}
      )

      assert {:ok, %Blob{} = blob} =
               Blobs.create_or_retry_cost_invoice_blob(path, "text/plain", "retry-me.txt", scope: scope)

      failed_blob = Blobs.get_blob!(blob.id, scope: scope)
      assert failed_blob.processing_state == :failed

      assert {:ok, :blob_reprocessing_started} =
               Blobs.create_or_retry_cost_invoice_blob(
                 path,
                 "text/plain",
                 "retry-me-again.txt",
                 scope: scope
               )
    end
  end

  defp configure_reducto_test_client do
    Application.put_env(
      :firmowid,
      :reducto_api_client,
      upload: [plug: {Req.Test, :reducto_api_client}],
      extract: [plug: {Req.Test, :reducto_api_client}]
    )

    Req.Test.stub(:reducto_api_client, &stub_reducto_request/1)
  end

  defp stub_reducto_request(%{request_path: "/upload"} = conn) do
    Req.Test.json(conn, %{"file_id" => "test-file-id"})
  end

  defp stub_reducto_request(%{request_path: "/extract"} = conn) do
    case Application.fetch_env!(:firmowid, :reducto_extract_result) do
      {:ok, result} ->
        Req.Test.json(conn, %{"result" => result})

      {:error, reason} ->
        Req.Test.json(conn, %{"error" => inspect(reason)})
    end
  end

  defp restore_env(key, nil), do: Application.delete_env(:firmowid, key)
  defp restore_env(key, value), do: Application.put_env(:firmowid, key, value)
end
