defmodule Firmowid.Ash.Invoicing.Changes.RequireTransactionIds do
  @moduledoc """
  Ensures an action receives at least one transaction ID.
  """
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    case Ash.Changeset.get_argument(changeset, :transaction_ids) do
      transaction_ids when is_list(transaction_ids) and transaction_ids != [] ->
        changeset

      _ ->
        Ash.Changeset.add_error(changeset,
          field: :transaction_ids,
          message: "Wybierz co najmniej jedną transakcję."
        )
    end
  end
end
