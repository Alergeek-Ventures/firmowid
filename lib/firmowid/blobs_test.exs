defmodule Firmowid.BlobsTest do
  use Firmowid.DataCase

  import Firmowid.AccountsFixtures

  alias Firmowid.Ash.Blobs
  alias Firmowid.Repo

  # TODO: replace authorize?: false with system actor once available
  defp blob_opts, do: [tenant: Repo.get_org_id(), authorize?: false, actor: %{}]

  describe "create_blob" do
    test "uploads file to S3 and creates a blob record" do
      user = user_fixture()

      {:ok, path} = Briefly.create()
      File.write!(path, "hello from blob test")

      assert {:ok, blob} = Blobs.create_blob(path, "text/plain", "test.txt", blob_opts())

      assert blob.original_filename == "test.txt"
      assert blob.blob_path =~ ~r"^#{user.organization_id}/.+\.txt$"
      assert blob.blob_checksum
    end

    test "computes correct SHA-256 checksum" do
      _user = user_fixture()

      content = "deterministic content for checksum"
      {:ok, path} = Briefly.create()
      File.write!(path, content)

      expected_checksum =
        :sha256
        |> :crypto.hash(content)
        |> Base.encode16()
        |> String.downcase()

      assert {:ok, blob} =
               Blobs.create_blob(path, "application/pdf", "invoice.pdf", blob_opts())

      assert blob.blob_checksum == expected_checksum
    end
  end

  describe "get_blob" do
    test "retrieves an uploaded blob" do
      _user = user_fixture()

      {:ok, path} = Briefly.create()
      File.write!(path, "get blob test")

      {:ok, blob} = Blobs.create_blob(path, "text/plain", "get-me.txt", blob_opts())

      fetched = Blobs.get_blob!(blob.id, blob_opts())
      assert fetched.id == blob.id
      assert fetched.original_filename == "get-me.txt"
    end
  end

  describe "destroy_blob" do
    test "deletes blob record and S3 object" do
      _user = user_fixture()

      {:ok, path} = Briefly.create()
      File.write!(path, "delete me")

      {:ok, blob} = Blobs.create_blob(path, "text/plain", "delete-me.txt", blob_opts())

      assert :ok = Blobs.destroy_blob(blob, blob_opts())

      assert_raise Ash.Error.Invalid, fn ->
        Blobs.get_blob!(blob.id, blob_opts())
      end
    end
  end

  describe "url calculation" do
    test "returns a presigned URL for the blob" do
      _user = user_fixture()

      {:ok, path} = Briefly.create()
      File.write!(path, "url test")

      {:ok, blob} = Blobs.create_blob(path, "text/plain", "url-test.txt", blob_opts())

      blob_with_url = Blobs.get_blob!(blob.id, Keyword.put(blob_opts(), :load, [:url]))
      assert blob_with_url.url =~ "firmowid-uploads"
      assert blob_with_url.url =~ blob.blob_path
      assert blob_with_url.url =~ "X-Amz-Signature"
    end
  end
end
