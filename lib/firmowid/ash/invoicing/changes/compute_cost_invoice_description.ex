defmodule Firmowid.Ash.Invoicing.Changes.ComputeCostInvoiceDescription do
  @moduledoc """
  Computes cost invoice description from seller and items list using OpenAI.

  The description is system-derived. Failures are tolerated and leave the
  existing description unchanged (or empty on create).
  """
  use Ash.Resource.Change

  alias Firmowid.Ash.Invoicing.Services.OpenAIEnrichment

  require Logger

  @impl true
  def change(changeset, _opts, _context) do
    seller = value(changeset, :seller)
    items_list = value(changeset, :items_list)

    case {seller, normalize_items_list(items_list)} do
      {seller, items_list} when is_binary(seller) and is_list(items_list) ->
        assign_description(changeset, seller, items_list)

      _ ->
        changeset
    end
  end

  defp assign_description(changeset, seller, items_list) do
    description =
      try do
        OpenAIEnrichment.generate_description(%{"seller" => seller, "items_list" => items_list})
      rescue
        error ->
          Logger.warning("Failed to compute cost invoice description: #{inspect(error)}")
          nil
      end

    case description do
      value when is_binary(value) ->
        Ash.Changeset.force_change_attribute(changeset, :description, String.trim(value))

      _ ->
        changeset
    end
  end

  defp value(changeset, field) do
    Ash.Changeset.get_attribute(changeset, field) || Map.get(changeset.data, field)
  end

  defp normalize_items_list(items_list) when is_list(items_list), do: items_list
  defp normalize_items_list(_), do: []
end
