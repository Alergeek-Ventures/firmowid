defmodule Firmowid.Repo.Migrations.RenameBlobsChecksumIndexForAshIdentity do
  @moduledoc """
  Renames the blobs checksum unique index to match Ash identity naming.

  This ensures duplicate checksum violations are mapped as structured identity
  errors instead of bubbling up as unknown Ecto constraint errors.
  """
  use Ecto.Migration

  def up do
    execute("DROP INDEX IF EXISTS blobs_unique_checksum_per_org_index")

    execute("""
    ALTER INDEX IF EXISTS blobs_blob_checksum_organization_id_index
    RENAME TO blobs_unique_checksum_per_org_index
    """)
  end

  def down do
    execute("DROP INDEX IF EXISTS blobs_blob_checksum_organization_id_index")

    execute("""
    ALTER INDEX IF EXISTS blobs_unique_checksum_per_org_index
    RENAME TO blobs_blob_checksum_organization_id_index
    """)
  end
end
