defmodule Firmowid.Ash.Invoicing.Changes.SetCostInvoiceAmount do
  @moduledoc """
  Builds the persisted Money amount from the legacy cost-invoice input pair.

  The legacy fields remain the write contract until their data is fully
  backfilled and consumers have moved to `amount`.
  """
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    with %Decimal{} = total_amount <- Ash.Changeset.get_attribute(changeset, :total_amount),
         currency when is_binary(currency) <- Ash.Changeset.get_attribute(changeset, :currency),
         %Money{} = amount <- Money.new(currency, total_amount) do
      Ash.Changeset.force_change_attribute(changeset, :amount, amount)
    else
      _ ->
        Ash.Changeset.add_error(changeset,
          field: :currency,
          message: "must be a valid ISO 4217 currency code"
        )
    end
  end
end
