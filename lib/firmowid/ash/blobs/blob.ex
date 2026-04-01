defmodule Firmowid.Ash.Blobs.Blob do
  @moduledoc """
  Ash resource for organization-scoped binary objects stored in S3.

  Handles file upload (with image preprocessing), S3 lifecycle, and
  presigned URL generation via the `:url` calculation.
  """
  use Ash.Resource,
    domain: Firmowid.Ash.Blobs,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias Firmowid.Ash.Blobs.Changes.DeleteFromS3
  alias Firmowid.Ash.Blobs.Changes.UploadToS3
  alias Firmowid.Ash.Resource

  require Resource

  postgres do
    table "blobs"
    repo Firmowid.Repo
    migrate? false
  end

  actions do
    defaults [:read]

    create :create_blob do
      description "Upload a file to S3 and create a blob record."

      argument :upload_path, :string, allow_nil?: false
      argument :content_type, :string, allow_nil?: false
      argument :original_filename, :string, allow_nil?: false

      change UploadToS3
    end

    destroy :destroy do
      description "Delete a blob record and clean up the S3 object."
      require_atomic? false

      change DeleteFromS3
    end
  end

  policies do
    policy always() do
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

  identities do
    identity :unique_checksum_per_org, [:blob_checksum, :organization_id]
  end
end
