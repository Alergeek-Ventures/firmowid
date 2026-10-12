defmodule Firmowid.Delegations.Changes.SetSubmittedAt do
  @moduledoc "Sets the immutable UTC submission timestamp for a delegation settlement."

  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.force_change_attribute(
      changeset,
      :submitted_at,
      DateTime.truncate(DateTime.utc_now(), :second)
    )
  end
end
