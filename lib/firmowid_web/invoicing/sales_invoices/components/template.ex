defmodule FirmowidWeb.Invoicing.SalesInvoices.Components.Template do
  @moduledoc false
  use FirmowidWeb, :html

  import FirmowidWeb.DesignSystem.Components.Link
  import Phoenix.Component, except: [link: 1]

  alias Firmowid.Ash.Ksef
  alias Firmowid.Ash.Ksef.Services.InvoiceRenderer
  alias Firmowid.Ash.Ksef.VatRate
  alias FirmowidWeb.Invoicing.Components.Print

  attr :sales_invoice, :map, required: true
  attr :show_vat, :boolean, default: true
  attr :logo_data_uri, :string, default: nil
  attr :logo_url, :string, default: nil

  defp invoice_header(assigns) do
    ~H"""
    <div class="mt-1 flex justify-between text-[10px]">
      <div class="flex flex-col gap-x-2">
        <div class="text-sm uppercase">
          {case @sales_invoice.invoice_type do
            :poland ->
              case @sales_invoice.ksef_invoice_kind do
                :vat -> [(@show_vat && "Faktura VAT") || "Faktura"]
                :kor -> ["Faktura korygująca"]
              end

            :foreign ->
              case @sales_invoice.ksef_invoice_kind do
                :vat ->
                  [(@show_vat && "Faktura VAT / VAT Invoice:") || "Faktura / Invoice:"]

                :kor ->
                  ["Faktura korygująca / Correction Invoice"]
              end
          end}
          <span class="font-bold">
            {@sales_invoice.invoice_number}
          </span>
        </div>

        <%= if @sales_invoice.ksef_invoice_kind == :kor do %>
          <div class="mt-1">
            <span>
              {case @sales_invoice.invoice_type do
                :poland -> "Do faktury nr "
                :foreign -> "Do faktury nr / For invoice no. "
              end}
            </span>
            <span class="font-bold">{@sales_invoice.corrected_invoice.invoice_number}</span>
            <span>
              {case @sales_invoice.invoice_type do
                :poland -> "z dnia"
                :foreign -> "z dnia / dated"
              end}
              {@sales_invoice.corrected_invoice.issue_date |> Calendar.strftime("%d.%m.%Y")}
            </span>
          </div>

          <%= if @sales_invoice.correction_reason && @sales_invoice.correction_reason != "" do %>
            <div class="mt-1">
              <span>
                {case @sales_invoice.invoice_type do
                  :poland -> "Przyczyna korekty:"
                  :foreign -> "Przyczyna korekty / Correction reason:"
                end}
              </span>
              <span class="font-bold">{@sales_invoice.correction_reason}</span>
            </div>
          <% end %>
        <% end %>

        <div class={if @sales_invoice.ksef_invoice_kind == :kor, do: "mt-4", else: "mt-2"}>
          <span>
            {case @sales_invoice.invoice_type do
              :poland -> "Data wystawienia:"
              :foreign -> "Data wystawienia / Issue date:"
            end}
          </span>
          <span class="font-bold">
            {@sales_invoice.issue_date |> Calendar.strftime("%d.%m.%Y")}
          </span>
        </div>
        <div class="mt-1">
          <span>
            {case @sales_invoice.invoice_type do
              :poland -> "Data sprzedaży:"
              :foreign -> "Data sprzedaży / Sale date:"
            end}
          </span>
          <span class="font-bold">
            {@sales_invoice.sale_date |> Calendar.strftime("%d.%m.%Y")}
          </span>
        </div>
      </div>
      <div>
        <div class="flex items-center gap-4">
          <%= if @logo_data_uri do %>
            <img src={@logo_data_uri} class="size-8" />
          <% else %>
            <img
              :if={@logo_url}
              src={@logo_url}
              class="size-8"
            />
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  attr :sales_invoice, :map, required: true

  defp seller_buyer_section(assigns) do
    ~H"""
    <div class="grid grid-cols-2 gap-5 text-[10px]/[14px]">
      <div>
        <h2 class="text-grey-600 mb-2 text-[8px] font-bold">
          {case @sales_invoice.invoice_type do
            :poland -> "SPRZEDAWCA"
            :foreign -> "SPRZEDAWCA / SELLER"
          end}
        </h2>
        <div class="grid grid-cols-[auto_1fr] gap-1">
          <span class="text-[8px]">
            {case @sales_invoice.invoice_type do
              :poland -> "Nazwa:"
              :foreign -> "Nazwa / Name:"
            end}
          </span>
          <span class="font-bold">
            {@sales_invoice.seller_display_name}
          </span>

          <span class="text-[8px]">
            {case @sales_invoice.invoice_type do
              :poland -> "Adres:"
              :foreign -> "Adres / Address:"
            end}
          </span>
          <span>{@sales_invoice.seller_address}</span>

          <span class="text-[8px]">
            {case @sales_invoice.invoice_type do
              :poland -> "NIP:"
              :foreign -> "VAT-ID:"
            end}
          </span>
          <span>
            <%= if @sales_invoice.invoice_type == :foreign do %>
              PL{@sales_invoice.seller_nip}
            <% else %>
              {@sales_invoice.seller_nip}
            <% end %>
          </span>
        </div>
      </div>
      <div>
        <h2 class="text-grey-600 mb-2 text-[8px] font-bold">
          {case @sales_invoice.invoice_type do
            :poland -> "NABYWCA"
            :foreign -> "NABYWCA / BUYER"
          end}
        </h2>
        <div class="grid grid-cols-[auto_1fr] gap-1">
          <%= if @sales_invoice.buyer_type == :company do %>
            <span class="text-[8px]">
              {case @sales_invoice.invoice_type do
                :poland -> "Nazwa:"
                :foreign -> "Nazwa / Name:"
              end}
            </span>
            <span class="font-bold">
              {@sales_invoice.buyer_full_name}
            </span>
          <% end %>

          <%= if @sales_invoice.buyer_type == :individual do %>
            <span class="text-[8px]">
              {case @sales_invoice.invoice_type do
                :poland -> "Imię i nazwisko:"
                :foreign -> "Imię i nazwisko / Name and surname:"
              end}
            </span>
            <span>{@sales_invoice.buyer_given_name} {@sales_invoice.buyer_surname}</span>
          <% end %>

          <%= if @sales_invoice.buyer_address && @sales_invoice.buyer_address != "" do %>
            <span class="text-[8px]">
              {case @sales_invoice.invoice_type do
                :poland -> "Adres:"
                :foreign -> "Adres / Address:"
              end}
            </span>
            <span>{@sales_invoice.buyer_address}</span>
          <% end %>

          <%= if @sales_invoice.buyer_type == :individual and @sales_invoice.invoice_type == :poland do %>
            <%= if !is_nil(@sales_invoice.buyer_pesel) and
                @sales_invoice.buyer_pesel != "" do %>
              <span class="text-[8px]">PESEL:</span>
              <span class="text-[10px]">{@sales_invoice.buyer_pesel}</span>
            <% end %>
          <% else %>
            <span class="text-[8px]">
              {case @sales_invoice.invoice_type do
                :poland -> "NIP:"
                :foreign -> "VAT-ID:"
              end}
            </span>
            <span class="text-[10px]">
              <%= if @sales_invoice.invoice_type == :foreign and @sales_invoice.buyer_country do %>
                {@sales_invoice.buyer_country}{@sales_invoice.buyer_id}
              <% else %>
                {@sales_invoice.buyer_id}
              <% end %>
            </span>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  attr :sales_invoice, :map, required: true
  attr :show_vat, :boolean, default: true

  defp items_table(assigns) do
    ~H"""
    <div>
      <h2 class="text-grey-600 text-[8px] font-bold">
        {case @sales_invoice.invoice_type do
          :poland -> "TOWARY LUB USŁUGI"
          :foreign -> "TOWARY LUB USŁUGI / GOODS OR SERVICES"
        end}
      </h2>
      <table class="mt-1 w-full">
        <thead class="text-darkGrey/70 text-[8px]">
          <%= if @sales_invoice.invoice_type == :poland  do %>
            <tr class="py-2">
              <th class="text-left">Lp.</th>
              <th class="text-left">Nazwa</th>
              <th class="text-right">Ilość</th>
              <th class="text-right">J. m.</th>
              <%= if @show_vat do %>
                <th class="text-right">Cena netto</th>
                <th class="w-12 pl-5 text-center">Vat</th>
                <th class="text-right">Wartość netto</th>
                <th class="text-right">Wartość brutto</th>
              <% else %>
                <th class="text-right">Cena jednostkowa</th>
                <th class="text-right">Cena sumaryczna</th>
              <% end %>
            </tr>
          <% end %>
          <%= if @sales_invoice.invoice_type == :foreign do %>
            <tr class="pt-2">
              <th class="text-left">Lp.</th>
              <th class="text-left">Nazwa</th>
              <th class="text-right">Ilość</th>
              <th class="text-right">J. m.</th>
              <th class="text-right">Cena jednostkowa</th>
              <th class="text-right">Cena sumaryczna</th>
            </tr>
            <tr class="pb-2">
              <th class="text-left">No</th>
              <th class="text-left">Name</th>
              <th class="text-right">Count</th>
              <th class="text-right">Unit</th>
              <th class="text-right">Unit price</th>
              <th class="text-right">Total price</th>
            </tr>
          <% end %>
        </thead>
        <tbody class="text-[10px]">
          <%= for {item, index} <- Enum.with_index(@sales_invoice.sales_invoice_items, 1) do %>
            <tr class="align-top">
              <td class="py-1">{index}.</td>
              <td class="max-w-40 py-1">{item.name}</td>
              <td class="py-1 text-right">{item.quantity}</td>
              <td class="py-1 text-right">{item.unit}</td>
              <%= if @sales_invoice.invoice_type == :poland do %>
                <td class="py-1 text-right">
                  {Money.new(
                    @sales_invoice.currency,
                    item.unit_price,
                    currency_symbol: ""
                  )}
                </td>
                <td :if={@show_vat} class="py-1 text-right">
                  {VatRate.label(item.vat_rate)}
                </td>
                <td class="py-1 text-right">
                  {Money.new(
                    @sales_invoice.currency,
                    item.net_value,
                    currency_symbol: ""
                  )}
                </td>
                <td :if={@show_vat} class="py-1 text-right">
                  {Money.new(
                    @sales_invoice.currency,
                    item.gross_value,
                    currency_symbol: ""
                  )}
                </td>
              <% end %>
              <%= if @sales_invoice.invoice_type == :foreign do %>
                <td class="py-1 text-right">
                  {Money.new!(@sales_invoice.currency, item.unit_price)
                  |> Money.to_string!(currency_symbol: "")}
                </td>
                <td class="py-1 text-right">
                  {Money.new!(
                    @sales_invoice.currency,
                    item.net_value
                  )
                  |> Money.to_string!(currency_symbol: "")}
                </td>
              <% end %>
            </tr>
          <% end %>
        </tbody>
      </table>
    </div>
    """
  end

  attr :sales_invoice, :map, required: true
  attr :show_vat, :boolean, default: true
  attr :items, :list, required: true
  attr :title, :string, required: true

  defp correction_items_section(assigns) do
    ~H"""
    <div>
      <h3 class="text-grey-600 text-[8px] font-bold uppercase">
        {@title}
      </h3>
      <table class="mt-1 w-full">
        <thead class="text-darkGrey/70 text-[8px]/[11px]">
          <%= if @sales_invoice.invoice_type == :poland do %>
            <tr class="*:pb-1">
              <th class="text-left">Lp.</th>
              <th class="text-left">Nazwa</th>
              <th class="text-right">Ilość</th>
              <th class="text-right">J. m.</th>
              <%= if @show_vat do %>
                <th class="text-right">Cena netto</th>
                <th class="w-12 pl-5 text-center">Vat</th>
                <th class="text-right">Wartość netto</th>
                <th class="text-right">Wartość brutto</th>
              <% else %>
                <th class="text-right">Cena jednostkowa</th>
                <th class="text-right">Cena sumaryczna</th>
              <% end %>
            </tr>
          <% end %>
          <%= if @sales_invoice.invoice_type == :foreign do %>
            <tr class="*:pb-0.5">
              <th class="text-left">Lp.</th>
              <th class="text-left">Nazwa</th>
              <th class="text-right">Ilość</th>
              <th class="text-right">J. m.</th>
              <th class="text-right">Cena jednostkowa</th>
              <th class="text-right">Cena sumaryczna</th>
            </tr>
            <tr class="*:pb-1">
              <th class="text-left">No</th>
              <th class="text-left">Name</th>
              <th class="text-right">Count</th>
              <th class="text-right">Unit</th>
              <th class="text-right">Unit price</th>
              <th class="text-right">Total price</th>
            </tr>
          <% end %>
        </thead>
        <tbody class="text-[10px]/[14px]">
          <%= for {item, index} <- Enum.with_index(@items, 1) do %>
            <tr class="align-top *:py-1 last:*:pb-0">
              <td class="py-1">{index}.</td>
              <td class="max-w-40 py-1">{item.name}</td>
              <td class="py-1 text-right">{item.quantity}</td>
              <td class="py-1 text-right">{item.unit}</td>
              <%= if @sales_invoice.invoice_type == :poland do %>
                <td class="py-1 text-right">
                  {Money.new(
                    @sales_invoice.currency,
                    item.unit_price,
                    currency_symbol: ""
                  )}
                </td>
                <td :if={@show_vat} class="py-1 text-right">
                  {VatRate.label(item.vat_rate)}
                </td>
                <td class="py-1 text-right">
                  {Money.new(
                    @sales_invoice.currency,
                    item.net_value,
                    currency_symbol: ""
                  )}
                </td>
                <td :if={@show_vat} class="py-1 text-right">
                  {Money.new(
                    @sales_invoice.currency,
                    item.gross_value,
                    currency_symbol: ""
                  )}
                </td>
              <% end %>
              <%= if @sales_invoice.invoice_type == :foreign do %>
                <td class="py-1 text-right">
                  {Money.new!(@sales_invoice.currency, item.unit_price)
                  |> Money.to_string!(currency_symbol: "")}
                </td>
                <td class="py-1 text-right">
                  {Money.new!(
                    @sales_invoice.currency,
                    item.net_value
                  )
                  |> Money.to_string!(currency_symbol: "")}
                </td>
              <% end %>
            </tr>
          <% end %>
        </tbody>
      </table>
    </div>
    """
  end

  attr :sales_invoice, :map, required: true
  attr :show_vat, :boolean, default: true
  attr :reference_invoice, :map, required: true

  defp correction_items_table(assigns) do
    before_title =
      case assigns.sales_invoice.invoice_type do
        :poland -> "Przed korektą"
        :foreign -> "Przed korektą / Before correction"
      end

    after_title =
      case assigns.sales_invoice.invoice_type do
        :poland -> "Po korekcie"
        :foreign -> "Po korekcie / After correction"
      end

    assigns =
      assigns
      |> assign(:before_title, before_title)
      |> assign(:after_title, after_title)

    ~H"""
    <div class="mb-4 space-y-2.5">
      <h2 class="text-darkGrey/70 mb-4 text-[8px] font-bold">
        {case @sales_invoice.invoice_type do
          :poland -> "TOWARY LUB USŁUGI"
          :foreign -> "TOWARY LUB USŁUGI / GOODS OR SERVICES"
        end}
      </h2>
      <.correction_items_section
        sales_invoice={@sales_invoice}
        show_vat={@show_vat}
        items={@reference_invoice.sales_invoice_items}
        title={@before_title}
      />
      <.correction_items_section
        sales_invoice={@sales_invoice}
        show_vat={@show_vat}
        items={@sales_invoice.sales_invoice_items}
        title={@after_title}
      />
    </div>
    """
  end

  attr :sales_invoice, :map, required: true
  attr :show_vat, :boolean, default: true

  defp summary(assigns) do
    ~H"""
    <div class={[
      "bg-grey-100 mt-6 ml-auto flex flex-col gap-2 rounded-md px-4 py-2 text-[10px]",
      if(@sales_invoice.invoice_type == :poland, do: "w-63.75", else: "w-86.75")
    ]}>
      <h2 class="text-grey-600 text-[8px] font-bold uppercase">
        {case @sales_invoice.invoice_type do
          :poland -> "Podsumowanie"
          :foreign -> "Podsumowanie / Summary"
        end}
      </h2>

      <%= if @sales_invoice.invoice_type == :poland do %>
        <div class="flex items-center justify-between">
          <span>Wartość{if @show_vat, do: " netto"}:</span>
          <span>
            {Money.new(
              @sales_invoice.currency,
              @sales_invoice.net_value
            )}
          </span>
        </div>
        <%= if @show_vat do %>
          <div class="flex items-center justify-between">
            <span>Wartość całkowita VAT:</span>
            <span>
              {Money.new(
                @sales_invoice.currency,
                @sales_invoice.vat_value
              )}
            </span>
          </div>
          <div class="flex items-center justify-between">
            <span>Razem do zapłaty:</span>
            <span class="text-sm/tight font-bold">
              {@sales_invoice.amount}
            </span>
          </div>
        <% end %>
      <% end %>
      <%= if @sales_invoice.invoice_type == :foreign do %>
        <div class="flex items-center justify-between">
          <span>Wartość całkowita VAT / Total VAT:</span>
          <span>
            nie dotyczy / not applicable
          </span>
        </div>
        <div class="flex items-center justify-between font-bold">
          <span>Razem do zapłaty / Total:</span>
          <span class="text-sm/snug">
            {@sales_invoice.amount}
          </span>
        </div>
      <% end %>
    </div>
    """
  end

  attr :sales_invoice, :map, required: true
  attr :show_vat, :boolean, default: true
  attr :reference_invoice, :map, required: true

  defp correction_summary(assigns) do
    invoice = assigns.sales_invoice
    reference = assigns.reference_invoice

    before_net = reference.net_value
    before_vat = reference.vat_value

    after_net = invoice.net_value
    after_vat = invoice.vat_value

    delta_net = Decimal.sub(after_net, before_net)
    delta_vat = Decimal.sub(after_vat, before_vat)

    assigns =
      assigns
      |> assign(:before_currency, reference.currency)
      |> assign(:after_currency, invoice.currency)
      |> assign(:before_net, before_net)
      |> assign(:before_vat, before_vat)
      |> assign(:after_net, after_net)
      |> assign(:after_vat, after_vat)
      |> assign(:delta_net, delta_net)
      |> assign(:delta_vat, delta_vat)

    ~H"""
    <div class="bg-greyButtonBg/30 rounded-md px-4 py-2 text-[10px]/[14px]">
      <table class="w-full">
        <thead class="text-grey-600 text-[8px]">
          <%= if @sales_invoice.invoice_type == :poland do %>
            <tr class="*:pb-2.5">
              <th class="text-left uppercase">Podsumowanie</th>
              <th class="px-2 text-right">Przed korektą</th>
              <th class="px-2 text-right">Po korekcie</th>
              <th class="pl-2 text-right">Różnica</th>
            </tr>
          <% else %>
            <tr>
              <th class="text-left uppercase">Podsumowanie</th>
              <th class="px-2 text-right">Przed korektą</th>
              <th class="px-2 text-right">Po korekcie</th>
              <th class="pl-2 text-right">Różnica</th>
            </tr>
            <tr class="*:pb-2.5">
              <th class="text-left uppercase">Summary</th>
              <th class="px-2 text-right">Before correction</th>
              <th class="px-2 text-right">After correction</th>
              <th class="pl-2 text-right">Difference</th>
            </tr>
          <% end %>
        </thead>
        <tbody>
          <%= if @sales_invoice.invoice_type == :poland do %>
            <tr>
              <td class="py-0.5 text-[8px]">
                Wartość{if @show_vat, do: " netto"}:
              </td>
              <td class="text-grey-600 px-2 py-0.5 text-right line-through">
                {Money.new(@before_currency, @before_net)}
              </td>
              <td class="px-2 py-0.5 text-right">{Money.new(@after_currency, @after_net)}</td>
              <td class="py-0.5 pl-2 text-right font-medium">
                {signed_money_difference(
                  @before_currency,
                  @before_net,
                  @after_currency,
                  @after_net
                )}
              </td>
            </tr>
            <%= if @show_vat do %>
              <tr>
                <td class="py-0.5 text-[8px]">
                  Całkowita wartość VAT:
                </td>

                <td class="text-grey-600 px-2 py-0.5 text-right line-through">
                  {Money.new(@before_currency, @before_vat)}
                </td>
                <td class="px-2 py-0.5 text-right">{Money.new(@after_currency, @after_vat)}</td>
                <td class="py-0.5 pl-2 text-right font-medium">
                  {signed_money_difference(
                    @before_currency,
                    @before_vat,
                    @after_currency,
                    @after_vat
                  )}
                </td>
              </tr>

              <tr class="text-[14px]/[20px] font-bold">
                <td class="pt-0.5 text-[8px] font-normal">
                  Razem do zapłaty:
                </td>
                <td class="text-grey-600 px-2 pt-0.5 text-right line-through">
                  {@reference_invoice.amount}
                </td>
                <td class="px-2 pt-0.5 text-right">{@sales_invoice.amount}</td>
                <td class="pt-0.5 pl-2 text-right">
                  {signed_money_difference(@reference_invoice.amount, @sales_invoice.amount)}
                </td>
              </tr>
            <% end %>
          <% end %>
          <%= if @sales_invoice.invoice_type == :foreign do %>
            <tr>
              <td class="py-0.5 text-[8px]">
                Wartość całkowita VAT / Total VAT:
              </td>
              <td class="py-0.5 pl-2 text-right" colspan="3">
                nie dotyczy / not applicable
              </td>
            </tr>

            <tr class="text-[14px]/[20px] font-bold">
              <td class="pt-0.5 text-[8px] font-normal">
                Razem do zapłaty / Total:
              </td>
              <td class="text-grey-600 px-2 pt-0.5 text-right line-through">
                {@reference_invoice.amount}
              </td>
              <td class="px-2 pt-0.5 text-right">{@sales_invoice.amount}</td>
              <td class="pt-0.5 pl-2 text-right">
                {signed_money_difference(@reference_invoice.amount, @sales_invoice.amount)}
              </td>
            </tr>
          <% end %>
        </tbody>
      </table>
    </div>
    """
  end

  defp signed_money(currency, value) do
    money = Money.new(currency, value)

    if Decimal.positive?(value) do
      "+#{money}"
    else
      to_string(money)
    end
  end

  defp signed_money_difference(currency, before, currency, corrected),
    do: signed_money(currency, Decimal.sub(corrected, before))

  defp signed_money_difference(_before_currency, _before, _after_currency, _after), do: "—"

  defp signed_money_difference(%Money{currency: currency, amount: before}, %Money{currency: currency, amount: corrected}),
    do: signed_money(currency, Decimal.sub(corrected, before))

  defp signed_money_difference(%Money{}, %Money{}), do: "—"

  attr :sales_invoice, :map, required: true

  defp payment_details(assigns) do
    ~H"""
    <h2 class="text-darkGrey/70 mb-2 text-[8px] font-bold uppercase">
      {case @sales_invoice.invoice_type do
        :poland -> "Płatność"
        :foreign -> "Płatność / Payment"
      end}
    </h2>
    <div class="flex w-fit flex-col gap-1 text-[10px]/[14px]">
      <%= if @sales_invoice.invoice_type == :poland do %>
        <div>
          Metoda płatności: {case @sales_invoice.payment_method do
            :cash -> "Gotówka"
            :card -> "Karta"
            :voucher -> "Bon"
            :check -> "Czek"
            :credit -> "Kredyt"
            :transfer -> "Przelew"
            :mobile -> "Mobilna"
          end} | nr konta: {@sales_invoice.seller_account_number}
        </div>
      <% end %>
      <%= if @sales_invoice.invoice_type == :foreign do %>
        <div>
          Metoda płatności / Payment method: {case @sales_invoice.payment_method do
            :cash -> "Cash"
            :card -> "Card"
            :voucher -> "Voucher"
            :check -> "Check"
            :credit -> "Credit"
            :transfer -> "Transfer"
            :mobile -> "Mobile"
          end}
        </div>
        <div>
          Nr konta / Bank account number: {@sales_invoice.seller_account_number}
        </div>
      <% end %>
      <div>
        {case @sales_invoice.invoice_type do
          :poland -> "Termin płatności:"
          :foreign -> "Termin płatności / Payment deadline:"
        end}

        <span class="font-bold">
          {@sales_invoice.due_date |> Calendar.strftime("%d.%m.%Y")}
        </span>
      </div>
      <div class="font-bold">
        <%= if @sales_invoice.is_reverse_charge do %>
          Odwrotne obciążenie / Reverse charge
        <% end %>
        <%= if @sales_invoice.is_cash_account do %>
          Metoda kasowa
        <% end %>
      </div>
    </div>
    """
  end

  attr :footer_logo_data_uri, :string, default: nil
  attr :invoice_type, :atom, required: true

  defp footer(assigns) do
    ~H"""
    <div class="absolute inset-x-0 bottom-8 left-8 flex items-end justify-start text-[8px]">
      <div class="flex items-end gap-0.5">
        <%= if @footer_logo_data_uri do %>
          <img src={@footer_logo_data_uri} class="size-10" />
        <% else %>
          <img src="/images/invoice_firmowid_logo.png" class="size-10" />
        <% end %>
        <p class="text-center">
          {case @invoice_type do
            :poland -> "Faktura wygenerowana za pomocą"
            :foreign -> "Invoice from"
          end}
          <.link
            kind="unstyled"
            external="https://firmowid.pl"
            target="_blank"
            rel="noreferrer noopener"
            class="font-black"
          >
            Firmowid.pl
          </.link>
        </p>
      </div>
    </div>
    """
  end

  attr :sales_invoice, :map, required: true

  defp qrcode(assigns) do
    qrcode =
      assigns.sales_invoice
      |> Ksef.invoice_url!()
      |> EQRCode.encode()
      |> EQRCode.svg()
      |> Base.encode64()

    assigns = assign(assigns, :qrcode, qrcode)

    ~H"""
    <div class="absolute right-8 bottom-8 flex w-26 flex-col items-start justify-center">
      <p class="text-grey-600 px-1 text-[8px] font-medium">
        <%= case @sales_invoice.invoice_type do %>
          <% :poland -> %>
            Sprawdź w KSeF
          <% :foreign -> %>
            Sprawdź w KSeF<br />View in KSeF
        <% end %>
      </p>
      <img src={"data:image/svg+xml; base64, #{@qrcode}"} alt="KSeF QR code" width="104" height="104" />
      <p class="max-w-26 text-center text-[8px]">{@sales_invoice.ksef_number}</p>
    </div>
    """
  end

  attr :sales_invoice, :map, required: true
  attr :show_vat, :boolean, default: true
  attr :logo_data_uri, :string, default: nil
  attr :logo_url, :string, default: nil
  attr :footer_logo_data_uri, :string, default: nil
  attr :reference_invoice, :map, default: nil
  attr :currency_rate, :map, default: nil

  def sales_invoice(assigns) do
    if assigns.sales_invoice.ksef_invoice_kind == :kor and is_nil(assigns.reference_invoice) do
      raise ArgumentError,
            "reference_invoice is required when rendering a correction invoice (ksef_invoice_kind: :kor)"
    end

    ~H"""
    <Print.a4_page>
      <.invoice_header
        sales_invoice={@sales_invoice}
        show_vat={@show_vat}
        logo_data_uri={@logo_data_uri}
        logo_url={@logo_url}
      />
      <hr class="border-greyButtonBg my-6" />
      <.seller_buyer_section sales_invoice={@sales_invoice} />
      <hr class="border-greyButtonBg my-6" />
      <%= if @sales_invoice.ksef_invoice_kind == :kor do %>
        <% items_changed? =
          correction_items_table_changed?(@sales_invoice, @reference_invoice, @show_vat) %>
        <%= if items_changed? do %>
          <.correction_items_table
            sales_invoice={@sales_invoice}
            show_vat={@show_vat}
            reference_invoice={@reference_invoice}
          />
        <% end %>
        <.correction_summary
          sales_invoice={@sales_invoice}
          show_vat={@show_vat}
          reference_invoice={@reference_invoice}
        />
      <% else %>
        <.items_table sales_invoice={@sales_invoice} show_vat={@show_vat} />
        <.summary sales_invoice={@sales_invoice} show_vat={@show_vat} />
      <% end %>

      <hr class="border-greyButtonBg my-6" />
      <%= if @sales_invoice.currency != "PLN" do %>
        <div class="mb-3">
          <h2 class="text-darkGrey/70 mb-2 text-[8px] font-bold uppercase">
            {case @sales_invoice.invoice_type do
              :poland -> "Przewalutowanie"
              :foreign -> "Przewalutowanie / Currency conversion"
            end}
          </h2>
          <div>
            <div class="text-[10px]/[14px]">
              Kurs {@sales_invoice.currency} / {@sales_invoice.currency} exchange rate: {@currency_rate.rate
              |> Firmowid.Cldr.Number.to_string!(format: "#0.0000 ¤¤", currency: "PLN")}
            </div>
            <div class="mt-1 text-[8px]">
              Kurs waluty wg. tabeli kursów średnich nr {@currency_rate.table_number} z dnia {@currency_rate.effective_date}
              <br />
              Exchange rate according to average exchange rate table No. {@currency_rate.table_number} of {@currency_rate.effective_date}
            </div>
          </div>
        </div>
      <% end %>
      <%= if InvoiceRenderer.has_exempt_items?(@sales_invoice) do %>
        <div class="mb-3">
          <h3 class="text-darkGrey/70 mb-2 text-[8px] font-bold uppercase">Zwolnienie z VAT</h3>
          <div class="text-[10px]/[14px]">
            Podstawa zwolnienia z VAT:
            <span class="font-bold">
              {InvoiceRenderer.exemption_basis_label(
                Map.get(@sales_invoice, :vat_exemption_type) || :art_113,
                @sales_invoice
              )}
            </span>
          </div>
        </div>
      <% end %>
      <.payment_details sales_invoice={@sales_invoice} />
      <%= if @sales_invoice.invoice_note && @sales_invoice.invoice_note != "" do %>
        <div class="mt-4 text-[10px]/[14px]">
          <h3 class="text-darkGrey/70 mb-2 text-[8px] font-bold uppercase">Uwagi / Notes</h3>
          <div>{@sales_invoice.invoice_note}</div>
        </div>
      <% end %>
      <.footer
        footer_logo_data_uri={@footer_logo_data_uri}
        invoice_type={@sales_invoice.invoice_type}
      />
      <.qrcode
        :if={@sales_invoice.ksef_number}
        sales_invoice={@sales_invoice}
      />
    </Print.a4_page>

    <Print.internal_note_page
      :if={@include_internal_note_page && @sales_invoice.internal_note not in [nil, ""]}
      internal_note={@sales_invoice.internal_note}
      footer_logo_data_uri={@footer_logo_data_uri}
    />
    """
  end

  defp correction_items_table_changed?(
         %{sales_invoice_items: current_items, invoice_type: invoice_type},
         %{sales_invoice_items: reference_items},
         show_vat
       ) do
    if length(current_items) == length(reference_items) do
      compare_vat_rate? = invoice_type == :poland and show_vat

      current_items
      |> Enum.zip(reference_items)
      |> Enum.any?(fn {current_item, reference_item} ->
        current_item.name != reference_item.name or
          not Decimal.eq?(current_item.quantity, reference_item.quantity) or
          current_item.unit != reference_item.unit or
          not Decimal.eq?(current_item.unit_price, reference_item.unit_price) or
          (compare_vat_rate? and current_item.vat_rate != reference_item.vat_rate)
      end)
    else
      true
    end
  end
end
