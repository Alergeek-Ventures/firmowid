defmodule Firmowid.Ash.Invoicing.Changes.PrepareInvoiceItems do
  @moduledoc "Supplies line ordering and contextual VAT defaults before relationship changes."
  use Ash.Resource.Change

  alias Firmowid.Ash.Invoicing.CountryCodes
  alias Firmowid.Ash.Ksef.VatRate

  @doc "Defaults omitted item indices and VAT rates using the invoice's buyer identity."
  @spec change(Ash.Changeset.t(), keyword(), Ash.Resource.Change.Context.t()) :: Ash.Changeset.t()
  @impl true
  def change(changeset, _opts, _context) do
    case Ash.Changeset.get_argument(changeset, :sales_invoice_items) do
      items when is_list(items) ->
        rate = default_rate(changeset)

        items =
          items
          |> Enum.with_index()
          |> Enum.map(fn {item, index} ->
            item
            |> default_if_nil(:index, index)
            |> default_if_nil(:vat_rate, rate)
          end)

        Ash.Changeset.set_argument(changeset, :sales_invoice_items, items)

      _ ->
        changeset
    end
  end

  defp default_rate(changeset) do
    country = Ash.Changeset.get_attribute(changeset, :buyer_country)
    country = if country, do: CountryCodes.normalize(country), else: "PL"
    pesel = Ash.Changeset.get_attribute(changeset, :buyer_pesel)
    type = Ash.Changeset.get_attribute(changeset, :buyer_type)
    id_type = CountryCodes.tax_id_type(country, pesel, type)

    case VatRate.available_rates(country, id_type) do
      {:fixed, rate} -> rate
      {:select, _rates, rate} -> rate
    end
  end

  defp default_if_nil(item, field, default) do
    key = if Map.has_key?(item, to_string(field)), do: to_string(field), else: field
    if is_nil(item[key]), do: Map.put(item, key, default), else: item
  end
end
