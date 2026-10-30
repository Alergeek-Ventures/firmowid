defmodule Firmowid.Invoicing.Changes.RequireTransactionIds do
  @moduledoc """
  Ensures an action receives at least one transaction ID.
  """
  use Ash.Resource.Change
  use Gettext, backend: Firmowid.Gettext

  @impl true
  def change(changeset, _opts, _context) do
    case Ash.Changeset.get_argument(changeset, :transaction_ids) do
      transaction_ids when is_list(transaction_ids) and transaction_ids != [] ->
        changeset

      _ ->
        Ash.Changeset.add_error(changeset,
          field: :transaction_ids,
          message: gettext_noop("Select at least one transaction.")
        )
    end
  end
end
