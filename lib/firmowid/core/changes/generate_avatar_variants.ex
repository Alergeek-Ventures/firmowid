defmodule Firmowid.Core.Changes.GenerateAvatarVariants do
  @moduledoc """
  Queues the small copies of a newly set avatar
  (`Firmowid.Blobs.PictureVariants`), so pages switch to them within seconds
  instead of waiting for the hourly scheduler. The job skips a picture that
  already has them.
  """
  use Ash.Resource.Change

  alias Firmowid.Blobs.Blob

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn changeset, record ->
      if record.avatar_blob_id && Ash.Changeset.changing_attribute?(changeset, :avatar_blob_id) do
        AshOban.run_trigger(
          # A member's organization, or the organization itself.
          %Blob{
            id: record.avatar_blob_id,
            organization_id: Map.get(record, :organization_id, record.id)
          },
          :generate_picture_variants
        )
      end

      {:ok, record}
    end)
  end
end
