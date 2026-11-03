defmodule Firmowid.Blobs.Blob.Persistence do
  @moduledoc "PostgreSQL configuration and checksum data migration for blobs."
  use Spark.Dsl.Fragment, of: Ash.Resource, data_layer: AshPostgres.DataLayer

  postgres do
    table "blobs"
    repo Firmowid.Repo

    custom_statements do
      statement :recalculate_byte_checksums do
        code? true

        up ~S"""
        execute(fn ->
          {:ok, _apps} = Application.ensure_all_started(:req)

          %{rows: blobs} =
            repo().query!("SELECT id::text, blob_path, blob_checksum FROM blobs ORDER BY id FOR UPDATE")

          Enum.each(blobs, fn [id, blob_path, old_checksum] ->
            {:ok, url} = Firmowid.S3Client.presigned_get_url(blob_path)
            response = Req.get!(url, decode_body: false)

            if response.status != 200 do
              raise "Checksum backfill failed for blob #{id}: S3 returned HTTP #{response.status}"
            end

            checksum =
              :sha256
              |> :crypto.hash(response.body)
              |> Base.encode16(case: :lower)

            if checksum != old_checksum do
              %{num_rows: 1} =
                repo().query!(
                  "UPDATE blobs SET blob_checksum = $1 WHERE id = $2::text::uuid AND blob_checksum = $3",
                  [checksum, id, old_checksum]
                )
            end
          end)
        end)
        """

        # Rolling back must not restore the invalid CRLF-normalized fingerprints.
        down ":ok"
      end
    end
  end
end
