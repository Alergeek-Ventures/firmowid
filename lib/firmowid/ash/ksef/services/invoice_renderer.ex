defmodule Firmowid.Ash.Ksef.Services.InvoiceRenderer do
  @moduledoc """
  Renders sales invoices into KSeF FA(3) XML format.

  Handles the full rendering pipeline:
  - Loading required calculations and aggregates (net/vat/gross values)
  - XML escaping of all string values
  - VAT summary calculation (grouped by rate and type)
  - Correction invoice (KOR) chain resolution and before/after delta computation
  - Validation of correction constraints (buyer tax ID, seller data immutability)

  The XML template is compiled from `fa3_invoice_template.xml.eex` at compile time
  using `EEx.function_from_file/5`.
  """
  alias Firmowid.Ash.Ksef.VatRate

  require EEx

  @item_calcs [:net_value, :vat_value, :gross_value]
  @invoice_aggs [:net_value, :vat_value, :gross_value]
  @invoice_calcs [:buyer_id_type]

  @doc """
  Renders the FA(3) XML template with the given sales invoice.

  Loads required calculations/aggregates, handles correction chain annotation,
  validates correction constraints, and delegates to the compiled EEx template.
  """
  @spec render_fa3(map()) :: iodata()
  def render_fa3(%{__struct__: _, ksef_invoice_kind: _} = invoice) do
    tenant = invoice.organization_id

    invoice =
      case invoice do
        %{ksef_invoice_kind: :kor} ->
          invoice
          |> Ash.load!(
            @invoice_aggs ++
              @invoice_calcs ++
              [
                sales_invoice_items: @item_calcs,
                corrected_invoice:
                  @invoice_aggs ++
                    @invoice_calcs ++
                    [
                      sales_invoice_items: @item_calcs,
                      corrections: @invoice_aggs ++ @invoice_calcs ++ [sales_invoice_items: @item_calcs]
                    ]
              ],
            authorize?: false,
            actor: %{},
            tenant: tenant,
            lazy?: false
          )
          |> annotate_correction_chain()
          |> validate_correction_buyer_tax_id!()
          # for now we raise because edit view does not allow for changing seller data
          # change in seller data should be intentional and not automatic like in creator
          |> validate_correction_seller_data!()

        invoice ->
          Ash.load!(
            invoice,
            @invoice_aggs ++ @invoice_calcs ++ [sales_invoice_items: @item_calcs],
            authorize?: false,
            actor: %{},
            tenant: tenant
          )
      end

    reference_invoice = Map.get(invoice, :reference_invoice)

    assigns = [
      invoice: xml_escape(invoice),
      reference_invoice: if(reference_invoice, do: xml_escape(reference_invoice)),
      vat_summary: calculate_vat_summary(invoice, reference_invoice)
    ]

    do_render(assigns)
  end

  EEx.function_from_file(
    :defp,
    :do_render,
    "lib/firmowid/ash/ksef/services/fa3_invoice_template.xml.eex",
    [:assigns],
    trim: true
  )

  defp xml_escape(%{__struct__: _} = invoice) do
    invoice
    |> Map.from_struct()
    |> Map.new(fn
      {:sales_invoice_items, items} when is_list(items) ->
        {:sales_invoice_items, xml_escape_items(items)}

      {:corrected_invoice, %{__struct__: _} = corrected} ->
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
    Enum.map(items, fn %{__struct__: _} = item ->
      item
      |> Map.from_struct()
      |> Map.new(fn
        {key, value} when is_binary(value) -> {key, xml_escape(value)}
        other -> other
      end)
    end)
  end

  @doc "Formats a decimal value to 2 decimal places for KSeF XML monetary fields."
  @spec format_decimal(Decimal.t() | number() | nil) :: String.t()
  def format_decimal(nil), do: "0.00"
  def format_decimal(%Decimal{} = value), do: value |> Decimal.round(2) |> Decimal.to_string()

  def format_decimal(value) when is_number(value), do: :erlang.float_to_binary(value / 1, decimals: 2)

  @doc """
  Formats quantity values with up to 6 decimal places (TIlosci type in XSD).
  Uses normal notation (not scientific) as required by XSD.
  """
  @spec format_quantity(Decimal.t() | number()) :: String.t()
  def format_quantity(%Decimal{} = value) do
    # Use :normal to avoid scientific notation (e.g., "1E+2" -> "100")
    Decimal.to_string(value, :normal)
  end

  def format_quantity(value) when is_number(value), do: :erlang.float_to_binary(value / 1, decimals: 6)

  @doc """
  Formats VAT rate for P_12 field in KSeF invoice.

  Since vat_rate is now stored as a KSeF-compliant string code
  (e.g., "23", "8", "0 KR", "oo", "np I"), this is a simple passthrough.
  """
  @spec format_vat_rate(String.t()) :: String.t()
  def format_vat_rate(rate) when is_binary(rate), do: rate

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
  # add `vat_pln` to the summary map using `Firmowid.Ash.Currencies.Converter.normalize_amount_to_pln/3`
  # with the rate date from `SalesInvoice.get_currency_conversion_date/1`.

  # For correction invoices (KOR) with before/after method, calculate delta (after - before)
  # Uses the reference invoice (previous correction or original) as the "before" state.
  defp calculate_vat_summary(%{ksef_invoice_kind: :kor, sales_invoice_items: after_items}, %{
         sales_invoice_items: before_items
       }) do
    before_summary = items_to_summary_map(before_items)
    after_summary = items_to_summary_map(after_items)

    # Merge all rate keys from both before and after
    all_keys =
      MapSet.union(MapSet.new(Map.keys(before_summary)), MapSet.new(Map.keys(after_summary)))

    all_keys
    |> Enum.map(fn {rate, type} = key ->
      before = Map.get(before_summary, key, %{net: Decimal.new(0), vat: Decimal.new(0)})
      after_vals = Map.get(after_summary, key, %{net: Decimal.new(0), vat: Decimal.new(0)})

      %{
        rate: rate,
        type: type,
        net: Decimal.sub(after_vals.net, before.net),
        vat: Decimal.sub(after_vals.vat, before.vat)
      }
    end)
    |> Enum.reject(fn summary ->
      # Skip rates where both net and vat are zero (no change)
      Decimal.eq?(summary.net, 0) and Decimal.eq?(summary.vat, 0)
    end)
    |> Enum.sort_by(&VatRate.to_numeric(&1.rate), {:desc, Decimal})
  end

  # Regular invoice VAT summary
  defp calculate_vat_summary(%{sales_invoice_items: items}, _reference_invoice) do
    items
    |> Enum.group_by(fn item ->
      {item.vat_rate, VatRate.summary_type(item.vat_rate)}
    end)
    |> Enum.map(fn {{rate, type}, group_items} ->
      net = Enum.reduce(group_items, Decimal.new(0), &Decimal.add(&2, &1.net_value))
      vat = Enum.reduce(group_items, Decimal.new(0), &Decimal.add(&2, &1.vat_value))

      %{
        rate: rate,
        type: type,
        net: net,
        vat: vat
      }
    end)
    |> Enum.sort_by(&VatRate.to_numeric(&1.rate), {:desc, Decimal})
  end

  # Helper to build a summary map keyed by {rate, type}
  defp items_to_summary_map(items) do
    items
    |> Enum.group_by(fn item ->
      {item.vat_rate, VatRate.summary_type(item.vat_rate)}
    end)
    |> Map.new(fn {{rate, type} = key, group_items} ->
      net = Enum.reduce(group_items, Decimal.new(0), &Decimal.add(&2, &1.net_value))
      vat = Enum.reduce(group_items, Decimal.new(0), &Decimal.add(&2, &1.vat_value))
      {key, %{rate: rate, type: type, net: net, vat: vat}}
    end)
  end

  @doc """
  Renders the buyer identification XML fragment for FA(3) Podmiot2/Podmiot2K.

  Returns an iodata XML fragment containing the appropriate identification element
  (`NIP`, `KodUE`+`NrVatUE`, `KodKraju`+`NrID`, or `BrakID`) based on the
  invoice's `buyer_id_type`.

  Used by the EEx template to avoid duplicating the buyer ID switch logic
  between Podmiot2 (current buyer) and Podmiot2K (previous buyer in corrections).
  """
  @spec buyer_id_xml(map()) :: String.t()
  def buyer_id_xml(%{buyer_id_type: :nip} = inv), do: "<NIP>#{inv.buyer_id}</NIP>"

  def buyer_id_xml(%{buyer_id_type: :eu_vat} = inv),
    do: "<KodUE>#{inv.buyer_country}</KodUE><NrVatUE>#{inv.buyer_id}</NrVatUE>"

  def buyer_id_xml(%{buyer_id_type: :other_id} = inv),
    do: country_xml(inv.buyer_country) <> "<NrID>#{inv.buyer_id}</NrID>"

  def buyer_id_xml(%{buyer_id_type: :optional_id, buyer_id: id} = inv) when is_binary(id) and id != "",
    do: country_xml(inv.buyer_country) <> "<NrID>#{id}</NrID>"

  def buyer_id_xml(%{buyer_id_type: :optional_id}), do: "<BrakID>1</BrakID>"

  def buyer_id_xml(%{buyer_id_type: :no_id}), do: "<BrakID>1</BrakID>"

  defp country_xml(nil), do: ""
  defp country_xml(country), do: "<KodKraju>#{country}</KodKraju>"

  @doc """
  Calculates the gross value delta for correction invoices (KOR).
  Returns after_gross - before_gross, using the reference invoice as the "before" state.
  """
  @spec gross_value_delta(map(), map()) :: Decimal.t()
  def gross_value_delta(invoice, reference_invoice) do
    after_gross = invoice.gross_value
    before_gross = reference_invoice.gross_value
    Decimal.sub(after_gross, before_gross)
  end

  @doc "Converts a payment method atom to the FA(3) numeric code string."
  @spec payment_method_code(atom()) :: String.t()
  def payment_method_code(:cash), do: "1"
  def payment_method_code(:card), do: "2"
  def payment_method_code(:voucher), do: "3"
  def payment_method_code(:check), do: "4"
  def payment_method_code(:credit), do: "5"
  def payment_method_code(:transfer), do: "6"
  def payment_method_code(:mobile), do: "7"
  # Fallback for nil or unexpected values - default to transfer
  def payment_method_code(_), do: "6"

  @doc "Returns the seller name for KSeF invoice. Prefers `seller_display_name`, falls back to name+surname."
  @spec seller_name(map()) :: String.t()
  def seller_name(%{seller_display_name: name}) when is_binary(name) and name != "", do: name

  def seller_name(%{seller_name: name, seller_surname: surname}) when is_binary(name) and is_binary(surname) do
    String.trim("#{name} #{surname}")
  end

  def seller_name(_), do: raise("Seller name is missing")

  @doc """
  Returns the buyer name for KSeF invoice.

  Priority:
  1. buyer_display_name (if set) - user's preferred short name
  2. For companies: buyer_full_name (legal name)
  3. For individuals: buyer_given_name + buyer_surname

  Returns nil if no name is available (optional in simplified invoices per art. 106e ust. 5 pkt 3).
  """
  @spec buyer_name(map()) :: String.t() | nil
  def buyer_name(%{buyer_display_name: name}) when is_binary(name) and name != "", do: name

  def buyer_name(%{buyer_type: :company, buyer_full_name: name}) when is_binary(name) and name != "", do: name

  def buyer_name(%{buyer_type: :individual, buyer_given_name: given_name, buyer_surname: surname})
      when is_binary(given_name) and is_binary(surname) do
    full_name = String.trim("#{given_name} #{surname}")
    if full_name == "", do: nil, else: full_name
  end

  def buyer_name(_), do: nil

  @doc """
  Validates that buyer tax ID hasn't changed in correction invoice.
  Raises if buyer_id differs between correction and corrected invoice.

  Per KSeF FA(3) schema: buyer NIP changes require zeroing out the invoice,
  not a simple correction.
  """
  @spec validate_correction_buyer_tax_id!(map()) :: map()
  def validate_correction_buyer_tax_id!(%{ksef_invoice_kind: :kor, corrected_invoice: corrected} = invoice) do
    if invoice.buyer_id != corrected.buyer_id or
         invoice.buyer_id_type != corrected.buyer_id_type do
      raise "Buyer tax ID cannot change in correction invoice. " <>
              "Original: #{inspect(corrected.buyer_id)}, New: #{inspect(invoice.buyer_id)}"
    end

    invoice
  end

  def validate_correction_buyer_tax_id!(invoice), do: invoice

  @doc """
  Validates that seller data hasn't changed in correction invoice.
  Raises if seller NIP, name, or address differ between correction and corrected invoice.
  """
  @spec validate_correction_seller_data!(map()) :: map()
  def validate_correction_seller_data!(%{ksef_invoice_kind: :kor, corrected_invoice: corrected} = invoice) do
    seller_data_changed? =
      invoice.seller_nip != corrected.seller_nip or
        invoice.seller_display_name != corrected.seller_display_name or
        invoice.seller_name != corrected.seller_name or
        invoice.seller_surname != corrected.seller_surname or
        invoice.seller_address != corrected.seller_address

    if seller_data_changed? do
      raise "Seller data cannot change in correction invoice. " <>
              "Original: #{corrected |> Map.take([:seller_display_name, :seller_name, :seller_surname, :seller_address]) |> inspect()}, " <>
              "New: #{invoice |> Map.take([:seller_display_name, :seller_name, :seller_surname, :seller_address]) |> inspect()}"
    end

    invoice
  end

  def validate_correction_seller_data!(invoice), do: invoice

  @doc """
  Checks if buyer data changed between the current invoice and the reference invoice.
  For correction invoices, the reference is the previous correction (or original if first correction).
  """
  @spec buyer_data_changed?(map(), map()) :: boolean()
  def buyer_data_changed?(invoice, reference_invoice) do
    invoice.buyer_type != reference_invoice.buyer_type or
      invoice.buyer_full_name != reference_invoice.buyer_full_name or
      invoice.buyer_given_name != reference_invoice.buyer_given_name or
      invoice.buyer_surname != reference_invoice.buyer_surname or
      invoice.buyer_display_name != reference_invoice.buyer_display_name or
      invoice.buyer_address != reference_invoice.buyer_address or
      invoice.buyer_country != reference_invoice.buyer_country
  end

  @doc "Fallback: returns `false` when no reference invoice is provided (non-correction context)."
  @spec buyer_data_changed?(map()) :: boolean()
  def buyer_data_changed?(_), do: false

  @doc """
  Checks if invoice items changed between current and reference invoice.
  Returns true if item count differs or any item field differs.

  Compares: name, quantity, unit, unit_price, vat_rate
  Ignores: id (always differs between invoices), timestamps
  """
  @spec invoice_items_changed?(map(), map()) :: boolean()
  def invoice_items_changed?(%{sales_invoice_items: current_items}, %{sales_invoice_items: reference_items}) do
    # If counts differ, items definitely changed
    if length(current_items) == length(reference_items) do
      # Sort both by index and compare each item
      current_sorted = Enum.sort_by(current_items, & &1.index)
      reference_sorted = Enum.sort_by(reference_items, & &1.index)

      current_sorted
      |> Enum.zip(reference_sorted)
      |> Enum.any?(fn {current, reference} -> item_changed?(current, reference) end)
    else
      true
    end
  end

  def invoice_items_changed?(_, _), do: false

  defp item_changed?(current, reference) do
    current.name != reference.name or
      not Decimal.eq?(current.quantity, reference.quantity) or
      current.unit != reference.unit or
      not Decimal.eq?(current.unit_price, reference.unit_price) or
      current.vat_rate != reference.vat_rate
  end

  # Builds the correction chain for a KOR invoice, annotating each correction
  # with its reference_invoice. Uses already-loaded data — no Ash.load! calls.
  defp annotate_correction_chain(%{ksef_invoice_kind: :kor} = invoice) do
    original = invoice.corrected_invoice
    corrections = Enum.sort_by(original.corrections, &safe_timestamp/1, DateTime)
    references = [original | corrections]

    annotated =
      [corrections, references]
      |> Enum.zip()
      |> Enum.map(fn {correction, reference} ->
        correction
        |> Map.put(:reference_invoice, reference)
        |> Map.put(:corrected_invoice, original)
      end)

    # Find the reference for this specific KOR
    my_ref =
      corrections
      |> Enum.reject(fn c ->
        c.id == invoice.id or safe_after?(c, safe_timestamp(invoice))
      end)
      |> Enum.max_by(&safe_timestamp/1, DateTime, fn -> original end)

    invoice
    |> Map.put(:corrections, annotated)
    |> Map.put(:reference_invoice, my_ref)
    |> Map.put(:corrected_invoice, original)
  end

  defp safe_timestamp(record) do
    case {record.locked_at, record.inserted_at} do
      {%DateTime{} = ts, _} -> ts
      {_, %DateTime{} = ts} -> ts
      _ -> ~U[1970-01-01 00:00:00Z]
    end
  end

  defp safe_after?(record, %DateTime{} = reference) do
    DateTime.after?(safe_timestamp(record), reference)
  end
end
