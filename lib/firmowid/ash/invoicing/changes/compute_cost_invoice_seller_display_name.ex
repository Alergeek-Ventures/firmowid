defmodule Firmowid.Ash.Invoicing.Changes.ComputeCostInvoiceSellerDisplayName do
  @moduledoc """
  Computes a stored cost invoice seller display name from invoice contents.

  The value is system-derived and recomputable.

  Failed or blank generations leave the current value unchanged.
  """
  use Ash.Resource.Change

  alias Firmowid.Ash.Invoicing.Services.SellerDisplayNameEnrichment

  @impl true
  def change(changeset, _opts, context) do
    seller = value(changeset, :seller)

    if is_binary(seller) and seller != "" do
      assign_seller_display_name(changeset, context)
    else
      changeset
    end
  end

  defp assign_seller_display_name(changeset, context) do
    seller_display_name =
      SellerDisplayNameEnrichment.generate_display_name(document(changeset),
        current_cost_invoice_id: changeset.data.id,
        ash_opts: Ash.Context.to_opts(context)
      )

    case seller_display_name do
      value when is_binary(value) and value != "" ->
        Ash.Changeset.force_change_attribute(changeset, :seller_display_name, value)

      _ ->
        changeset
    end
  end

  defp document(changeset) do
    %{
      seller: value(changeset, :seller),
      seller_nip: value(changeset, :seller_nip),
      items_list: normalize_items_list(value(changeset, :items_list))
    }
  end

  defp value(changeset, field) do
    Ash.Changeset.get_attribute(changeset, field) || Map.get(changeset.data, field)
  end

  defp normalize_items_list(items_list) when is_list(items_list), do: items_list
  defp normalize_items_list(_), do: []
end
