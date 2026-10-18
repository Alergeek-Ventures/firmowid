defmodule Firmowid.Ash.Invoicing.Changes.InheritItemGtu do
  @moduledoc """
  Keeps the GTU of corrected lines on a correction.

  A correction line that does not state its GTU takes the GTU of the corrected state's
  line at the same position, so a correction issued from a form or ChatGPT does not drop
  the markers an imported invoice carries. `PrepareCorrection` stores that state as
  `invoice_reference`.
  """
  use Ash.Resource.Change

  @doc "Fills missing `gtu` on `sales_invoice_items` from the corrected state's lines."
  @spec change(Ash.Changeset.t(), keyword(), Ash.Resource.Change.Context.t()) :: Ash.Changeset.t()
  @impl true
  def change(changeset, _opts, _context) do
    with %{sales_invoice_items: reference_items} <- changeset.context[:invoice_reference],
         items when is_list(items) <- Ash.Changeset.get_argument(changeset, :sales_invoice_items) do
      gtus = Map.new(reference_items, &{&1.index, &1.gtu})

      items =
        items
        |> Enum.with_index()
        |> Enum.map(fn {item, position} ->
          inherit(item, Map.get(gtus, index(item, position)))
        end)

      Ash.Changeset.set_argument(changeset, :sales_invoice_items, items)
    else
      _no_reference_or_items -> changeset
    end
  end

  defp inherit(item, nil), do: item

  defp inherit(item, gtu) do
    key = if Map.has_key?(item, "name"), do: "gtu", else: :gtu
    if item[key] in [nil, ""], do: Map.put(item, key, gtu), else: item
  end

  defp index(item, position) do
    case item[:index] || item["index"] do
      nil -> position
      index when is_integer(index) -> index
      index -> String.to_integer(index)
    end
  end
end
