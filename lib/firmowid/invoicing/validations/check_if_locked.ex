defmodule Firmowid.Invoicing.Validations.CheckIfLocked do
  @moduledoc """
  Ash validation that prevents changes to the issued data of locked invoices.

  The atomic callback checks the persisted lock at write time, even when the
  calling action also uses non-atomic changes or relationship management.
  """
  use Ash.Resource.Validation
  use Gettext, backend: Firmowid.Gettext

  alias Ash.Error.Changes.InvalidAttribute

  @message gettext_noop("the invoice is locked and cannot be modified")

  @impl true
  def validate(changeset, _opts, _context) do
    locked_at = Ash.Changeset.get_data(changeset, :locked_at)

    if is_nil(locked_at) do
      :ok
    else
      {:error, field: :base, message: @message}
    end
  end

  @impl true
  def atomic(_changeset, _opts, _context) do
    {:atomic, [:locked_at], expr(not is_nil(locked_at)),
     expr(error(^InvalidAttribute, %{field: :base, message: ^@message}))}
  end
end
