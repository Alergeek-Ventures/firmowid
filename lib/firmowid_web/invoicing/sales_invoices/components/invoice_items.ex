defmodule FirmowidWeb.Invoicing.SalesInvoices.Components.InvoiceItems do
  @moduledoc """
  Component for editing invoice line items.

  Works with AshPhoenix.Form (WizardDraft, SalesInvoice).
  The parent view passes a pre-built Phoenix form and the items field name.
  """
  use FirmowidWeb, :html

  alias Firmowid.Ash.Currencies.NbpApiClient
  alias Firmowid.Ash.Ksef.VatRate
  alias FirmowidWeb.Invoicing.FormHelpers
  alias Phoenix.HTML.FormData

  import FirmowidWeb.DesignSystem.Components.CoreComponents, except: [button: 1]
  import FirmowidWeb.DesignSystem.Components.Button

  defp currency_options do
    # Use only currencies supported by NBP (plus PLN as base currency)
    nbp_currencies = NbpApiClient.supported_currencies()
    all_supported = ["PLN" | nbp_currencies]

    popular = ["PLN", "EUR", "USD"]
    rest = all_supported -- popular

    [
      {"Popularne", popular},
      {"Wszystkie", Enum.sort(rest)}
    ]
  end

  defp to_boolean(bool) when is_boolean(bool), do: bool
  defp to_boolean("true"), do: true
  defp to_boolean("false"), do: false

  defp item_net_value(item_form) do
    unit_price = parse_decimal(item_form[:unit_price].value)
    quantity = parse_decimal(item_form[:quantity].value)

    if unit_price && quantity, do: Decimal.mult(unit_price, quantity), else: Decimal.new(0)
  end

  defp item_gross_value(item_form) do
    net = item_net_value(item_form)
    vat_rate = to_string(item_form[:vat_rate].value || "0")
    vat_rate_numeric = VatRate.to_numeric(vat_rate)
    vat = Decimal.mult(net, Decimal.div(vat_rate_numeric, 100))
    Decimal.add(net, vat)
  end

  defp parse_decimal(value), do: FormHelpers.parse_decimal(value)

  defp compute_vat_options(invoice, is_reverse_charge) do
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

  defp summary_item_net(%{quantity: qty, unit_price: price}) when not is_nil(qty) and not is_nil(price) do
    Decimal.mult(parse_decimal(qty) || Decimal.new(0), parse_decimal(price) || Decimal.new(0))
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
    |> Enum.flat_map(fn item_form -> item_form.errors end)
    |> Keyword.get_values(field_name)
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
        vat_rate: AshPhoenix.Form.value(item_form, :vat_rate)
      }
    end)
  end

  defp extract_items_as_structs(_source, _field), do: []

  defp get_currency(%AshPhoenix.Form{} = form), do: AshPhoenix.Form.value(form, :currency)

  defp get_reverse_charge(%AshPhoenix.Form{} = form), do: AshPhoenix.Form.value(form, :is_reverse_charge) || false

  defp form_valid?(%AshPhoenix.Form{} = form), do: form.valid?

  attr :invoice, :any, required: true
  attr :invoice_changeset, :any, required: true
  attr :items_field, :atom, default: :sales_invoice_items

  def invoice_items(%{invoice_changeset: source, invoice: invoice, items_field: items_field}) do
    items = extract_items_as_structs(source, items_field)

    single_item? =
      case items do
        [_single] -> true
        _ -> false
      end

    # Ensure at least one item exists for the form
    {source, items} = ensure_minimum_item(source, items, items_field)

    is_reverse_charge = get_reverse_charge(source)
    {vat_options, vat_disabled?} = compute_vat_options(invoice, is_reverse_charge)

    currency = get_currency(source) || "PLN"
    items_form = build_form(source)

    # Get nested item forms for error extraction
    item_forms = get_nested_item_forms(source, items_field)
    name_error = get_first_error_for_items(item_forms, :name)
    quantity_error = get_first_error_for_items(item_forms, :quantity)
    unit_price_error = get_first_error_for_items(item_forms, :unit_price)

    # Sort/drop param names
    form_name = items_form.name
    sort_param = "#{form_name}[#{sort_param_name(source, items_field)}][]"
    drop_param = "#{form_name}[#{drop_param_name(source, items_field)}][]"
    add_param = sort_param

    assigns = %{
      invoice: invoice,
      items_form: items_form,
      items_field: items_field,
      summary: invoice_summary(items, currency),
      single_item?: single_item?,
      vat_options: vat_options,
      vat_disabled?: vat_disabled?,
      name_error: name_error,
      quantity_error: quantity_error,
      unit_price_error: unit_price_error,
      valid?: form_valid?(source),
      sort_param: sort_param,
      drop_param: drop_param,
      add_param: add_param
    }

    ~H"""
    <div class="col-start-2 col-end-9 mb-8 space-y-8">
      <div class="mb-2 flex flex-row items-center gap-5">
        <label class="text-grey-700 mr-auto flex flex-row items-center gap-5">
          <span><strong>1.</strong> Wybrana waluta</span>
          <.input
            field={@items_form[:currency]}
            type="select"
            options={currency_options()}
            disabled={@invoice.buyer_id_type == :nip}
            new={true}
          />
        </label>

        <div class="flex flex-row">
          <.switch
            :if={@invoice.buyer_country != "PL"}
            field={@items_form[:is_reverse_charge]}
            color="turquoise"
            class="text-grey-700 flex-row-reverse gap-2 text-sm"
          >
            <:label_slot>
              Reverse charge
              <Lucideicons.info
                id="reverse-charge-tooltip"
                phx-hook="Tippy"
                data-tippy-content="Reverse charge (odwrotne obciążenie) to mechanizm, w którym obowiązek rozliczenia podatku VAT spoczywa na nabywcy usługi; dotyczy m.in. importu usług z Unii Europejskiej."
                class="ml-0.5 size-4"
              />
            </:label_slot>
          </.switch>

          <div class="flex flex-row items-center gap-3">
            <.switch
              :if={false}
              field={@items_form[:is_reverse_charge]}
              label="Rabat"
              color="turquoise"
              class="text-grey-700 flex-row-reverse gap-2 text-sm"
            />
            <.switch
              :if={false}
              field={@items_form[:is_reverse_charge]}
              label="PKWiU"
              color="turquoise"
              class="text-grey-700 flex-row-reverse gap-2 text-sm"
            />
          </div>
        </div>
      </div>
      <div class="flex flex-row items-end gap-4">
        <p class="text-grey-700 mr-auto"><strong>2.</strong> Pozycje na fakturze</p>

        <.button :if={false} type="button" size="small" variant="secondary">
          <Lucideicons.copy /> Skopiuj poprzednie pozycje
        </.button>
        <.button :if={false} type="button" size="small" variant="secondary">
          <Lucideicons.clock /> Zaciągnij godziny
        </.button>
      </div>
    </div>
    <div class="text-grey-700 col-start-2 col-end-9 mb-1 grid grid-cols-subgrid py-1 pl-2 text-sm/snug">
      <.error :if={@name_error} is_tooltip={true} target="name">
        {@name_error}
      </.error>
      <.error :if={@quantity_error} is_tooltip={true} target="quantity">
        {@quantity_error}
      </.error>
      <.error :if={@unit_price_error} is_tooltip={true} target="price">
        {@unit_price_error}
      </.error>
      <p id="name">
        Towar/usługa
      </p>
      <p id="quantity">
        Ilość
      </p>
      <p>VAT</p>
      <p>Jednostka</p>
      <p id="price">
        Cena netto
      </p>

      <%= if to_boolean(@items_form[:is_reverse_charge].value) do %>
        <p class="col-span-2 text-end">Wartość</p>
      <% else %>
        <p class="text-end">Wartość netto</p>
        <p class="text-end">Wartość brutto</p>
      <% end %>
    </div>

    <div class="col-span-full grid grid-cols-subgrid gap-y-2" id="items_list" phx-hook=".Sortable">
      <.inputs_for :let={item} field={@items_form[@items_field]}>
        <div class="col-span-full grid grid-cols-subgrid items-center">
          <input type="hidden" name={@sort_param} value={item.index} />
          <input type="hidden" name={item[:index].name} value={item.index} />
          <Lucideicons.grip_vertical class="text-grey-700 mr-1" drag-handle />
          <.input
            field={item[:name]}
            placeholder="Wprowadź nazwę"
            phx-debounce
            class="w-full"
            input_class={[item[:name].errors != [] && "border-redText"]}
            new={true}
            is_tooltip={true}
          />
          <.input
            field={item[:quantity]}
            placeholder="0"
            phx-debounce
            type="number"
            step=".000001"
            min="0"
            class="w-16"
            input_class={["text-center", item[:quantity].errors != [] && "border-redText"]}
            new={true}
            is_tooltip={true}
          />
          <.input
            field={item[:vat_rate]}
            type="select"
            options={@vat_options}
            phx-debounce
            container_class="w-24"
            new={true}
            readonly={@vat_disabled?}
          />
          <.input
            field={item[:unit]}
            type="select"
            placeholder="0,00"
            phx-debounce
            container_class="w-24"
            options={["szt.", "godz."]}
            new={true}
          />
          <div class="flex flex-row items-center gap-1">
            <.input
              field={item[:unit_price]}
              type="number"
              phx-debounce
              step=".01"
              min="0"
              placeholder="0,00"
              class="w-30"
              input_class={["text-center", item[:unit_price].errors != [] && "border-redText"]}
              new={true}
              is_tooltip={true}
            />
            <p class="text-grey-500 text-sm">{@items_form[:currency].value}</p>
          </div>

          <%= if to_boolean(@items_form[:is_reverse_charge].value) do %>
            <% gross_value =
              Money.new(@items_form[:currency].value, item_gross_value(item)) %>

            <p class={[
              "col-span-2 w-58 truncate text-end",
              if(Money.zero?(gross_value), do: "text-grey-500")
            ]}>
              {Money.to_string!(gross_value, currency_symbol: "")}
            </p>
          <% else %>
            <% net_value =
              Money.new(@items_form[:currency].value, item_net_value(item)) %>
            <% gross_value =
              Money.new(@items_form[:currency].value, item_gross_value(item)) %>

            <p class={[
              "w-28 truncate text-end",
              if(Money.zero?(net_value), do: "text-grey-500")
            ]}>
              {Money.to_string!(net_value, currency_symbol: "")}
            </p>
            <p class={[
              "w-28 truncate text-end",
              if(Money.zero?(gross_value), do: "text-grey-500")
            ]}>
              {Money.to_string!(gross_value, currency_symbol: "")}
            </p>
          <% end %>

          <button
            type="button"
            name={@drop_param}
            value={item.index}
            phx-click={JS.dispatch("change")}
            disabled={@single_item?}
            class="hover:text-grey-700 text-grey-300 ml-1 cursor-pointer transition-colors duration-200 ease-out disabled:cursor-default disabled:text-transparent"
          >
            <Lucideicons.x class="size-4" />
          </button>
        </div>
      </.inputs_for>

      <input type="hidden" name={@drop_param} />
    </div>

    <%!-- todo: add loading state --%>
    <.button
      type="button"
      phx-click="add_item"
      phx-value-field={@items_field}
      class="col-span-1 col-start-2 mt-3"
      size="small"
      variant="secondary"
    >
      <Lucideicons.plus /> Dodaj pozycję
    </.button>

    <div class={[
      "col-start-1 col-end-9 mt-3 ml-auto grid w-72 min-w-min grid-cols-[1fr_repeat(2,min-content)] items-center gap-2 leading-snug whitespace-nowrap",
      if(Money.zero?(@summary.net_value), do: "text-grey-500", else: "text-black")
    ]}>
      <%= if to_boolean(@items_form[:is_reverse_charge].value) do %>
        <p class="text-grey-500 text-left text-sm">Suma</p>
        <p class="text-right text-[27px]/tight font-medium">
          {Money.to_string!(@summary.gross_value, currency_symbol: "")}
        </p>
        <p class="text-right">{@items_form[:currency].value}</p>
      <% else %>
        <p class="text-grey-500 text-left text-sm">Suma netto</p>
        <p class="text-right">
          {Money.to_string!(@summary.net_value, currency_symbol: "")}
        </p>
        <p class="text-right">{@items_form[:currency].value}</p>

        <p class="text-grey-500 text-left text-sm">Suma VAT</p>
        <p class="text-right">
          {Money.to_string!(@summary.vat_value, currency_symbol: "")}
        </p>
        <p class="text-right">{@items_form[:currency].value}</p>

        <p class="text-grey-500 text-left text-sm">Suma brutto</p>
        <p class="text-right text-[27px]/tight font-medium">
          {Money.to_string!(@summary.gross_value, currency_symbol: "")}
        </p>
        <p class="text-right">{@items_form[:currency].value}</p>
      <% end %>
    </div>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".Sortable">
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

  defp access_forms(forms, key), do: FormHelpers.access_forms(forms, key)

  defp sort_param_name(%AshPhoenix.Form{}, items_field), do: "_sort_#{items_field}"

  defp drop_param_name(%AshPhoenix.Form{}, items_field), do: "_drop_#{items_field}"
end
