defmodule FirmowidWeb.SalesInvoicesLive.Components.InvoiceItems do
  @moduledoc false
  use FirmowidWeb, :html

  alias Firmowid.Ksef.VatRate
  alias Firmowid.SalesInvoices.SalesInvoice
  alias Firmowid.SalesInvoices.SalesInvoiceItem

  defp currency_options do
    # Use only currencies supported by NBP (plus PLN as base currency)
    nbp_currencies = Firmowid.Nbp.ApiClient.supported_currencies()
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

  defp compute_vat_options(invoice, is_reverse_charge) do
    if is_reverse_charge do
      {VatRate.select_options_short(["oo"]), true}
    else
      buyer_id_type = SalesInvoice.buyer_id_type(invoice)

      case VatRate.available_rates(invoice.buyer_country, buyer_id_type) do
        {:select, rates, _default} -> {VatRate.select_options_short(rates), false}
        {:fixed, rate} -> {VatRate.select_options_short([rate]), true}
      end
    end
  end

  defp invoice_summary(%Ecto.Changeset{} = changeset) do
    items = Ecto.Changeset.get_assoc(changeset, :sales_invoice_items, :struct)
    currency = Ecto.Changeset.get_field(changeset, :currency)

    invoice = %{sales_invoice_items: items, currency: currency}

    %{
      net_value: Money.new(currency, SalesInvoice.get_net_value(invoice)),
      vat_value: Money.new(currency, SalesInvoice.get_vat_value(invoice)),
      gross_value: Money.new(currency, SalesInvoice.get_gross_value(invoice))
    }
  end

  attr :invoice, SalesInvoice, required: true
  attr :invoice_changeset, Ecto.Changeset, required: true

  def invoice_items(%{invoice_changeset: changeset, invoice: invoice}) do
    sales_invoice_items = Ecto.Changeset.get_assoc(changeset, :sales_invoice_items, :struct)

    single_sales_invoice_item =
      case sales_invoice_items do
        [_single_item] -> true
        _ -> false
      end

    changeset =
      case sales_invoice_items do
        [] ->
          Ecto.Changeset.put_assoc(changeset, :sales_invoice_items, [%SalesInvoiceItem{}])

        _ ->
          changeset
      end

    # Compute VAT rate options based on buyer context
    is_reverse_charge = Ecto.Changeset.get_field(changeset, :is_reverse_charge) || false
    {vat_options, vat_disabled?} = compute_vat_options(invoice, is_reverse_charge)

    assigns = %{
      invoice: invoice,
      items_form: to_form(changeset, action: :validate),
      summary: invoice_summary(changeset),
      single_item?: single_sales_invoice_item,
      vat_options: vat_options,
      vat_disabled?: vat_disabled?
    }

    ~H"""
    <div class="col-start-2 col-end-9 space-y-8 mb-8">
      <div class="flex flex-row items-center gap-5 mb-2">
        <label class="text-grey-700 flex flex-row items-center gap-5 mr-auto">
          <span><strong>1.</strong> Wybrana waluta</span>
          <.input
            field={@items_form[:currency]}
            type="select"
            options={currency_options()}
            disabled={SalesInvoice.buyer_id_type(@invoice) == :nip}
            new={true}
          />
        </label>

        <div class="flex flex-row">
          <.switch
            :if={@invoice.buyer_country != "PL"}
            field={@items_form[:is_reverse_charge]}
            color="turquoise"
            class="flex-row-reverse gap-2 text-sm text-grey-700"
          >
            <:label_slot>
              Reverse charge
              <Lucideicons.info
                id="reverse-charge-tooltip"
                phx-hook="Tippy"
                data-tippy-content="Reverse charge (odwrotne obciążenie) to mechanizm, w którym obowiązek rozliczenia podatku VAT spoczywa na nabywcy usługi; dotyczy m.in. importu usług z Unii Europejskiej."
                class="size-4 ml-[0.125rem]"
              />
            </:label_slot>
          </.switch>

          <div class="flex flex-row items-center gap-3">
            <.switch
              :if={false}
              field={@items_form[:is_reverse_charge]}
              label="Rabat"
              color="turquoise"
              class="flex-row-reverse gap-2 text-sm text-grey-700"
            />
            <.switch
              :if={false}
              field={@items_form[:is_reverse_charge]}
              label="PKWiU"
              color="turquoise"
              class="flex-row-reverse gap-2 text-sm text-grey-700"
            />
          </div>
        </div>
      </div>
      <div class="flex flex-row items-end gap-4">
        <p class="text-grey-700 mr-auto"><strong>2.</strong> Pozycje na fakturze</p>

        <.button :if={false} type="button" size="small" color="light_grey" new={true}>
          <Lucideicons.copy /> Skopiuj poprzednie pozycje
        </.button>
        <.button :if={false} type="button" size="small" color="light_grey" new={true}>
          <Lucideicons.clock /> Zaciągnij godziny
        </.button>
      </div>
    </div>

    <div class="col-start-2 col-end-9 grid grid-cols-subgrid text-sm/snug text-grey-700 mb-1 py-1 pl-2">
      <p id="name">Towar/usługa</p>
      <p id="quantity">Ilość</p>
      <p>VAT</p>
      <p>Jednostka</p>
      <p id="price">Cena netto</p>

      <%= if to_boolean(@items_form[:is_reverse_charge].value) do %>
        <p class="text-end col-span-2">Wartość</p>
      <% else %>
        <p class="text-end">Wartość netto</p>
        <p class="text-end">Wartość brutto</p>
      <% end %>
    </div>

    <div class="col-span-full grid grid-cols-subgrid gap-y-2" id="items_list" phx-hook=".Sortable">
      <.inputs_for :let={item} field={@items_form[:sales_invoice_items]}>
        <div class="col-span-full grid grid-cols-subgrid items-center">
          <input type="hidden" name="sales_invoice[items_sort][]" value={item.index} />

          <Lucideicons.grip_vertical class="text-grey-700 mr-1" drag-handle />
          <.input
            field={item[:name]}
            placeholder="Wprowadź nazwę"
            phx-debounce
            class="w-full"
            new={true}
            is_tooltip={true}
            reference="name"
          />
          <.input
            field={item[:quantity]}
            placeholder="0"
            phx-debounce
            type="number"
            step=".000001"
            min="0"
            class="w-16"
            input_class="text-center"
            new={true}
            is_tooltip={true}
            reference="quantity"
            onkeydown="return event.key !== '-'"
          />

          <.input
            field={item[:vat_rate]}
            type="select"
            options={@vat_options}
            phx-debounce
            class="w-24"
            new={true}
            readonly={@vat_disabled?}
          />
          <.input
            field={item[:unit]}
            type="select"
            placeholder="0,00"
            phx-debounce
            class="w-24"
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
              class="w-24"
              input_class="text-center"
              new={true}
              is_tooltip={true}
              reference="price"
              onkeydown="return event.key !== '-'"
            />
            <p class="text-sm text-grey-500">{@items_form[:currency].value}</p>
          </div>

          <%= if to_boolean(@items_form[:is_reverse_charge].value) do %>
            <% gross_value =
              Money.new(@items_form[:currency].value, item[:gross_value].value || "0.00") %>

            <p class={[
              "text-end w-[14.5rem] truncate col-span-2",
              if(Money.zero?(gross_value), do: "text-grey-500")
            ]}>
              {Money.to_string!(gross_value, currency_symbol: "")}
            </p>
          <% else %>
            <% net_value =
              Money.new(@items_form[:currency].value, item[:net_value].value || "0.00") %>
            <% gross_value =
              Money.new(@items_form[:currency].value, item[:gross_value].value || "0.00") %>

            <p class={[
              "text-end w-28 truncate",
              if(Money.zero?(net_value), do: "text-grey-500")
            ]}>
              {Money.to_string!(net_value, currency_symbol: "")}
            </p>
            <p class={[
              "text-end w-28 truncate",
              if(Money.zero?(gross_value), do: "text-grey-500")
            ]}>
              {Money.to_string!(gross_value, currency_symbol: "")}
            </p>
          <% end %>

          <button
            type="button"
            name="sales_invoice[items_drop][]"
            value={item.index}
            phx-click={JS.dispatch("change")}
            disabled={@single_item?}
            class="ml-1 transition-colors ease-out duration-200 text-grey-300 hover:text-grey-700 cursor-pointer disabled:cursor-default disabled:text-transparent"
          >
            <Lucideicons.x class="size-4" />
          </button>
        </div>
      </.inputs_for>

      <input type="hidden" name="sales_invoice[items_drop][]" />
    </div>

    <%!-- todo: add loading state --%>
    <.button
      type="button"
      name="sales_invoice[items_sort][]"
      value="new"
      phx-click={JS.dispatch("change")}
      class="col-start-2 col-span-1 mt-3"
      size="small"
      color="light_grey"
      new={true}
    >
      <Lucideicons.plus /> Dodaj pozycję
    </.button>

    <div class={[
      "col-start-1 col-end-9 ml-auto grid grid-cols-[1fr_repeat(2,min-content)] gap-y-2 gap-x-2 min-w-min w-72 mt-3 whitespace-nowrap items-center leading-snug",
      if(Money.zero?(@summary.net_value), do: "text-grey-500", else: "text-black")
    ]}>
      <%= if to_boolean(@items_form[:is_reverse_charge].value) do %>
        <p class="text-sm text-grey-500 text-left">Suma</p>
        <p class="text-[27px]/tight font-medium text-right">
          {Money.to_string!(@summary.gross_value, currency_symbol: "")}
        </p>
        <p class="text-right">{@items_form[:currency].value}</p>
      <% else %>
        <p class="text-sm text-grey-500 text-left">Suma netto</p>
        <p class="text-right">
          {Money.to_string!(@summary.net_value, currency_symbol: "")}
        </p>
        <p class="text-right">{@items_form[:currency].value}</p>

        <p class="text-sm text-grey-500 text-left">Suma VAT</p>
        <p class="text-right">
          {Money.to_string!(@summary.vat_value, currency_symbol: "")}
        </p>
        <p class="text-right">{@items_form[:currency].value}</p>

        <p class="text-sm text-grey-500 text-left">Suma brutto</p>
        <p class="text-[27px]/tight font-medium text-right">
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
end
