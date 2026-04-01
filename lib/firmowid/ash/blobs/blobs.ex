defmodule Firmowid.Ash.Blobs do
  @moduledoc """
  Ash domain for blob storage.

  Manages file uploads to S3, presigned URL generation, and blob lifecycle.
  Blobs are organization-scoped binary objects (PDFs, images, XML files) used
  by cost invoices, hours records, avatars, and other features.
  """
  use Ash.Domain

  resources do
    resource Firmowid.Ash.Blobs.Blob do
      define :get_blob, action: :read, get_by: [:id]
      define :create_blob, args: [:upload_path, :content_type, :original_filename]
      define :destroy_blob, action: :destroy
    end
  end

  authorization do
    authorize :by_default
    require_actor? true
  end
end
