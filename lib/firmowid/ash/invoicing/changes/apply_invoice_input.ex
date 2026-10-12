defmodule Firmowid.Ash.Invoicing.Changes.ApplyInvoiceInput do
  @moduledoc "Applies typed document input through the owning invoice action's accepted fields."
  use Ash.Resource.Change

  @doc "Casts accepted fields and forwards supplied line items to relationship management."
  @spec change(Ash.Changeset.t(), keyword(), Ash.Resource.Change.Context.t()) :: Ash.Changeset.t()
  @impl true
  def change(changeset, _opts, _context) do
    case Ash.Changeset.get_argument(changeset, :input) do
      nil ->
        changeset

      input ->
        changeset =
          Ash.Changeset.change_attributes(changeset, Map.take(input, changeset.action.accept))

        case Map.fetch(input, :sales_invoice_items) do
          {:ok, items} -> Ash.Changeset.set_argument(changeset, :sales_invoice_items, items)
          :error -> changeset
        end
    end
  end
end
