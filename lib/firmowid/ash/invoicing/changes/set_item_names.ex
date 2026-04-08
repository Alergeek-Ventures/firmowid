defmodule Firmowid.Ash.Invoicing.Changes.SetItemNames do
  @moduledoc """
  Ash change that denormalizes item names into the `item_names` field.

  After SalesInvoice create/update, loads the persisted items via `Ash.load!/3`
  and concatenates all item names with a space separator. Updates the field via
  a dedicated `:denormalize_item_names` action to avoid triggering another round
  of change callbacks (prevents recursion).
  """
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, context) do
    Ash.Changeset.after_action(changeset, fn _changeset, record ->
      opts =
        context
        |> Ash.Context.to_opts()
        |> Keyword.delete(:tenant)
        |> Keyword.put(:tenant, record.organization_id)

      record = Ash.load!(record, [:sales_invoice_items], opts)

      item_names =
        record.sales_invoice_items
        |> Enum.sort_by(& &1.index)
        |> Enum.map(& &1.name)
        |> Enum.reject(&is_nil/1)
        |> Enum.join(" ")

      updated =
        record
        |> Ash.Changeset.for_update(:denormalize_item_names, %{item_names: item_names}, opts)
        |> Ash.update!()

      {:ok, updated}
    end)
  end
end
