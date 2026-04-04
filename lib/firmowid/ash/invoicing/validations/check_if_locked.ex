defmodule Firmowid.Ash.Invoicing.Validations.CheckIfLocked do
  @moduledoc """
  Ash validation that prevents modification of locked invoices.

  Returns an error if `locked_at` is not nil on the record being modified.
  """
  use Ash.Resource.Validation

  @impl true
  def validate(changeset, _opts, _context) do
    locked_at = Ash.Changeset.get_data(changeset, :locked_at)

    if is_nil(locked_at) do
      :ok
    else
      {:error, field: :base, message: "faktura jest zablokowana i nie może być modyfikowana"}
    end
  end
end
