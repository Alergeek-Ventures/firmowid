defmodule FirmowidWeb.Invoicing.SalesInvoices.Components.InvoiceItems do
  @moduledoc """
  Component for editing invoice line items.

  Works with AshPhoenix.Form (WizardState, SalesInvoice).
  The parent view passes a pre-built Phoenix form and the items field name.
  """
  use FirmowidWeb, :html

  import FirmowidUI.Components.Button
  import FirmowidWeb.DesignSystem.Components.CoreComponents
  import FirmowidWeb.Invoicing.FormHelpers, only: [access_forms: 2, parse_decimal: 1]

  alias Firmowid.Currencies.NbpApiClient
  alias Firmowid.Invoicing
  alias Firmowid.Invoicing.SalesInvoiceItem
  alias Firmowid.Ksef.VatRate
  alias FirmowidWeb.Invoicing.Utilities.PriceInput
  alias FirmowidWeb.Invoicing.Utilities.VatExemption
  alias Phoenix.HTML.FormData

  @doc """
  Reads the items suggested in the item name fields of an invoice to the
  counterparty, its own invoiced items first.
  """
  @spec item_suggestions(Firmowid.Scope.t(), Ash.UUID.t() | nil) :: [map()]
  def item_suggestions(scope, counterparty_id) do
    counterparty_id
    |> Invoicing.list_item_suggestions!(scope: scope)
    |> Enum.map(&Map.take(&1, [:name, :quantity, :unit, :unit_price, :currency, :vat_rate]))
  end

  @doc """
  Adds the item of a clicked quick suggestion, from the click's params, in place of
  the first empty item, or after the last one. An item with a name or a price is not
  empty, so a price the user typed is never replaced.
  """
  @spec add_suggested_item(AshPhoenix.Form.t(), atom(), map()) :: AshPhoenix.Form.t()
  def add_suggested_item(form, items_field, click_params) do
    params = Map.take(click_params, ~w(name quantity unit unit_price vat_rate))

    form.forms
    |> access_forms(items_field)
    |> Enum.find_index(
      &(blank?(AshPhoenix.Form.value(&1, :name)) and
          blank?(AshPhoenix.Form.value(&1, :unit_price)))
    )
    |> case do
      nil ->
        AshPhoenix.Form.add_form(form, [items_field], params: params)

      index ->
        AshPhoenix.Form.update_form(
          form,
          [items_field, index],
          &AshPhoenix.Form.validate(&1, Map.merge(&1.params, params))
        )
    end
    # Validates the whole invoice again, so its validity includes the new item.
    |> then(&AshPhoenix.Form.validate(&1, AshPhoenix.Form.params(&1)))
  end

  defp blank?(value), do: String.trim(to_string(value || "")) == ""

  # The three most likely items not on the invoice yet, those with a price in its currency
  # first, each with the item params its button adds.
  defp quick_suggestions(suggestions, items, currency, vat_options, vat_disabled?) do
    on_invoice = MapSet.new(items, &comparable_name(&1.name))
    vat_rates = Enum.map(vat_options, &elem(&1, 1))

    suggestions
    |> Enum.reject(&MapSet.member?(on_invoice, comparable_name(&1.name)))
    |> Enum.sort_by(&(&1.currency != currency or is_nil(&1.unit_price)))
    |> Enum.take(3)
    |> Enum.map(fn suggestion ->
      unit_price = if suggestion.currency == currency, do: suggestion.unit_price

      vat_rate =
        cond do
          vat_disabled? -> List.first(vat_rates)
          suggestion.vat_rate in vat_rates -> suggestion.vat_rate
          true -> nil
        end

      item = %{
        name: suggestion.name,
        quantity: suggestion.quantity || Decimal.new(1),
        unit: if(suggestion.unit in SalesInvoiceItem.units(), do: suggestion.unit, else: "szt."),
        unit_price: unit_price,
        vat_rate: vat_rate
      }

      Map.put(
        item,
        :params,
        item
        |> Map.reject(fn {_key, value} -> is_nil(value) end)
        |> Map.new(fn {key, value} -> {to_string(key), to_string(value)} end)
      )
    end)
  end

  defp comparable_name(name), do: (name || "") |> String.trim() |> String.downcase()

  defp currency_options do
    # Use only currencies supported by NBP (plus PLN as base currency)
    nbp_currencies = NbpApiClient.supported_currencies()
    all_supported = ["PLN" | nbp_currencies]

    popular = ["PLN", "EUR", "USD"]
    rest = all_supported -- popular

    [
      {pgettext("currency list group", "Popular"), popular},
      {pgettext("currency list group", "All"), Enum.sort(rest)}
    ]
  end

  defp to_boolean(bool) when is_boolean(bool), do: bool
  defp to_boolean("true"), do: true
  defp to_boolean("false"), do: false

  # With the discount switch off, a discount typed before switching it off no longer counts.
  defp item_net_value(item_form, discount?) do
    unit_price = parse_decimal(item_form[:unit_price].value)
    quantity = parse_decimal(item_form[:quantity].value)
    discount = (discount? && parse_decimal(item_form[:discount].value)) || Decimal.new(0)

    if unit_price && quantity,
      do: Decimal.sub(Decimal.mult(unit_price, quantity), discount),
      else: Decimal.new(0)
  end

  defp item_gross_value(item_form, discount?) do
    net = item_net_value(item_form, discount?)
    vat_rate = to_string(item_form[:vat_rate].value || "0")
    vat_rate_numeric = VatRate.to_numeric(vat_rate)
    vat = Decimal.mult(net, Decimal.div(vat_rate_numeric, 100))
    Decimal.add(net, vat)
  end

  defp item_unit_vat_value(item_form) do
    unit_price = parse_decimal(item_form[:unit_price].value) || Decimal.new(0)
    vat_rate = to_string(item_form[:vat_rate].value || "0")
    vat_rate_numeric = VatRate.to_numeric(vat_rate)

    Decimal.mult(unit_price, Decimal.div(vat_rate_numeric, 100))
  end

  defp displayed_item_gross_value(item_form, gross_value_inputs) do
    case Map.fetch(gross_value_inputs, to_string(item_form.index)) do
      {:ok, value} -> value
      :error -> computed_item_gross_unit_price(item_form)
    end
  end

  defp computed_item_gross_unit_price(item_form) do
    value =
      item_form[:unit_price].value
      |> parse_decimal()
      |> case do
        nil -> Decimal.new(0)
        unit_price -> PriceInput.gross_unit_price_from_net(unit_price, item_form[:vat_rate].value)
      end

    if Decimal.eq?(value, Decimal.new(0)) do
      ""
    else
      value |> Decimal.round(2) |> Decimal.to_string(:normal)
    end
  end

  defp price_input_mode(price_input_modes, item_form) do
    row_mode =
      Map.get(
        price_input_modes,
        to_string(item_form.index),
        Map.get(price_input_modes, "all", :net)
      )

    case to_string(row_mode) do
      "gross" -> :gross
      _ -> :net
    end
  end

  defp price_error_target(_price_input_modes, true), do: "price"

  defp price_error_target(price_input_modes, false) do
    if Enum.any?(price_input_modes, fn {_index, mode} -> to_string(mode) == "gross" end) do
      "gross-price"
    else
      "price"
    end
  end

  defp field_errors(field) do
    if submitted_form?(field.form.source) and Phoenix.Component.used_input?(field) do
      field.errors
    else
      []
    end
  end

  defp invalid_field?(field), do: field_errors(field) != []

  defp submitted_form?(%AshPhoenix.Form{just_submitted?: true}), do: true
  defp submitted_form?(_source), do: false

  defp displayed_item_unit_price_text(item_form, currency) do
    unit_price = parse_decimal(item_form[:unit_price].value) || Decimal.new(0)
    format_amount(currency, unit_price)
  end

  # The gross price button shows what the user typed or the computed price, formatted like other amounts.
  defp displayed_item_gross_price_text(item_form, gross_value_inputs, currency) do
    case item_form |> displayed_item_gross_value(gross_value_inputs) |> parse_decimal() do
      nil -> ""
      gross_price -> format_amount(currency, gross_price)
    end
  end

  defp format_amount(currency, amount), do: Money.to_string!(Money.new(currency, amount), currency_symbol: "")

  defp compute_vat_options(_invoice, _is_reverse_charge, false) do
    {VatRate.select_options_short(["zw"]), true}
  end

  defp compute_vat_options(invoice, is_reverse_charge, true) do
    if is_reverse_charge do
      {VatRate.select_options_short(["oo"]), true}
    else
      buyer_id_type = invoice.buyer_id_type

      case VatRate.available_rates(invoice.buyer_country, buyer_id_type) do
        {:select, rates, _default} -> {VatRate.select_options_short(rates), false}
        {:fixed, rate} -> {VatRate.select_options_short([rate]), true}
      end
    end
  end

  defp summary_item_net(%{quantity: qty, unit_price: price} = item) when not is_nil(qty) and not is_nil(price) do
    (parse_decimal(qty) || Decimal.new(0))
    |> Decimal.mult(parse_decimal(price) || Decimal.new(0))
    |> Decimal.sub(parse_decimal(Map.get(item, :discount)) || Decimal.new(0))
  end

  defp summary_item_net(_), do: Decimal.new(0)

  defp summary_item_vat_rate(%{vat_rate: vat_rate}) do
    numeric = VatRate.to_numeric(to_string(vat_rate || "0"))
    Decimal.div(numeric, 100)
  end

  defp invoice_summary(items, currency) do
    zero = Decimal.new(0)

    {net, vat, gross} =
      Enum.reduce(items, {zero, zero, zero}, fn item, {net_acc, vat_acc, gross_acc} ->
        net = summary_item_net(item)
        vat = Decimal.mult(net, summary_item_vat_rate(item))
        gross = Decimal.add(net, vat)

        {Decimal.add(net_acc, net), Decimal.add(vat_acc, vat), Decimal.add(gross_acc, gross)}
      end)

    %{
      net_value: Money.new(currency, net),
      vat_value: Money.new(currency, vat),
      gross_value: Money.new(currency, gross)
    }
  end

  defp get_first_error_for_items(items_forms, field_name) do
    items_forms
    |> Enum.flat_map(fn item_form -> field_errors(item_form[field_name]) end)
    |> List.first()
    |> case do
      nil -> nil
      {_msg, _opts} = error -> translate_error(error)
    end
  end

  defp extract_items_as_structs(%AshPhoenix.Form{} = form, items_field) do
    form.forms
    |> access_forms(items_field)
    |> Enum.map(fn item_form ->
      %{
        name: AshPhoenix.Form.value(item_form, :name),
        quantity: AshPhoenix.Form.value(item_form, :quantity),
        unit: AshPhoenix.Form.value(item_form, :unit),
        unit_price: AshPhoenix.Form.value(item_form, :unit_price),
        discount: AshPhoenix.Form.value(item_form, :discount),
        vat_rate: AshPhoenix.Form.value(item_form, :vat_rate)
      }
    end)
  end

  defp extract_items_as_structs(_source, _field), do: []

  defp get_currency(%AshPhoenix.Form{} = form), do: AshPhoenix.Form.value(form, :currency)

  # The discount switch is a UI-only param on the invoice form; until it is touched, the column shows
  # when a line already carries a discount (e.g. an invoice imported from KSeF).
  defp line_discounts?(items_form, items) do
    case items_form[:line_discounts].value do
      nil -> Enum.any?(items, &(not is_nil(&1.discount)))
      value -> to_boolean(value)
    end
  end

  defp get_reverse_charge(%AshPhoenix.Form{} = form), do: AshPhoenix.Form.value(form, :is_reverse_charge) || false

  defp form_valid?(%AshPhoenix.Form{} = form), do: form.valid?

  attr :invoice, :any, required: true
  attr :invoice_changeset, :any, required: true
  attr :items_field, :atom, default: :sales_invoice_items
  attr :item_price_input_modes, :map, default: %{}
  attr :gross_item_price_inputs, :map, default: %{}
  attr :focused_item_price_input_index, :any, default: nil
  attr :show_vat, :boolean, default: true

  attr :item_suggestions, :list,
    default: [],
    doc:
      "items suggested in the item name fields, most likely first: a name, and the quantity, unit and net unit price it fills in"

  slot :rubric,
    doc: "rows put before the currency's, numbered from 1; the content is the row's answer, a single element" do
    attr :label, :string, required: true
    attr :id, :string, doc: "the label's id, for an answer that names itself after it"
  end

  def invoice_items(%{invoice_changeset: source, invoice: invoice, items_field: items_field} = input_assigns) do
    items = extract_items_as_structs(source, items_field)

    single_item? =
      case items do
        [_single] -> true
        _ -> false
      end

    # Ensure at least one item exists for the form
    {source, items} = ensure_minimum_item(source, items, items_field)

    show_vat = Map.get(input_assigns, :show_vat, true)
    is_reverse_charge = get_reverse_charge(source)
    {vat_options, vat_disabled?} = compute_vat_options(invoice, is_reverse_charge, show_vat)

    currency = get_currency(source) || "PLN"
    items_form = build_form(source)
    show_exemption? = show_vat and Enum.any?(items, &(&1.vat_rate == "zw"))

    # Get nested item forms for error extraction
    item_forms = get_nested_item_forms(source, items_field)
    name_error = get_first_error_for_items(item_forms, :name)
    quantity_error = get_first_error_for_items(item_forms, :quantity)
    unit_price_error = get_first_error_for_items(item_forms, :unit_price)
    discount_error = get_first_error_for_items(item_forms, :discount)

    # Sort/drop param names
    form_name = items_form.name
    sort_param = "#{form_name}[#{sort_param_name(source, items_field)}][]"
    drop_param = "#{form_name}[#{drop_param_name(source, items_field)}][]"
    add_param = sort_param

    discount? = line_discounts?(items_form, items)

    assigns = %{
      invoice: invoice,
      items_form: items_form,
      items_field: items_field,
      currency: currency,
      summary:
        invoice_summary(
          if(discount?, do: items, else: Enum.map(items, &%{&1 | discount: nil})),
          currency
        ),
      single_item?: single_item?,
      show_exemption?: show_exemption?,
      # Reverse charge and non-VAT payers show one value per item instead of VAT and gross prices.
      unit_vat?: show_vat and not to_boolean(items_form[:is_reverse_charge].value),
      rubric: input_assigns.rubric,
      number: numbering(length(input_assigns.rubric), show_exemption?),
      vat_options: vat_options,
      vat_disabled?: vat_disabled?,
      name_error: name_error,
      quantity_error: quantity_error,
      unit_price_error: unit_price_error,
      discount_error: discount_error,
      discount?: discount?,
      valid?: form_valid?(source),
      show_vat: show_vat,
      item_suggestions: input_assigns.item_suggestions,
      quick_suggestions:
        quick_suggestions(
          input_assigns.item_suggestions,
          items,
          currency,
          vat_options,
          vat_disabled?
        ),
      item_price_input_modes: input_assigns.item_price_input_modes,
      gross_item_price_inputs: input_assigns.gross_item_price_inputs,
      focused_item_price_input_index: input_assigns.focused_item_price_input_index,
      sort_param: sort_param,
      drop_param: drop_param,
      add_param: add_param
    }

    ~H"""
    <div class="@container flex flex-col">
      <div class="grid grid-cols-[2.25rem_max-content_minmax(0,1fr)] items-baseline gap-y-12">
        <%= for {row, number} <- Enum.with_index(@rubric, 1) do %>
          <.rubric_label id={row[:id]} number={number} class="col-span-2">
            {row.label}
          </.rubric_label>
          {render_slot(row)}
        <% end %>

        <.rubric_label for={@items_form[:currency].id} number={@number.currency} class="col-span-2">
          {gettext("Selected currency")}
        </.rubric_label>
        <div class="flex flex-row flex-wrap items-center gap-x-8 gap-y-3">
          <.input
            :if={@invoice.buyer_id_type == :nip}
            type="hidden"
            name={@items_form[:currency].name}
            value={@currency}
          />
          <.input
            field={@items_form[:currency]}
            type="select"
            options={currency_options()}
            disabled={@invoice.buyer_id_type == :nip}
          />
          <.switch
            :if={@show_vat and @invoice.invoice_type == :poland}
            field={@items_form[:is_cash_account]}
            color="teal"
            class="flex-row-reverse gap-2 text-sm text-grey-700"
          >
            <:label_slot>
              {gettext("Cash accounting")}
              <Lucideicons.info
                id="cash-accounting-tooltip"
                phx-hook="Tippy"
                data-tippy-content={
                  gettext(
                    "With cash accounting, VAT is due when the buyer pays the invoice, not when it is issued."
                  )
                }
                class="ml-0.5 size-4"
              />
            </:label_slot>
          </.switch>
          <.switch
            field={%{@items_form[:line_discounts] | value: @discount?}}
            color="teal"
            label={gettext("Discount")}
            class="flex-row-reverse gap-2 text-sm text-grey-700"
          />
          <.switch
            :if={@invoice.buyer_country != "PL"}
            field={@items_form[:is_reverse_charge]}
            color="teal"
            class="flex-row-reverse gap-2 text-sm text-grey-700"
          >
            <:label_slot>
              {gettext("Reverse charge")}
              <Lucideicons.info
                id="reverse-charge-tooltip"
                phx-hook="Tippy"
                data-tippy-content={
                  gettext(
                    "Reverse charge (odwrotne obciążenie) is a mechanism in which the obligation to account for VAT rests with the buyer of the service; it applies, among other things, to imports of services from the European Union."
                  )
                }
                class="ml-0.5 size-4"
              />
            </:label_slot>
          </.switch>
        </div>

        <%= if @show_exemption? do %>
          <.rubric_label number={@number.exemption} class="col-span-2">
            {gettext("VAT exemption")}
          </.rubric_label>
          <div class="flex flex-row flex-wrap gap-x-3 gap-y-4 justify-self-start">
            <div class="flex flex-col gap-2">
              <label for={@items_form[:vat_exemption_type].id} class="text-sm/snug text-grey-600">
                {gettext("Exemption basis")}
              </label>
              <.input
                type="select"
                field={@items_form[:vat_exemption_type]}
                options={VatExemption.options()}
                input_class="w-full"
              />
            </div>

            <%= if to_string(@items_form[:vat_exemption_type].value) == "other" do %>
              <div class="flex flex-col gap-2">
                <label
                  for={@items_form[:vat_exemption_basis].id}
                  class="text-sm/snug text-grey-600"
                >
                  {gettext("Legal basis for the VAT exemption")}
                </label>
                <.input type="text" field={@items_form[:vat_exemption_basis]} input_class="w-full" />
              </div>
            <% else %>
              <input type="hidden" name={@items_form[:vat_exemption_basis].name} value="" />
            <% end %>
          </div>
        <% end %>

        <div class="col-span-full grid grid-cols-subgrid items-baseline gap-y-3">
          <.rubric_label number={@number.items} class="col-span-full">
            {gettext("Invoice items")}
          </.rubric_label>

          <%!-- `-me-8` hangs the remove buttons outside the content's right edge; the drag
          handles stand in the numerals' column, so the names share the labels' left edge. --%>
          <div class={[
            "col-span-full -me-8 grid gap-x-2",
            cond do
              @unit_vat? and @discount? ->
                "grid-cols-[min-content_1fr_repeat(8,min-content)] @max-[60rem]:grid-cols-[min-content_1fr_repeat(7,min-content)]"

              @unit_vat? ->
                "grid-cols-[min-content_1fr_repeat(7,min-content)] @max-[60rem]:grid-cols-[min-content_1fr_repeat(6,min-content)]"

              @show_vat and @discount? ->
                "grid-cols-[min-content_1fr_repeat(8,min-content)]"

              @show_vat ->
                "grid-cols-[min-content_1fr_repeat(7,min-content)]"

              @discount? ->
                "grid-cols-[min-content_1fr_repeat(7,min-content)]"

              true ->
                "grid-cols-[min-content_1fr_repeat(6,min-content)]"
            end
          ]}>
            <div class="col-start-2 -col-end-2 mb-1 grid grid-cols-subgrid py-1 text-sm/snug text-grey-600">
              <.error :if={@name_error} is_tooltip={true} target="name">
                {@name_error}
              </.error>
              <.error :if={@quantity_error} is_tooltip={true} target="quantity">
                {@quantity_error}
              </.error>
              <.error
                :if={@unit_price_error}
                is_tooltip={true}
                target={
                  price_error_target(
                    @item_price_input_modes,
                    to_boolean(@items_form[:is_reverse_charge].value)
                  )
                }
              >
                {@unit_price_error}
              </.error>
              <.error :if={@discount_error} is_tooltip={true} target="discount">
                {@discount_error}
              </.error>
              <p id="name">
                {gettext("Product/service")}
              </p>
              <p id="quantity">
                {gettext("Quantity")}
              </p>
              <p :if={@show_vat}>VAT</p>
              <p>{pgettext("sales invoice items", "Unit")}</p>
              <.button
                id="price"
                type="button"
                variant="unstyled"
                class="cursor-pointer text-left"
                phx-click="set_price_input_mode"
                phx-value-index="all"
                phx-value-mode="net"
              >
                {gettext("Net price")}
              </.button>
              <p :if={@discount?} id="discount" class="text-center">{gettext("Discount")}</p>

              <%= if @unit_vat? do %>
                <%!-- The column gives way where the names would otherwise be too narrow. --%>
                <p class="text-end @max-[60rem]:hidden">{gettext("VAT per unit")}</p>
                <.button
                  id="gross-price"
                  type="button"
                  variant="unstyled"
                  class="cursor-pointer text-right"
                  phx-click="set_price_input_mode"
                  phx-value-index="all"
                  phx-value-mode="gross"
                >
                  {gettext("Gross price")}
                </.button>
              <% else %>
                <p class="col-span-2 text-end">{pgettext("sales invoice items", "Value")}</p>
              <% end %>
            </div>

            <div
              class="col-span-full grid grid-cols-subgrid gap-y-2"
              id="items_list"
              phx-hook=".Sortable"
              data-item-suggestions={Jason.encode!(@item_suggestions)}
            >
              <.inputs_for :let={item} field={@items_form[@items_field]}>
                <% gross_value_input_name =
                  String.replace(item[:unit_price].name, ~r/\[unit_price\]$/, "[gross_value]") %>
                <% gross_value_input_id =
                  String.replace(item[:unit_price].id, ~r/_unit_price$/, "_gross_value") %>
                <% focus_price_input? =
                  to_string(@focused_item_price_input_index) == to_string(item.index) %>
                <div class="col-span-full grid grid-cols-subgrid items-center">
                  <input type="hidden" name={@sort_param} value={item.index} />
                  <input type="hidden" name={item[:index].name} value={item.index} />
                  <input
                    :if={item[:gtu].value}
                    type="hidden"
                    name={item[:gtu].name}
                    value={item[:gtu].value}
                  />
                  <Lucideicons.grip_vertical class="mr-1 text-grey-700" drag-handle />
                  <.item_name
                    field={item[:name]}
                    index={item.index}
                    suggest?={@item_suggestions != []}
                  />
                  <.input
                    field={item[:quantity]}
                    placeholder="0"
                    aria-label={gettext("Item %{number}: quantity", number: item.index + 1)}
                    phx-debounce
                    type="number"
                    step=".000001"
                    min="0"
                    class="w-16"
                    input_class={[
                      "text-center",
                      if(invalid_field?(item[:quantity]), do: "border-brick-700")
                    ]}
                    show_error={false}
                  />
                  <.hidden_input show={@show_vat} field={item[:vat_rate]} value="zw">
                    <:input>
                      <.input
                        field={item[:vat_rate]}
                        type="select"
                        options={@vat_options}
                        aria-label={gettext("Item %{number}: VAT rate", number: item.index + 1)}
                        phx-debounce
                        container_class="w-24"
                        readonly={@vat_disabled?}
                      />
                    </:input>
                  </.hidden_input>
                  <.input
                    field={item[:unit]}
                    type="select"
                    placeholder="0,00"
                    aria-label={gettext("Item %{number}: unit", number: item.index + 1)}
                    phx-debounce
                    container_class="w-24"
                    options={SalesInvoiceItem.units()}
                  />
                  <% price_input_mode = price_input_mode(@item_price_input_modes, item) %>
                  <.hidden_input show={price_input_mode == :net} field={item[:unit_price]}>
                    <:input>
                      <div class="flex w-30 flex-row items-center gap-1">
                        <.input
                          field={item[:unit_price]}
                          type="number"
                          value={item[:unit_price].value}
                          aria-label={gettext("Item %{number}: net price", number: item.index + 1)}
                          phx-mounted={focus_price_input? && JS.focus()}
                          phx-debounce
                          step="any"
                          min="0"
                          placeholder="0,00"
                          class="w-30"
                          input_class={[
                            "text-center",
                            if(invalid_field?(item[:unit_price]), do: "border-brick-700")
                          ]}
                          show_error={false}
                        />
                        <p class="text-sm text-grey-500">{@items_form[:currency].value}</p>
                      </div>
                    </:input>
                    <:fallback>
                      <div class="flex w-30 flex-row items-center justify-center gap-1">
                        <.button
                          type="button"
                          variant="unstyled"
                          class="w-24 rounded p-1 text-center transition hover:bg-grey-200"
                          phx-click="set_price_input_mode"
                          phx-value-index={item.index}
                          phx-value-mode="net"
                        >
                          {displayed_item_unit_price_text(item, @currency)}
                        </.button>
                        <p class="text-sm text-grey-500">{@items_form[:currency].value}</p>
                      </div>
                    </:fallback>
                  </.hidden_input>

                  <input :if={not @discount?} type="hidden" name={item[:discount].name} value="" />
                  <.input
                    :if={@discount?}
                    field={item[:discount]}
                    type="number"
                    aria-labelledby="discount"
                    phx-debounce
                    step="any"
                    placeholder="0,00"
                    class="w-24"
                    input_class={[
                      "text-center",
                      if(invalid_field?(item[:discount]), do: "border-brick-700")
                    ]}
                    show_error={false}
                  />

                  <%= if @unit_vat? do %>
                    <% vat_value =
                      Money.new(@currency, item_unit_vat_value(item)) %>
                    <% gross_unit_price =
                      displayed_item_gross_price_text(item, @gross_item_price_inputs, @currency) %>

                    <p class={[
                      "w-28 truncate text-end @max-[60rem]:hidden",
                      if(Money.zero?(vat_value), do: "text-grey-500")
                    ]}>
                      {Money.to_string!(vat_value, currency_symbol: "")}
                    </p>
                    <.hidden_input show={price_input_mode == :gross}>
                      <:input>
                        <div class="flex w-28 flex-row items-center justify-end">
                          <.input
                            type="number"
                            id={gross_value_input_id}
                            name={gross_value_input_name}
                            value={displayed_item_gross_value(item, @gross_item_price_inputs)}
                            aria-label={
                              gettext("Item %{number}: gross price", number: item.index + 1)
                            }
                            phx-mounted={focus_price_input? && JS.focus()}
                            phx-debounce
                            step=".01"
                            min="0"
                            placeholder="0,00"
                            class="w-28"
                            input_class={[
                              "text-right",
                              if(invalid_field?(item[:unit_price]), do: "border-brick-700")
                            ]}
                            show_error={false}
                          />
                        </div>
                      </:input>
                      <:fallback>
                        <.button
                          type="button"
                          variant="unstyled"
                          class={[
                            "w-28 truncate rounded p-1 text-right transition hover:bg-grey-200",
                            gross_unit_price == "" && "text-grey-500"
                          ]}
                          phx-click="set_price_input_mode"
                          phx-value-index={item.index}
                          phx-value-mode="gross"
                        >
                          {gross_unit_price}
                        </.button>
                      </:fallback>
                    </.hidden_input>
                  <% else %>
                    <% gross_value =
                      Money.new(@currency, item_gross_value(item, @discount?)) %>

                    <%!-- Narrows with the "VAT / jedn." column of the VAT layout. --%>
                    <p class={[
                      "col-span-2 w-58 truncate text-end @max-[60rem]:w-28",
                      if(Money.zero?(gross_value), do: "text-grey-500")
                    ]}>
                      {Money.to_string!(gross_value, currency_symbol: "")}
                    </p>
                  <% end %>

                  <.button
                    type="button"
                    name={@drop_param}
                    value={item.index}
                    phx-click={JS.dispatch("change")}
                    disabled={@single_item?}
                    variant="unstyled"
                    aria-label={gettext("Remove item")}
                    class="ml-1 cursor-pointer text-grey-300 transition-colors duration-200 ease-out hover:text-grey-700 disabled:cursor-default disabled:text-transparent"
                  >
                    <Lucideicons.x class="size-4" />
                  </.button>
                </div>
              </.inputs_for>

              <input type="hidden" name={@drop_param} />
            </div>

            <%!-- todo: add loading state --%>
            <.button
              type="button"
              phx-click="add_item"
              class="col-span-1 col-start-2 mt-3"
              size="small"
              variant="tertiary"
            >
              <Lucideicons.plus /> {gettext("Add item")}
            </.button>

            <div
              :if={@quick_suggestions != []}
              class="col-start-2 -col-end-2 mt-8 flex flex-col gap-3"
            >
              <p class="text-sm/snug text-grey-600">{gettext("Add in one click")}</p>
              <%!-- One flat tile per item, no surface inside: the name, then what the click fills in. --%>
              <div class="grid grid-cols-3 gap-3 @max-3xl:grid-cols-1">
                <.button
                  :for={suggestion <- @quick_suggestions}
                  type="button"
                  variant="unstyled"
                  phx-click="add_suggested_item"
                  phx-value-name={suggestion.params["name"]}
                  phx-value-quantity={suggestion.params["quantity"]}
                  phx-value-unit={suggestion.params["unit"]}
                  phx-value-unit_price={suggestion.params["unit_price"]}
                  phx-value-vat_rate={suggestion.params["vat_rate"]}
                  class="flex min-w-0 cursor-pointer items-start gap-3 rounded-lg border border-teal-200 bg-teal-50 px-4 py-3 text-start transition-colors duration-150 ease-out hover:border-teal-400 hover:bg-teal-100 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-(--focus-ring) active:bg-teal-200"
                >
                  <Lucideicons.plus class="mt-0.5 size-4 shrink-0 text-teal-700" />
                  <span class="flex min-w-0 flex-1 flex-col gap-1.5 self-stretch">
                    <span class="line-clamp-2 text-sm/snug font-medium wrap-anywhere text-grey-900">
                      {suggestion.name}
                    </span>
                    <.quick_suggestion_details
                      suggestion={suggestion}
                      currency={@currency}
                      show_vat={@show_vat}
                    />
                  </span>
                </.button>
              </div>
            </div>
          </div>
        </div>
      </div>

      <div class={[
        "mt-10 ml-auto grid w-72 min-w-min grid-cols-[1fr_repeat(2,min-content)] items-center gap-2 border-t border-grey-200 pt-4 leading-snug whitespace-nowrap",
        if(Money.zero?(@summary.net_value), do: "text-grey-500", else: "text-black")
      ]}>
        <%= if @unit_vat? do %>
          <p class="text-left text-sm/snug text-grey-600">{gettext("Net total")}</p>
          <p class="text-right">
            {Money.to_string!(@summary.net_value, currency_symbol: "")}
          </p>
          <p class="text-right">{@items_form[:currency].value}</p>

          <p class="text-left text-sm/snug text-grey-600">{gettext("VAT total")}</p>
          <p class="text-right">
            {Money.to_string!(@summary.vat_value, currency_symbol: "")}
          </p>
          <p class="text-right">{@items_form[:currency].value}</p>

          <p class="text-left text-sm/snug text-grey-600">{gettext("Gross total")}</p>
          <p class="text-right text-2xl/tight font-medium">
            {Money.to_string!(@summary.gross_value, currency_symbol: "")}
          </p>
          <p class="text-right">{@items_form[:currency].value}</p>
        <% else %>
          <p class="text-left text-sm/snug text-grey-600">
            {pgettext("sales invoice items", "Total")}
          </p>
          <p class="text-right text-2xl/tight font-medium">
            {Money.to_string!(@summary.gross_value, currency_symbol: "")}
          </p>
          <p class="text-right">{@items_form[:currency].value}</p>
        <% end %>
      </div>
    </div>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".ItemSuggestions">
      // Choosing a suggestion fills in the item's name and the quantity, unit, VAT rate and net
      // price the suggestion has; the price only on an invoice in its currency.

      // Matches regardless of case and Polish diacritics, so "uslu" finds "Usługi".
      const normalize = (text) =>
        text.normalize("NFD").replace(/\p{M}/gu, "").replace(/ł/gi, "l").toLowerCase();

      // Shows at most this many names at a time; typing narrows them down.
      const LIMIT = 5;

      export default {
        mounted() {
          this.input = this.el.querySelector("input");
          this.list = this.el.querySelector("[role=listbox]");
          if (!this.list) return;
          this.suggestions = JSON.parse(this.el.closest("[data-item-suggestions]").dataset.itemSuggestions);
          this.matches = [];
          this.active = -1;

          this.input.addEventListener("focus", () => this.open());
          this.input.addEventListener("input", () => this.open());
          this.input.addEventListener("blur", () => this.close());
          this.input.addEventListener("keydown", (event) => this.onKeydown(event));
          // Keeps focus in the input so a click does not close the list before it chooses.
          this.list.addEventListener("mousedown", (event) => event.preventDefault());
          this.list.addEventListener("click", (event) => {
            const option = event.target.closest("[role=option]");
            if (option) this.choose(this.matches[Number(option.dataset.index)]);
          });
        },
        open() {
          const query = normalize(this.input.value.trim());

          this.matches = this.suggestions
            .filter(({name}) => {
              const label = normalize(name);
              return (
                label !== query &&
                (label.startsWith(query) || label.split(/[\s-]+/).some((word) => word.startsWith(query)))
              );
            })
            .slice(0, LIMIT);

          this.active = -1;
          this.render();
        },
        close() {
          this.matches = [];
          this.active = -1;
          this.render();
        },
        render() {
          this.list.replaceChildren(
            ...this.matches.map(({name}, index) => {
              const option = document.createElement("div");
              option.id = `${this.list.id}-${index}`;
              option.setAttribute("role", "option");
              option.dataset.index = index;
              option.textContent = name;
              option.className =
                "cursor-pointer rounded-md px-2 py-1.5 text-sm text-grey-700 hover:bg-grey-100 data-active:bg-grey-100";
              option.toggleAttribute("data-active", index === this.active);
              option.setAttribute("aria-selected", String(index === this.active));
              return option;
            }),
          );

          const expanded = this.matches.length > 0;
          this.list.hidden = !expanded;
          this.input.setAttribute("aria-expanded", String(expanded));

          if (this.active >= 0) {
            this.input.setAttribute("aria-activedescendant", `${this.list.id}-${this.active}`);
          } else {
            this.input.removeAttribute("aria-activedescendant");
          }
        },
        choose(suggestion) {
          const row = this.el.parentElement;
          const field = (name) => row.querySelector(`[name$="[${name}]"]`);
          const currency = this.el.closest("form").querySelector('[name$="[currency]"]');
          let changed = this.input;

          this.input.value = suggestion.name;
          if (suggestion.quantity) field("quantity").value = suggestion.quantity;

          // The unit list holds only the units the form offers.
          const unit = field("unit");
          if ([...unit.options].some((option) => option.value === suggestion.unit)) unit.value = suggestion.unit;

          // A rate the row cannot take (a fixed or narrower list) stays as it is.
          const vat = field("vat_rate");
          if (vat?.tagName === "SELECT" && !vat.hasAttribute("readonly") &&
              [...vat.options].some((option) => option.value === suggestion.vat_rate)) {
            vat.value = suggestion.vat_rate;
          }

          if (suggestion.unit_price && suggestion.currency === currency?.value) {
            field("unit_price").value = suggestion.unit_price;
            // A typed gross price would override the net one, so the row recomputes it.
            const gross = field("gross_value");
            if (gross) gross.value = "";
            changed = field("unit_price");
          }

          // The event from the price tells the server to drop a typed gross price.
          changed.dispatchEvent(new Event("input", {bubbles: true}));
          this.close();
        },
        onKeydown(event) {
          if (event.key === "ArrowDown" || event.key === "ArrowUp") {
            event.preventDefault();
            if (this.matches.length === 0) this.open();
            const step = event.key === "ArrowDown" ? 1 : -1;
            const count = this.matches.length;
            // Cycles through the options and back to the typed text (-1).
            if (count > 0) this.active = ((this.active + 1 + step + count + 1) % (count + 1)) - 1;
            this.render();
          } else if (event.key === "Enter" && this.active >= 0) {
            event.preventDefault();
            this.choose(this.matches[this.active]);
          } else if (event.key === "Escape" && this.matches.length > 0) {
            // Closes only the list, not a modal around it.
            event.preventDefault();
            event.stopPropagation();
            this.close();
          }
        },
      };
    </script>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".Sortable">
      import Sortable from "sortablejs";

      export default {
      mounted() {
        new Sortable(this.el, {
          animation: 150,
          handle: "[drag-handle]",
          onEnd: (evt) => {
            // https://github.com/chrismccord/todo_trek/blob/328da395b820cd3072f806a36374cf882b854967/assets/js/app.js#L69C9-L69C106
            this.el.closest("form").querySelector("input").dispatchEvent(new Event("input", {bubbles: true}))
          }
        })
      }
      }
    </script>
    """
  end

  attr :suggestion, :map, required: true
  attr :currency, :string, required: true
  attr :show_vat, :boolean, required: true

  # "23 szt. · VAT 8%" with the unit price at the end, leaving out what the click does not fill in.
  defp quick_suggestion_details(assigns) do
    ~H"""
    <%!-- Pinned to the tile's bottom, so the details of neighbouring tiles share a line. --%>
    <span class="mt-auto flex items-baseline justify-between gap-3 text-sm/snug tabular-nums">
      <span class="text-grey-600">
        {Firmowid.Cldr.Number.to_string!(@suggestion.quantity)} {@suggestion.unit}
        <%= if @show_vat and @suggestion.vat_rate do %>
          · {gettext("VAT %{rate}", rate: VatRate.short_label(@suggestion.vat_rate))}
        <% end %>
      </span>
      <span :if={@suggestion.unit_price} class="shrink-0 font-medium text-grey-900">
        × {Money.to_string!(Money.new(@currency, @suggestion.unit_price))}
      </span>
    </span>
    """
  end

  attr :field, Phoenix.HTML.FormField, required: true
  attr :index, :integer, required: true
  attr :suggest?, :boolean, required: true

  # With suggestions, a combobox whose list the `.ItemSuggestions` hook fills as the user types;
  # the list and the attributes saying whether it is open are the hook's, so LiveView leaves them alone.
  # The hook stays without suggestions, since a colocated hook's name must be static.
  defp item_name(assigns) do
    ~H"""
    <div
      id={"#{@field.id}-suggest"}
      phx-hook=".ItemSuggestions"
      class="relative w-full"
    >
      <.input
        field={@field}
        placeholder={gettext("Enter a name")}
        aria-label={gettext("Item %{number}: product or service", number: @index + 1)}
        phx-debounce
        class="w-full"
        input_class={[if(invalid_field?(@field), do: "border-brick-700")]}
        show_error={false}
        {if @suggest?, do: combobox_attrs(@field), else: []}
      />
      <div
        :if={@suggest?}
        id={"#{@field.id}-suggestions"}
        role="listbox"
        aria-label={gettext("Suggested names")}
        hidden
        phx-update="ignore"
        phx-mounted={JS.ignore_attributes("hidden")}
        class="absolute inset-x-0 top-full z-20 mt-1 rounded-lg border border-grey-200 bg-white p-1 shadow-lg"
      >
      </div>
    </div>
    """
  end

  defp combobox_attrs(field) do
    [
      role: "combobox",
      autocomplete: "off",
      "aria-autocomplete": "list",
      "aria-expanded": "false",
      "aria-controls": "#{field.id}-suggestions",
      "phx-mounted": JS.ignore_attributes(["aria-expanded", "aria-activedescendant"])
    ]
  end

  # The rows follow the `rubric` rows; the exemption row exists only while an item uses
  # the "zw" rate and pushes the items one number down.
  defp numbering(rubric_rows, show_exemption?) do
    currency = rubric_rows + 1

    if show_exemption?,
      do: %{currency: currency, exemption: currency + 1, items: currency + 2},
      else: %{currency: currency, exemption: nil, items: currency + 1}
  end

  attr :number, :integer, required: true
  attr :class, :string, required: true
  attr :for, :string, default: nil
  attr :id, :string, default: nil

  slot :inner_block, required: true

  # The numeral has a column of its own, as wide as a drag handle's, so the label texts
  # share a left edge with the item names and the handles stand under the numerals.
  defp rubric_label(assigns) do
    ~H"""
    <%= if @for do %>
      <label for={@for} id={@id} class={["grid grid-cols-subgrid", @class]}>
        <span class="text-sm/snug font-medium text-grey-900 tabular-nums">{@number}.</span>
        <span class="col-start-2 -col-end-1 pe-12 text-sm/snug text-grey-600">
          {render_slot(@inner_block)}
        </span>
      </label>
    <% else %>
      <p id={@id} class={["grid grid-cols-subgrid", @class]}>
        <span class="text-sm/snug font-medium text-grey-900 tabular-nums">{@number}.</span>
        <span class="col-start-2 -col-end-1 pe-12 text-sm/snug text-grey-600">
          {render_slot(@inner_block)}
        </span>
      </p>
    <% end %>
    """
  end

  defp build_form(%AshPhoenix.Form{} = form), do: FormData.to_form(form, [])

  defp get_nested_item_forms(%AshPhoenix.Form{} = form, items_field) do
    form.forms
    |> access_forms(items_field)
    |> Enum.map(&FormData.to_form(&1, []))
  end

  # Ensure at least one item for the form
  defp ensure_minimum_item(source, [], _items_field) do
    # For AshPhoenix.Form, empty items should be handled at the form level
    # The form already has the item forms from the resource data
    {source, []}
  end

  defp ensure_minimum_item(source, items, _items_field), do: {source, items}

  defp sort_param_name(%AshPhoenix.Form{}, items_field), do: "_sort_#{items_field}"

  defp drop_param_name(%AshPhoenix.Form{}, items_field), do: "_drop_#{items_field}"
end
