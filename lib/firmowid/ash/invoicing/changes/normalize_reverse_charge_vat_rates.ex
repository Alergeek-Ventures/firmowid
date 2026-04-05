defmodule Firmowid.Ash.Invoicing.Changes.NormalizeReverseChargeVatRates do
  @moduledoc """
  Ash change that normalizes VAT rates on line items based on reverse charge status.

  Works in dual mode:

  - **Attribute mode** (for WizardDraft) — reads/writes items as an attribute
    containing a list of embedded resource structs.
  - **Argument mode** (for SalesInvoice) — reads/writes items as an action argument
    containing a list of maps for `manage_relationship`.

  When `is_reverse_charge` is true, forces all item VAT rates to `"oo"`.
  When switching from reverse charge back to normal, replaces `"oo"` rates
  with the appropriate fallback rate based on buyer context.

  ## Options

    * `:source` — `:attribute` or `:argument` (where to read/write items)
    * `:field` — atom (`:items` for WizardDraft, `:sales_invoice_items` for SalesInvoice)
  """
  use Ash.Resource.Change

  alias Firmowid.Ash.Invoicing.CountryCodes
  alias Firmowid.Ash.Ksef.VatRate

  @impl true
  def change(changeset, opts, _context) do
    source = opts[:source] || :argument
    field = opts[:field] || :items

    items = read_items(changeset, source, field)

    if is_nil(items) or items == [] do
      changeset
    else
      is_reverse_charge = Ash.Changeset.get_attribute(changeset, :is_reverse_charge)
      target_rate = target_rate(changeset, is_reverse_charge)

      normalized = Enum.map(items, &normalize_item(&1, is_reverse_charge, target_rate))

      write_items(changeset, source, field, normalized)
    end
  end

  defp read_items(changeset, :argument, field), do: Ash.Changeset.get_argument(changeset, field)
  defp read_items(changeset, :attribute, field), do: Ash.Changeset.get_attribute(changeset, field)

  defp write_items(changeset, :argument, field, items), do: Ash.Changeset.set_argument(changeset, field, items)

  defp write_items(changeset, :attribute, field, items), do: Ash.Changeset.force_change_attribute(changeset, field, items)

  defp target_rate(_changeset, true), do: "oo"

  defp target_rate(changeset, _) do
    buyer_country = Ash.Changeset.get_attribute(changeset, :buyer_country)
    buyer_pesel = Ash.Changeset.get_attribute(changeset, :buyer_pesel)
    buyer_type = Ash.Changeset.get_attribute(changeset, :buyer_type)

    buyer_id_type = CountryCodes.tax_id_type(buyer_country, buyer_pesel, buyer_type)

    case VatRate.available_rates(buyer_country || "PL", buyer_id_type) do
      {:fixed, rate} -> rate
      {:select, _rates, default_rate} -> default_rate
    end
  end

  defp normalize_item(item, true, target_rate) do
    set_vat_rate(item, target_rate)
  end

  defp normalize_item(item, false, target_rate) do
    current_rate = get_vat_rate(item)

    if current_rate == "oo" do
      set_vat_rate(item, target_rate)
    else
      item
    end
  end

  # Reading vat_rate — handles both structs and maps with atom/string keys
  defp get_vat_rate(%{vat_rate: rate}), do: rate
  defp get_vat_rate(%{"vat_rate" => rate}), do: rate
  defp get_vat_rate(_), do: nil

  # Writing vat_rate — handles both structs and maps with atom/string keys
  defp set_vat_rate(%{__struct__: _} = item, rate), do: %{item | vat_rate: rate}

  defp set_vat_rate(%{} = item, rate) do
    key = if Map.has_key?(item, "vat_rate"), do: "vat_rate", else: :vat_rate
    Map.put(item, key, rate)
  end
end
