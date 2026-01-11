defmodule Firmowid.Ksef.InvoiceRenderer do
  @moduledoc false
  alias Firmowid.Repo
  alias Firmowid.SalesInvoices.SalesInvoice
  alias Firmowid.SalesInvoices.SalesInvoiceItem

  require EEx

  @doc """
  Renders the FA(3) XML template with the given sales invoice.
  """
  def render_fa3(%SalesInvoice{} = invoice) do
    invoice =
      case invoice do
        %{ksef_invoice_kind: :kor} -> Repo.preload(invoice, [:corrected_invoice, :sales_invoice_items])
        invoice -> Repo.preload(invoice, :sales_invoice_items)
      end

    assigns = [invoice: xml_escape(invoice), vat_summary: calculate_vat_summary(invoice)]

    do_render(assigns)
  end

  EEx.function_from_file(:defp, :do_render, "lib/firmowid/ksef/fa3_invoice_template.xml.eex", [:assigns])

  defp xml_escape(%SalesInvoice{} = invoice) do
    invoice
    |> Map.from_struct()
    |> Map.new(fn
      {:sales_invoice_items, items} when is_list(items) ->
        {:sales_invoice_items, xml_escape_items(items)}

      {:corrected_invoice, %SalesInvoice{} = corrected} ->
        {:corrected_invoice, xml_escape(corrected)}

      {key, value} ->
        value =
          case value do
            value when is_binary(value) -> xml_escape(value)
            %Date{} = value -> Date.to_iso8601(value)
            value -> value
          end

        {key, value}
    end)
  end

  defp xml_escape(nil), do: ""
  defp xml_escape(""), do: ""

  defp xml_escape(value) when is_binary(value) do
    value
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&apos;")
  end

  defp xml_escape(value), do: xml_escape(to_string(value))

  defp xml_escape_items(items) when is_list(items) do
    Enum.map(items, fn %SalesInvoiceItem{} = item ->
      item
      |> Map.from_struct()
      |> Map.new(fn
        {key, value} when is_binary(value) -> {key, xml_escape(value)}
        other -> other
      end)
    end)
  end

  def format_decimal(nil), do: "0.00"
  def format_decimal(%Decimal{} = value), do: value |> Decimal.round(2) |> Decimal.to_string()
  def format_decimal(value) when is_number(value), do: :erlang.float_to_binary(value / 1, decimals: 2)

  @doc """
  Formats quantity values with up to 6 decimal places (TIlosci type in XSD).
  Uses normal notation (not scientific) as required by XSD.
  """
  def format_quantity(%Decimal{} = value) do
    # Use :normal to avoid scientific notation (e.g., "1E+2" -> "100")
    Decimal.to_string(value, :normal)
  end

  def format_quantity(value) when is_number(value), do: :erlang.float_to_binary(value / 1, decimals: 6)

  @doc """
  Formats VAT rate for P_12 field in KSeF invoice.

  Supported rates:
  - Numeric rates: 23, 22, 8, 7, 5, 4, 3, 0
  - Special: "oo" (reverse charge)

  Zero rate (0) always renders as "0 KR" (domestic).
  Reverse charge invoices use "oo" - see format_vat_rate/2.
  """
  def format_vat_rate(%Decimal{} = value) do
    if Decimal.eq?(value, 0) do
      "0 KR"
    else
      value
      |> Decimal.round(0)
      |> Decimal.to_integer()
      |> to_string()
    end
  end

  def format_vat_rate(0), do: "0 KR"

  def format_vat_rate(value) when is_number(value) do
    to_string(round(value))
  end

  def format_vat_rate("oo"), do: "oo"

  @doc """
  Formats VAT rate with explicit type.

  Implemented:
  - :reverse_charge => "oo"
  - :domestic => "0 KR" (for 0% rate)
  - :standard => numeric rate

  Not implemented (will raise):
  - :wdt, :export, :exempt, :not_subject_i, :not_subject_ii
  """
  def format_vat_rate(_rate, :reverse_charge), do: "oo"
  def format_vat_rate(rate, :domestic), do: format_vat_rate(rate)
  def format_vat_rate(rate, :standard), do: format_vat_rate(rate)
  def format_vat_rate(rate, nil), do: format_vat_rate(rate)

  def format_vat_rate(_rate, type) when type in [:wdt, :export, :exempt, :not_subject_i, :not_subject_ii] do
    raise "VAT rate type #{inspect(type)} is not implemented. Only :standard, :domestic, and :reverse_charge are supported."
  end

  # NOTE: P_14_XW (VAT in PLN for foreign currency invoices) is NOT implemented.
  # This field is only required when:
  #   1. Invoice currency != PLN, AND
  #   2. Standard VAT rates apply (23%, 8%, 5%, etc.)
  #
  # In practice, foreign currency invoices are almost always:
  #   - B2B services to EU → reverse charge (oo) → no VAT
  #   - B2B goods to EU → WDT (0 WDT) → 0% VAT
  #   - Export outside EU → export (0 EX) → 0% VAT
  #
  # All these cases have zero VAT, so there's nothing to convert to PLN.
  # If a future use case requires P_14_XW (e.g., B2C to EU consumer with Polish VAT),
  # add `vat_pln` to the summary map using `Firmowid.Currencies.normalize_amount_to_pln/3`
  # with the rate date from `SalesInvoice.get_currency_conversion_date/1`.
  defp calculate_vat_summary(%SalesInvoice{sales_invoice_items: items, is_reverse_charge: is_reverse_charge}) do
    items
    |> Enum.group_by(fn item ->
      rate = item.vat_rate

      type =
        cond do
          is_reverse_charge ->
            if Decimal.eq?(rate, 0) do
              :reverse_charge
            else
              raise "Invalid VAT rate #{Decimal.to_string(rate)} for reverse charge invoice"
            end

          Decimal.eq?(rate, 0) ->
            :domestic

          true ->
            :standard
        end

      {rate, type}
    end)
    |> Enum.map(fn {{rate, type}, group_items} ->
      net = Enum.reduce(group_items, Decimal.new(0), &Decimal.add(&2, SalesInvoiceItem.get_net_value(&1)))
      vat = Enum.reduce(group_items, Decimal.new(0), &Decimal.add(&2, SalesInvoiceItem.get_vat_value(&1)))

      %{
        rate: rate,
        type: type,
        net: net,
        vat: vat
      }
    end)
    |> Enum.sort_by(& &1.rate, {:desc, Decimal})
  end

  def payment_method_code(nil), do: "6"
  def payment_method_code("cash"), do: "1"
  def payment_method_code("card"), do: "2"
  def payment_method_code("transfer"), do: "6"
  def payment_method_code("przelew"), do: "6"
  def payment_method_code(_), do: "6"

  def seller_name(%{seller_display_name: name}) when is_binary(name) and name != "", do: name

  def seller_name(%{seller_name: name, seller_surname: surname}) when is_binary(name) and is_binary(surname) do
    String.trim("#{name} #{surname}")
  end

  def seller_name(_), do: raise("Seller name is missing")

  @doc """
  Returns the buyer name for KSeF invoice.
  For companies: uses buyer_display_name or buyer_name
  For individuals: uses buyer_name + buyer_surname
  Returns nil if no name is available (optional in simplified invoices per art. 106e ust. 5 pkt 3).
  """
  def buyer_name(%{buyer_display_name: name}) when is_binary(name) and name != "", do: name
  def buyer_name(%{buyer_type: :company, buyer_name: name}) when is_binary(name) and name != "", do: name

  def buyer_name(%{buyer_type: :individual, buyer_name: name, buyer_surname: surname})
      when is_binary(name) and is_binary(surname) do
    full_name = String.trim("#{name} #{surname}")
    if full_name == "", do: nil, else: full_name
  end

  def buyer_name(_), do: nil
end
