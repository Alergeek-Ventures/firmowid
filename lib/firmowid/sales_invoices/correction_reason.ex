defmodule Firmowid.SalesInvoices.CorrectionReason do
  @moduledoc """
  Generates a human-readable correction reason by detecting what changed between
  a correction invoice and its reference (the previous state).

  The generated reason is used as `PrzyczynaKorekty` in KSeF FA(3) XML and displayed
  on the rendered invoice (HTML/PDF). For foreign invoices, the reason is bilingual
  (Polish / English).

  The field is optional in the KSeF schema (`TZnakowy`, max 256 chars) but legally
  required by Art. 106j ust. 2 pkt 3 ustawy o VAT.
  """

  alias Firmowid.Ash.Invoicing.SalesInvoice

  @max_length 256

  @type change_type ::
          :cancellation
          | :vat_rate
          | :quantity
          | :price
          | :price_and_quantity
          | :item_name
          | :items_changed
          | :buyer_data
          | :payment_method
          | :sale_date
          | :due_date

  @reasons %{
    cancellation: {"anulowanie faktury", "invoice cancellation"},
    vat_rate: {"korekta stawki VAT", "VAT rate correction"},
    quantity: {"korekta ilości", "quantity correction"},
    price: {"korekta ceny", "price correction"},
    price_and_quantity: {"korekta ceny i ilości", "price and quantity correction"},
    item_name: {"korekta nazwy pozycji", "item name correction"},
    items_changed: {"korekta pozycji na fakturze", "invoice items correction"},
    buyer_data: {"korekta danych nabywcy", "buyer data correction"},
    payment_method: {"korekta formy płatności", "payment method correction"},
    sale_date: {"korekta daty sprzedaży", "sale date correction"},
    due_date: {"korekta terminu płatności", "payment deadline correction"}
  }

  @doc """
  Generates a correction reason string by comparing the current invoice state
  against the reference invoice (previous state in the correction chain).

  Returns a bilingual string for foreign invoices (`:foreign` invoice type),
  Polish-only for domestic invoices (`:poland`).

  Returns an empty string if no changes are detected.

  ## Examples

      iex> generate(zeroed_invoice, reference)
      "Anulowanie faktury"

      iex> generate(price_changed_invoice, reference)
      "Korekta ceny"

      iex> generate(foreign_price_changed, reference)
      "Korekta ceny / Price correction"
  """
  @spec generate(SalesInvoice.t() | map(), SalesInvoice.t() | map()) :: String.t()
  def generate(invoice, reference_invoice) do
    change_types = detect_changes(invoice, reference_invoice)

    change_types
    |> format_reasons(invoice.invoice_type)
    |> truncate(@max_length)
  end

  @spec detect_changes(map(), map()) :: [change_type()]
  defp detect_changes(invoice, reference) do
    if cancellation?(invoice) do
      [:cancellation]
    else
      []
      |> maybe_add_item_changes(invoice, reference)
      |> maybe_add(:buyer_data, buyer_data_changed?(invoice, reference))
      |> maybe_add(:payment_method, invoice.payment_method != reference.payment_method)
      |> maybe_add(:sale_date, invoice.sale_date != reference.sale_date)
      |> maybe_add(:due_date, invoice.due_date != reference.due_date)
      |> Enum.reverse()
    end
  end

  @spec cancellation?(map()) :: boolean()
  defp cancellation?(%{sales_invoice_items: items}) when is_list(items) do
    items != [] and Enum.all?(items, &Decimal.eq?(&1.quantity, 0))
  end

  defp cancellation?(_), do: false

  @spec maybe_add_item_changes([change_type()], map(), map()) :: [change_type()]
  defp maybe_add_item_changes(acc, invoice, reference) do
    current_items = sorted_items(invoice)
    reference_items = sorted_items(reference)

    if length(current_items) == length(reference_items) do
      changes =
        current_items
        |> Enum.zip(reference_items)
        |> Enum.reduce(MapSet.new(), fn {current, ref}, changes ->
          changes
          |> maybe_put(:vat_rate, current.vat_rate != ref.vat_rate)
          |> maybe_put(:quantity, not Decimal.eq?(current.quantity, ref.quantity))
          |> maybe_put(:price, not Decimal.eq?(current.unit_price, ref.unit_price))
          |> maybe_put(:item_name, current.name != ref.name)
        end)

      # Collapse :quantity + :price into :price_and_quantity
      changes =
        if MapSet.member?(changes, :quantity) and MapSet.member?(changes, :price) do
          changes
          |> MapSet.delete(:quantity)
          |> MapSet.delete(:price)
          |> MapSet.put(:price_and_quantity)
        else
          changes
        end

      # Maintain priority order
      [:vat_rate, :price_and_quantity, :quantity, :price, :item_name]
      |> Enum.filter(&MapSet.member?(changes, &1))
      |> Enum.reverse(acc)
    else
      [:items_changed | acc]
    end
  end

  @spec sorted_items(map()) :: [map()]
  defp sorted_items(%{sales_invoice_items: items}) when is_list(items) do
    Enum.sort_by(items, & &1.index)
  end

  defp sorted_items(_), do: []

  @spec maybe_put(MapSet.t(), atom(), boolean()) :: MapSet.t()
  defp maybe_put(set, _key, false), do: set
  defp maybe_put(set, key, true), do: MapSet.put(set, key)

  @spec maybe_add([change_type()], change_type(), boolean()) :: [change_type()]
  defp maybe_add(acc, _type, false), do: acc
  defp maybe_add(acc, type, true), do: [type | acc]

  @buyer_fields [
    :buyer_type,
    :buyer_id,
    :buyer_full_name,
    :buyer_given_name,
    :buyer_surname,
    :buyer_pesel,
    :buyer_display_name,
    :buyer_address,
    :buyer_country,
    :buyer_is_different_mail_address,
    :buyer_mail_address,
    :buyer_mail_country,
    :buyer_email,
    :buyer_phone,
    :buyer_description
  ]

  @spec buyer_data_changed?(map(), map()) :: boolean()
  defp buyer_data_changed?(invoice, reference) do
    Enum.any?(@buyer_fields, fn field ->
      Map.get(invoice, field) != Map.get(reference, field)
    end)
  end

  @spec format_reasons([change_type()], :poland | :foreign) :: String.t()
  defp format_reasons([], _invoice_type), do: ""

  defp format_reasons(change_types, :poland) do
    change_types
    |> Enum.map(fn type -> elem(@reasons[type], 0) end)
    |> join_and_capitalize()
  end

  defp format_reasons(change_types, :foreign) do
    pl =
      change_types
      |> Enum.map(fn type -> elem(@reasons[type], 0) end)
      |> join_and_capitalize()

    en =
      change_types
      |> Enum.map(fn type -> elem(@reasons[type], 1) end)
      |> join_and_capitalize()

    "#{pl} / #{en}"
  end

  @spec join_and_capitalize([String.t()]) :: String.t()
  defp join_and_capitalize([]), do: ""

  defp join_and_capitalize(parts) do
    parts
    |> Enum.join(", ")
    |> capitalize_first()
  end

  @spec capitalize_first(String.t()) :: String.t()
  defp capitalize_first(<<first::utf8, rest::binary>>), do: String.upcase(<<first::utf8>>) <> rest
  defp capitalize_first(str), do: str

  @spec truncate(String.t(), non_neg_integer()) :: String.t()
  defp truncate(str, max) do
    if String.length(str) <= max do
      str
    else
      String.slice(str, 0, max)
    end
  end
end
