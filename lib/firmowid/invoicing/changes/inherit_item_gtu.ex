defmodule Firmowid.Invoicing.Changes.InheritItemGtu do
  @moduledoc """
  Keeps the GTU of corrected lines on a correction.

  A correction line that does not mention its GTU at all takes the GTU of the corrected
  state's line with the same name, so a correction issued through ChatGPT does not drop
  the markers an imported invoice carries. A line that states its GTU, even as empty,
  keeps it, as does a line whose name matches no single corrected line. The edit form
  and cancellation state the GTU of each line. `PrepareCorrection` stores the corrected
  state as `invoice_reference`.
  """
  use Ash.Resource.Change

  @doc "Fills an unmentioned `gtu` on `sales_invoice_items` from the corrected line of the same name."
  @spec change(Ash.Changeset.t(), keyword(), Ash.Resource.Change.Context.t()) :: Ash.Changeset.t()
  @impl true
  def change(changeset, _opts, _context) do
    with %{sales_invoice_items: reference_items} <- changeset.context[:invoice_reference],
         items when is_list(items) <- Ash.Changeset.get_argument(changeset, :sales_invoice_items) do
      gtus =
        reference_items
        |> Enum.group_by(& &1.name, & &1.gtu)
        |> Map.filter(fn {_name, gtus} -> length(gtus) == 1 end)
        |> Map.new(fn {name, [gtu]} -> {name, gtu} end)

      Ash.Changeset.set_argument(
        changeset,
        :sales_invoice_items,
        Enum.map(items, &inherit(&1, gtus))
      )
    else
      _no_reference_or_items -> changeset
    end
  end

  defp inherit(item, gtus) do
    {name_key, gtu_key} = if Map.has_key?(item, "name"), do: {"name", "gtu"}, else: {:name, :gtu}

    case {Map.has_key?(item, gtu_key), Map.get(gtus, item[name_key])} do
      {false, gtu} when not is_nil(gtu) -> Map.put(item, gtu_key, gtu)
      _stated_or_unmatched -> item
    end
  end
end
