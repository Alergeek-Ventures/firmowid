defmodule Firmowid.Ash.Blobs.Changes.SetProcessingDefaults do
  @moduledoc """
  Sets blob processing defaults based on processing target.

  - target :none => state :succeeded
  - target :cost_invoice => state :pending
  - target :employment_contract => state :pending
  """
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    target = Ash.Changeset.get_argument(changeset, :processing_target) || :none
    metadata = Ash.Changeset.get_argument(changeset, :processing_metadata) || %{}

    state =
      if target in [:cost_invoice, :employment_contract] do
        :pending
      else
        :succeeded
      end

    changeset
    |> Ash.Changeset.force_change_attribute(:processing_target, target)
    |> Ash.Changeset.force_change_attribute(:processing_state, state)
    |> Ash.Changeset.force_change_attribute(:processing_metadata, metadata)
  end
end
