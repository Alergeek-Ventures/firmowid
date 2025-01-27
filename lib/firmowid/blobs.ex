defmodule Firmowid.Blobs do
  require Logger

  alias ExAws.S3
  alias MIME

  alias Firmowid.Repo
  alias Firmowid.Documents.Blob

  @doc """
  Creates a new blob record and uploads the associated file to S3 storage.
  """
  @spec create_blob(any(), String, String) ::
          {:ok, Ecto.Schema.t()} | {:error, Ecto.Changeset.t()}
  def create_blob(upload_path, content_type, original_filename) do
    organization_id = Repo.get_org_id()
    possible_extensions = MIME.extensions(content_type)
    extension = Enum.at(possible_extensions, 0, "pdf")
    upload_path = preprocess_blob(upload_path, extension)

    blob_id = UUIDv7.autogenerate()

    blob_checksum =
      File.stream!(upload_path, [], 2_048)
      |> Enum.reduce(:crypto.hash_init(:sha256), &:crypto.hash_update(&2, &1))
      |> :crypto.hash_final()
      |> Base.encode16()
      |> String.downcase()

    blob_path = "#{organization_id}/#{Path.basename("#{blob_id}.#{extension}")}"

    upload_path
    |> S3.Upload.stream_file()
    |> S3.upload(
      Application.get_env(:firmowid, :uploads_bucket),
      blob_path
    )
    |> ExAws.request!()

    %Blob{}
    |> Blob.changeset(%{
      id: blob_id,
      blob_path: blob_path,
      blob_checksum: blob_checksum,
      original_filename: original_filename,
      organization_id: organization_id
    })
    |> Repo.insert()
  end

  def get_blob!(id, organization_id) do
    Blob
    |> Repo.get!(id, organization_id: organization_id)
  end

  def delete_blob(id) do
    delete_blob(id, Repo.get_org_id())
  end

  def delete_blob(id, organization_id) do
    blob =
      Blob
      |> Repo.get!(id, organization_id: organization_id)

    Repo.transaction(fn ->
      blob |> Repo.delete!()

      S3.delete_object(
        to_string(Application.get_env(:firmowid, :uploads_bucket)),
        to_string(blob.blob_path)
      )
      |> ExAws.request!()
    end)
  end

  @spec get_blob_url(any()) :: <<_::64, _::_*8>>
  def get_blob_url(id) do
    get_blob_url(id, Repo.get_org_id())
  end

  def get_blob_url(id, organization_id) do
    blob =
      if organization_id == :skip_organization_id do
        Repo.get!(Blob, id, skip_organization_id: true)
      else
        Repo.get!(Blob, id, organization_id: organization_id)
      end

    {:ok, url} =
      :s3
      |> ExAws.Config.new([])
      |> S3.presigned_url(
        :get,
        Application.get_env(:firmowid, :uploads_bucket),
        blob.blob_path,
        expires_in: 200
      )

    url
  end

  def preprocess_blob(path, "pdf"), do: path

  # we only allow pdf and image/* in the upload
  def preprocess_blob(path, image_extension), do: shrink_image(path, image_extension)

  def shrink_image(image_path, image_extension) do
    with {:ok, path} <- Briefly.create(),
         image = Image.open!(image_path) do
      width = Image.width(image)
      height = Image.height(image)

      # Calculate scale while preventing division by zero
      scale =
        cond do
          width == 0 or height == 0 -> 1.0
          width > height -> min(1.0, 1000 / width)
          true -> min(1.0, 1000 / height)
        end

      # Only resize if the image is larger than 1000px
      resized_image =
        if scale < 1.0 do
          Image.resize!(image, scale)
        else
          image
        end

      # Convert stream to binary data before writing
      binary_data =
        resized_image
        |> Image.stream!(suffix: ".#{image_extension}")
        |> Enum.to_list()
        |> IO.iodata_to_binary()

      File.write!(path, binary_data)

      path
    end
  end
end
