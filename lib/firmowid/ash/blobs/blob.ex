defmodule Firmowid.Ash.Blobs.Blob do
  @moduledoc """
  Ash resource for organization-scoped binary objects stored in S3.

  Handles file upload (with image preprocessing), S3 lifecycle, and
  presigned URL generation via the `:url` calculation.

  ## Actions

    * `:read` — default read, scoped by multitenancy.
    * `:by_id` — get a single blob by primary key.
    * `:create_blob` — generic action: preprocesses the file, computes a
      SHA-256 checksum, uploads to S3, and inserts the DB record.
    * `:destroy_blob` — generic action: deletes the DB record and the S3
      object inside a transaction.

  ## Convenience functions

    * `get_url!/2` — loads a single blob by ID with the `:url` calculation
      and returns the presigned URL string. Intended as a bridge for callers
      that only have a `blob_id` (e.g. un-migrated Ecto contexts). Dies by
      starvation once those contexts migrate to Ash and can
      `Ash.load!(record, blob: [:url])` directly.
  """
  use Ash.Resource,
    domain: Firmowid.Ash.Blobs,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias ExAws.S3
  alias Firmowid.Ash.Resource
  alias Firmowid.Blobs.Blob, as: EctoBlob

  require Logger
  require Resource

  postgres do
    table "blobs"
    repo Firmowid.Repo
    migrate? false
  end

  code_interface do
    define :by_id, args: [:id], action: :by_id

    define :create_blob,
      args: [:upload_path, :content_type, :original_filename],
      action: :create_blob

    define :destroy_blob, args: [:blob_id], action: :destroy_blob
  end

  actions do
    defaults [:read]

    read :by_id do
      get_by [:id]
    end

    action :create_blob, :struct do
      constraints instance_of: __MODULE__
      description "Upload a file to S3 and create a blob record."

      argument :upload_path, :string, allow_nil?: false
      argument :content_type, :string, allow_nil?: false
      argument :original_filename, :string, allow_nil?: false

      # sobelow_skip ["Traversal.FileModule"]
      # upload_path is a temp file from Briefly or Phoenix uploads — not user-controlled path traversal.
      run fn input, context ->
        organization_id = context.tenant
        upload_path = Path.expand(input.arguments.upload_path)
        content_type = input.arguments.content_type
        original_filename = input.arguments.original_filename

        possible_extensions = MIME.extensions(content_type)
        extension = Enum.at(possible_extensions, 0, "pdf")
        upload_path = preprocess_file(upload_path, extension)

        blob_id = UUIDv7.generate()
        blob_checksum = compute_checksum(upload_path)
        blob_path = "#{organization_id}/#{Path.basename("#{blob_id}.#{extension}")}"

        upload_to_s3!(upload_path, blob_path)

        %EctoBlob{id: blob_id}
        |> EctoBlob.changeset(%{
          blob_path: blob_path,
          blob_checksum: blob_checksum,
          original_filename: original_filename,
          organization_id: organization_id
        })
        |> Firmowid.Repo.insert()
      end
    end

    action :destroy_blob, :struct do
      constraints instance_of: __MODULE__
      description "Delete a blob record and its S3 object."

      argument :blob_id, :uuid_v7, allow_nil?: false

      run fn input, context ->
        blob =
          __MODULE__
          |> Ash.Query.for_read(:by_id, %{id: input.arguments.blob_id},
            tenant: context.tenant,
            authorize?: false,
            actor: context.actor
          )
          |> Ash.read_one!()

        Firmowid.Repo.transaction(fn ->
          Firmowid.Repo.delete!(
            Ecto.Changeset.change(%EctoBlob{
              id: blob.id,
              blob_path: blob.blob_path,
              organization_id: context.tenant
            })
          )

          :firmowid
          |> Application.get_env(:uploads_bucket)
          |> to_string()
          |> S3.delete_object(to_string(blob.blob_path))
          |> ExAws.request!()

          {:ok, blob}
        end)
      end
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if always()
    end

    policy action(:create_blob) do
      authorize_if always()
    end

    policy action(:destroy_blob) do
      authorize_if always()
    end
  end

  multitenancy do
    strategy :attribute
    attribute :organization_id
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :blob_path, :string, public?: true, allow_nil?: false
    attribute :blob_checksum, :string, public?: true, allow_nil?: false
    attribute :original_filename, :string, public?: true, allow_nil?: false

    Resource.firmowid_timestamps()
  end

  relationships do
    belongs_to :organization, Firmowid.Ash.Core.Organization do
      allow_nil? false
    end
  end

  calculations do
    calculate :url, :string, Firmowid.Ash.Blobs.Calculations.BlobUrl
  end

  # ── Convenience functions (bridge for un-migrated contexts) ──────────

  @doc """
  Loads a blob by ID with the `:url` calculation and returns the presigned
  URL string. Bridge helper for callers that only have a `blob_id`.

  Dies by starvation once CostInvoices/Accounts migrate and can load
  `blob: [:url]` through relationships.

  ## Options

    * `:tenant` — organization ID (required when no scope)
    * `:scope` — Ash scope struct
    * `:authorize?` — defaults to `false` for worker compatibility
  """
  @spec get_url!(Ash.UUID.t(), keyword()) :: String.t()
  def get_url!(blob_id, opts \\ []) do
    blob_id
    |> by_id!(opts)
    |> Ash.load!(:url, opts)
    |> Map.get(:url)
  end

  # ── Private helpers ──────────────────────────────────────────────────

  # sobelow_skip ["Traversal.FileModule"]
  # upload_path comes from Briefly temp files, not user input.
  defp compute_checksum(upload_path) do
    upload_path
    |> File.stream!()
    |> Enum.reduce(:crypto.hash_init(:sha256), &:crypto.hash_update(&2, &1))
    |> :crypto.hash_final()
    |> Base.encode16()
    |> String.downcase()
  end

  defp upload_to_s3!(upload_path, blob_path) do
    upload_path
    |> S3.Upload.stream_file()
    |> S3.upload(
      Application.get_env(:firmowid, :uploads_bucket),
      blob_path
    )
    |> ExAws.request!()
  end

  defp preprocess_file(path, extension) when extension in ["jpg", "jpeg", "png", "gif"], do: shrink_image(path, extension)

  defp preprocess_file(path, _extension), do: path

  # sobelow_skip ["Traversal.FileModule"]
  # path is generated by Briefly — OS-managed temp directory, not user input.
  defp shrink_image(image_path, image_extension) do
    with {:ok, path} <- Briefly.create() do
      image = Image.open!(image_path)
      width = Image.width(image)
      height = Image.height(image)

      scale =
        if width > height do
          min(1.0, 1000 / width)
        else
          min(1.0, 1000 / height)
        end

      resized_image =
        if scale < 1.0 do
          Image.resize!(image, scale)
        else
          image
        end

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
