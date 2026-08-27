defmodule Firmowid.Ash.Blobs.Changes.ValidateProcessingStateTransition do
  @moduledoc """
  Validates allowed processing state transitions on Blob.
  """
  use Ash.Resource.Change

  @impl true
  def change(changeset, opts, _context) do
    to = Keyword.fetch!(opts, :to)
    from = Ash.Changeset.get_attribute(changeset, :processing_state)

    if allowed_transition?(from, to) do
      changeset
    else
      Ash.Changeset.add_error(
        changeset,
        field: :processing_state,
        message: "invalid transition from #{inspect(from)} to #{inspect(to)}"
      )
    end
  end

  defp allowed_transition?(:pending, :processing), do: true
  defp allowed_transition?(:processing, :succeeded), do: true
  defp allowed_transition?(:processing, :failed), do: true
  defp allowed_transition?(:processing, :pending), do: true
  defp allowed_transition?(:failed, :pending), do: true
  defp allowed_transition?(:succeeded, :pending), do: true
  defp allowed_transition?(same, same), do: true
  defp allowed_transition?(_, _), do: false
end
