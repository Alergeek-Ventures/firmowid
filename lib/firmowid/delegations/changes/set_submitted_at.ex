defmodule Firmowid.Delegations.Changes.SetSubmittedAt do
  @moduledoc "Sets the immutable UTC submission timestamp for a delegation settlement."

  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    now = DateTime.truncate(DateTime.utc_now(), :second)

    # Approval is bound to this timestamp, so a resubmission must never repeat it.
    submitted_at =
      case changeset.data.submitted_at do
        nil -> now
        previous -> Enum.max([now, DateTime.shift(previous, second: 1)], DateTime)
      end

    Ash.Changeset.force_change_attribute(changeset, :submitted_at, submitted_at)
  end
end
