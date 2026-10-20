# credo:disable-for-this-file ExDNA.Credo
# Renderer duplicates branch-specific loading/summary paths for VAT vs KOR correctness;
# flattening this requires larger refactor across XML rendering and correction semantics.
defmodule Firmowid.Ash.Ksef.Services.InvoiceRenderer do
  @moduledoc """
  Renders sales invoices into KSeF FA(3) XML format.

  Handles the full rendering pipeline:
  - Loading required calculations and aggregates (net/vat/gross values)
  - XML escaping of all string values
  - VAT summary calculation (grouped by FA(3) rate field)
  - Correction invoice (KOR) chain resolution and before/after delta computation
  - Validation of correction constraints (buyer tax ID, seller data immutability)

  The XML template is compiled from `fa3_invoice_template.xml.eex` at compile time
  using `EEx.function_from_file/5`.
  """
  alias Firmowid.Ash.Invoicing
  alias Firmowid.Ash.Invoicing.Utilities.SafeTimestamp
  alias Firmowid.Ash.Invoicing.VatExemption
  alias Firmowid.Ash.Ksef.VatRate
  alias Firmowid.Ash.Scope
  alias Firmowid.Ash.SystemActor

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
  def render_fa3(%{__struct__: _, ksef_invoice_kind: _} = invoice), do: render_fa3(invoice, [])

  @spec render_fa3(map(), keyword()) :: iodata()
  def render_fa3(%{__struct__: _, ksef_invoice_kind: _} = invoice, opts) do
    tenant_opts = renderer_opts(invoice, opts)

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
            Keyword.put(tenant_opts, :lazy?, false)
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
            tenant_opts
          )
      end

    reference_invoice = Map.get(invoice, :reference_invoice)

    assigns = [
      invoice: xml_escape(invoice),
      reference_invoice: if(reference_invoice, do: xml_escape(reference_invoice)),
      vat_summary:
        invoice
        |> calculate_vat_summary(reference_invoice)
        |> add_vat_pln(invoice, reference_invoice)
    ]

    do_render(assigns)
  end

  defp renderer_opts(invoice, opts) do
    cond do
      Keyword.has_key?(opts, :scope) ->
        opts

      Keyword.has_key?(opts, :actor) ->
        opts |> Keyword.delete(:tenant) |> Keyword.put(:tenant, invoice.organization_id)

      true ->
        actor = %SystemActor{org_id: invoice.organization_id, role: :sales_invoice_processor}
        scope = %Scope{actor: actor, tenant: invoice.organization_id}

        opts
        |> Keyword.delete(:actor)
        |> Keyword.delete(:tenant)
        |> Keyword.put(:scope, scope)
    end
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

  # FA(3) sums 23% with 22% (P_13_1) and 8% with 7% (P_13_2); every other rate has its own field.
  @rate_groups [["23", "22"], ["8", "7"]]

  # P_14_xW: a foreign-currency invoice's VAT in PLN at the NBP rate, for the groups FA(3)
  # converts (23/22%, 8/7%, 5%, 4%).
  @pln_converted_rates ["23", "22", "8", "7", "5", "4"]

  # One summary per FA(3) field. Each state's group net and VAT are rounded to the grosz
  # first, so a correction (KOR, before/after method) states the change between the amounts
  # its corrected state and its state after show; groups it leaves unchanged are skipped.
  defp calculate_vat_summary(invoice, reference_invoice) do
    {after_items, before_items} = summary_states(invoice, reference_invoice)

    (after_items ++ (before_items || []))
    |> Enum.map(&rate_group(&1.vat_rate))
    |> Enum.uniq()
    |> Enum.map(fn [rate | _] = rates ->
      %{
        rate: rate,
        rates: rates,
        type: VatRate.summary_type(rate),
        net: group_change(after_items, before_items, rates, :net_value),
        vat: group_change(after_items, before_items, rates, :vat_value)
      }
    end)
    |> Enum.reject(&(before_items && Decimal.eq?(&1.net, 0) && Decimal.eq?(&1.vat, 0)))
    |> Enum.sort_by(&VatRate.to_numeric(&1.rate), {:desc, Decimal})
  end

  # A correction's VAT in PLN is the difference of the converted states after and before it.
  defp add_vat_pln(summary, %{currency: "PLN"}, _reference_invoice), do: summary

  defp add_vat_pln(summary, invoice, reference_invoice) do
    if Enum.any?(summary, &(&1.rate in @pln_converted_rates)) do
      %{rate: rate} =
        Invoicing.get_currency_rate(invoice) ||
          raise "NBP exchange rate unavailable for #{invoice.currency} on #{invoice.issue_date}"

      rate = Decimal.from_float(rate)
      {after_items, before_items} = summary_states(invoice, reference_invoice)

      Enum.map(summary, fn group ->
        if group.rate in @pln_converted_rates,
          do: Map.put(group, :vat_pln, pln_change(after_items, before_items, group.rates, rate)),
          else: group
      end)
    else
      summary
    end
  end

  defp summary_states(%{ksef_invoice_kind: :kor, sales_invoice_items: after_items}, %{sales_invoice_items: before_items}),
    do: {after_items, before_items}

  defp summary_states(%{sales_invoice_items: items}, _reference_invoice), do: {items, nil}

  defp rate_group(rate), do: Enum.find(@rate_groups, [rate], &(rate in &1))

  defp group_change(after_items, nil, rates, field), do: group_sum(after_items, rates, field)

  defp group_change(after_items, before_items, rates, field),
    do: Decimal.sub(group_sum(after_items, rates, field), group_sum(before_items, rates, field))

  defp pln_change(after_items, nil, rates, rate), do: to_pln(group_sum(after_items, rates, :vat_value), rate)

  defp pln_change(after_items, before_items, rates, rate),
    do:
      Decimal.sub(
        to_pln(group_sum(after_items, rates, :vat_value), rate),
        to_pln(group_sum(before_items, rates, :vat_value), rate)
      )

  defp group_sum(items, rates, field) do
    items
    |> Enum.filter(&(&1.vat_rate in rates))
    |> Enum.reduce(Decimal.new(0), &Decimal.add(&2, Map.fetch!(&1, field)))
    |> Decimal.round(2)
  end

  defp to_pln(vat, rate), do: vat |> Decimal.mult(rate) |> Decimal.round(2)

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
  # :loan is the CostInvoice atom for FA(3) code "5" (parsed by InvoiceParser);
  # :credit is the SalesInvoice equivalent. Both map to "5".
  def payment_method_code(:loan), do: "5"
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

  def seller_name(_), do: raise(ArgumentError, "Seller name is missing")

  @doc """
  Returns the buyer name for KSeF invoice.

  Priority:
  1. For companies: buyer_full_name (legal name), then buyer_display_name
     (short name) if the legal name is unavailable
  2. For individuals: buyer_display_name (if set), then buyer_given_name +
     buyer_surname

  Returns nil if no name is available (optional in simplified invoices per art. 106e ust. 5 pkt 3).
  """
  @spec buyer_name(map()) :: String.t() | nil
  def buyer_name(%{buyer_type: :company, buyer_full_name: name}) when is_binary(name) and name != "", do: name

  def buyer_name(%{buyer_type: :company, buyer_display_name: name}) when is_binary(name) and name != "", do: name

  def buyer_name(%{buyer_display_name: name}) when is_binary(name) and name != "", do: name

  def buyer_name(%{buyer_type: :individual, buyer_given_name: given_name, buyer_surname: surname})
      when is_binary(given_name) and is_binary(surname) do
    full_name = String.trim("#{given_name} #{surname}")
    if full_name == "", do: nil, else: full_name
  end

  def buyer_name(_), do: nil

  @doc """
  Validates that buyer tax ID hasn't changed in correction invoice.
  Raises if buyer_id differs between correction and corrected invoice. A missing
  tax ID stored as nil or a blank string counts as the same value.

  Per KSeF FA(3) schema: buyer NIP changes require zeroing out the invoice,
  not a simple correction.
  """
  @spec validate_correction_buyer_tax_id!(map()) :: map()
  def validate_correction_buyer_tax_id!(%{ksef_invoice_kind: :kor, corrected_invoice: corrected} = invoice) do
    if blank_to_nil(invoice.buyer_id) != blank_to_nil(corrected.buyer_id) or
         invoice.buyer_id_type != corrected.buyer_id_type do
      raise ArgumentError,
            "Buyer tax ID cannot change in correction invoice. " <>
              "Original: #{inspect(correction_buyer_identity(corrected))}, " <>
              "New: #{inspect(correction_buyer_identity(invoice))}"
    end

    invoice
  end

  def validate_correction_buyer_tax_id!(invoice), do: invoice

  defp correction_buyer_identity(invoice) do
    %{
      buyer_id: invoice.buyer_id,
      buyer_id_type: invoice.buyer_id_type,
      buyer_pesel: invoice.buyer_pesel,
      buyer_type: invoice.buyer_type,
      buyer_country: invoice.buyer_country
    }
  end

  @doc """
  Validates that seller identity hasn't changed in a correction invoice.

  Raises if seller NIP, name, or address differ between the correction and the
  corrected (original) invoice. Missing values stored as nil or blank strings
  count as the same. VAT exemption type/basis may change on purpose and are not
  checked here.
  """
  @spec validate_correction_seller_data!(map()) :: map()
  def validate_correction_seller_data!(%{ksef_invoice_kind: :kor, corrected_invoice: corrected} = invoice) do
    seller_fields = [
      :seller_nip,
      :seller_display_name,
      :seller_name,
      :seller_surname,
      :seller_address
    ]

    seller_data_changed? =
      Enum.any?(seller_fields, &seller_attr_changed?(invoice, corrected, &1))

    if seller_data_changed? do
      raise ArgumentError,
            "Seller data cannot change in correction invoice. " <>
              "Original: #{corrected |> Map.take([:seller_display_name, :seller_name, :seller_surname, :seller_address]) |> inspect()}, " <>
              "New: #{invoice |> Map.take([:seller_display_name, :seller_name, :seller_surname, :seller_address]) |> inspect()}"
    end

    invoice
  end

  def validate_correction_seller_data!(invoice), do: invoice

  defp seller_attr_changed?(invoice, corrected, field) do
    blank_to_nil(Map.get(invoice, field)) != blank_to_nil(Map.get(corrected, field))
  end

  # Invoices stored before the Ash migration may hold blank strings where Ash now stores nil.
  defp blank_to_nil(value) when is_binary(value) do
    if String.trim(value) == "", do: nil, else: value
  end

  defp blank_to_nil(value), do: value

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
      current.vat_rate != reference.vat_rate or
      current.gtu != reference.gtu
  end

  # Builds the correction chain for a KOR invoice, annotating each correction
  # with its reference_invoice. Uses already-loaded data — no Ash.load! calls.
  defp annotate_correction_chain(%{ksef_invoice_kind: :kor} = invoice) do
    original = invoice.corrected_invoice
    corrections = Enum.sort_by(original.corrections, &SafeTimestamp.safe_timestamp/1, DateTime)
    references = [original | corrections]

    # zip/1 intentionally truncates: corrections has N elements, references has N+1.
    # Each correction[i] gets references[i] as its "before" state. The extra reference
    # (last element = last correction) would be for a future correction not yet created.
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
        c.id == invoice.id or SafeTimestamp.safe_after?(c, SafeTimestamp.safe_timestamp(invoice))
      end)
      |> Enum.max_by(&SafeTimestamp.safe_timestamp/1, DateTime, fn -> original end)

    invoice
    |> Map.put(:corrections, annotated)
    |> Map.put(:reference_invoice, my_ref)
    |> Map.put(:corrected_invoice, original)
  end

  @doc "Returns true when the invoice has at least one VAT-exempt (zw) line item."
  @spec has_exempt_items?(map()) :: boolean()
  def has_exempt_items?(%{sales_invoice_items: items}) do
    Enum.any?(items, &(VatRate.summary_type(&1.vat_rate) == :exempt))
  end

  @doc """
  Returns the legal-basis label for an exemption type.

  Delegates to `VatExemption.basis_label/2`.
  """
  @spec exemption_basis_label(atom(), map()) :: String.t()
  def exemption_basis_label(type, invoice) do
    VatExemption.basis_label(type, invoice)
  end
end
