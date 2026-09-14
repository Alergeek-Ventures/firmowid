defmodule Firmowid.Repo.Migrations.MarkStaleProcessingBlobsFailed do
  @moduledoc """
  Marks blobs stuck in `processing` (pre generic-failure-handling) as failed.
  Failed rows are then reaped by the hourly cleanup trigger.
  """
  use Ecto.Migration

  def up do
    execute(~S|
      UPDATE blobs
      SET processing_state = 'failed',
          processing_metadata = '{"error": ":processing_timeout", "error_code": "processing_failed", "error_message": "Nie udało się przetworzyć pliku."}'::jsonb,
          updated_at = NOW()
      WHERE processing_state = 'processing'
        AND processing_target != 'none'
        AND updated_at < NOW() - INTERVAL '1 hour';
    |)
  end

  def down, do: :ok
end
