defmodule Firmowid.Ash.Payroll.Validations.ImmutableAppliesFrom do
  @moduledoc "Allows a manual correction to complete a draft, but not move a dated declaration."

  use Ash.Resource.Validation

  @impl true
  def validate(changeset, _opts, _context) do
    previous = changeset.data.applies_from
    current = Ash.Changeset.get_attribute(changeset, :applies_from)

    if is_nil(previous) or is_nil(changeset.data.received_on) or previous == current do
      :ok
    else
      {:error, field: :applies_from, message: "is invalid"}
    end
  end
end
