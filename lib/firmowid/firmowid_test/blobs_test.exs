defmodule Firmowid.BlobsTest do
  use Firmowid.DataCase

  import Firmowid.AccountsFixtures

  alias Firmowid.Blobs
  alias Firmowid.Blobs.Blob

  describe "create_blob/3" do
    test "uploads file to S3 and creates a blob record" do
      user = user_fixture()

      {:ok, path} = Briefly.create()
      File.write!(path, "hello from blob test")

      assert {:ok, %Blob{} = blob} = Blobs.create_blob(path, "text/plain", "test.txt")

      assert blob.original_filename == "test.txt"
      assert blob.organization_id == user.organization_id
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

      assert {:ok, %Blob{blob_checksum: ^expected_checksum}} =
               Blobs.create_blob(path, "application/pdf", "invoice.pdf")
    end
  end

  describe "get_blob!/1" do
    test "retrieves an uploaded blob" do
      _user = user_fixture()

      {:ok, path} = Briefly.create()
      File.write!(path, "get blob test")

      {:ok, blob} = Blobs.create_blob(path, "text/plain", "get-me.txt")

      fetched = Blobs.get_blob!(blob.id)
      assert fetched.id == blob.id
      assert fetched.original_filename == "get-me.txt"
    end
  end

  describe "delete_blob/1" do
    test "deletes blob record and S3 object" do
      _user = user_fixture()

      {:ok, path} = Briefly.create()
      File.write!(path, "delete me")

      {:ok, blob} = Blobs.create_blob(path, "text/plain", "delete-me.txt")

      assert {:ok, _} = Blobs.delete_blob(blob.id)
      assert_raise Ecto.NoResultsError, fn -> Blobs.get_blob!(blob.id) end
    end
  end

  describe "get_blob_url/1" do
    test "returns a presigned URL for the blob" do
      _user = user_fixture()

      {:ok, path} = Briefly.create()
      File.write!(path, "url test")

      {:ok, blob} = Blobs.create_blob(path, "text/plain", "url-test.txt")

      url = Blobs.get_blob_url(blob.id)
      assert url =~ "firmowid-uploads"
      assert url =~ blob.blob_path
      assert url =~ "X-Amz-Signature"
    end
  end
end
