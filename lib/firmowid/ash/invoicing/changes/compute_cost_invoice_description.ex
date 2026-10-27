defmodule Firmowid.Ash.Invoicing.Changes.ComputeCostInvoiceDescription do
  @moduledoc """
  Computes cost invoice description from seller, its display name, the seller
  activity left in the context by `ComputeCostInvoiceSellerDisplayName` and the
  items list using OpenAI.

  The description is system-derived. Failures are tolerated and leave the
  existing description unchanged (or empty on create).
  """
  use Ash.Resource.Change

  alias Firmowid.Ash.Invoicing.Services.OpenAIEnrichment

  @impl true
  def change(changeset, _opts, _context) do
    seller = value(changeset, :seller)
    items_list = normalize_items_list(value(changeset, :items_list))

    cond do
      not is_binary(seller) ->
        changeset

      # Without items the model can only guess what was bought, so an existing
      # description stays.
      items_list == [] and value(changeset, :description) not in [nil, ""] ->
        changeset

      true ->
        assign_description(changeset, seller, items_list)
    end
  end

  defp assign_description(changeset, seller, items_list) do
    description =
      %{
        "seller" => seller,
        "seller_display_name" => value(changeset, :seller_display_name),
        "seller_activity" => changeset.context[:seller_activity],
        "items_list" => items_list
      }
      |> description_generator().generate_description()
      |> String.trim()

    if description == "" do
      changeset
    else
      Ash.Changeset.force_change_attribute(changeset, :description, description)
    end
  end

  defp description_generator do
    Application.get_env(:firmowid, :openai_enrichment_module, OpenAIEnrichment)
  end

  defp value(changeset, field) do
    Ash.Changeset.get_attribute(changeset, field) || Map.get(changeset.data, field)
  end

  defp normalize_items_list(items_list) when is_list(items_list), do: items_list
  defp normalize_items_list(_), do: []
end
