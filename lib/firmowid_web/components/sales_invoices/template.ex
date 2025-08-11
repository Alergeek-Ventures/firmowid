defmodule FirmowidWeb.SalesInvoices.Template do
  @moduledoc false
  use FirmowidWeb, :html

  attr :sales_invoice, :map, required: true
  attr :show_vat, :boolean, default: true

  defp invoice_header(assigns) do
    ~H"""
    <div class="flex justify-between mt-1 text-[10px]">
      <div class="flex flex-col gap-x-2">
        <div class="text-sm uppercase font-bold">
          {case @sales_invoice.invoice_type do
            :poland -> [(@show_vat && "Faktura VAT") || "Faktura"]
            :foreign -> [(@show_vat && "Faktura VAT / VAT Invoice:") || "Faktura / Invoice:"]
          end}
          {@sales_invoice.invoice_number}
        </div>
        <div class="mt-2">
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
        <div class="flex gap-4 items-center">
          <div class="text-right">
            <%= if @sales_invoice.is_reverse_charge do %>
              <div>Odwrotne obciążenie <br /> / Reverse charge</div>
            <% end %>
            <%= if @sales_invoice.is_cash_account do %>
              Metoda kasowa
            <% end %>
          </div>
          <img :if={@sales_invoice.logo_url} src={@sales_invoice.logo_url} class="w-8 h-8" />
        </div>
      </div>
    </div>
    """
  end

  attr :sales_invoice, :map, required: true

  defp seller_buyer_section(assigns) do
    ~H"""
    <div class="grid grid-cols-2 gap-7 text-[10px] leading-[14px]">
      <div>
        <h2 class=" text-darkGrey/70 text-[8px] font-bold mb-2">
          {case @sales_invoice.invoice_type do
            :poland -> "SPRZEDAWCA"
            :foreign -> "SPRZEDAWCA / SELLER"
          end}
        </h2>
        <div class="grid grid-cols-[auto,_1fr] gap-1">
          <span>
            {case @sales_invoice.invoice_type do
              :poland -> "Nazwa:"
              :foreign -> "Nazwa / Name:"
            end}
          </span>
          <span class="font-bold">
            {@sales_invoice.seller_display_name}
          </span>

          <span>
            {case @sales_invoice.invoice_type do
              :poland -> "Adres:"
              :foreign -> "Adres / Address:"
            end}
          </span>
          <span>{@sales_invoice.seller_address}</span>

          <span>
            {case @sales_invoice.invoice_type do
              :poland -> "NIP:"
              :foreign -> "VAT-ID:"
            end}
          </span>
          <span>{@sales_invoice.seller_nip}</span>
        </div>
      </div>
      <div>
        <h2 class=" text-darkGrey/70 text-[8px] font-bold mb-2">
          {case @sales_invoice.invoice_type do
            :poland -> "NABYWCA"
            :foreign -> "NABYWCA / BUYER"
          end}
        </h2>
        <div class="grid grid-cols-[auto,_1fr] gap-1">
          <span>
            {case @sales_invoice.invoice_type do
              :poland -> "Nazwa:"
              :foreign -> "Nazwa / Name:"
            end}
          </span>
          <span class="font-bold ">
            {@sales_invoice.buyer_display_name}
          </span>

          <%= if @sales_invoice.buyer_name && @sales_invoice.buyer_surname do %>
            <span>
              {case @sales_invoice.invoice_type do
                :poland -> "Imię i nazwisko:"
                :foreign -> "Name and surname:"
              end}
            </span>
            <span>{@sales_invoice.buyer_name} {@sales_invoice.buyer_surname}</span>
          <% end %>

          <span>
            {case @sales_invoice.invoice_type do
              :poland -> "Adres:"
              :foreign -> "Adres / Address:"
            end}
          </span>
          {}
          <span>
            {case @sales_invoice.buyer_address do
              nil -> ""
              address -> address
            end}
          </span>

          <span>
            {case @sales_invoice.invoice_type do
              :poland -> "NIP:"
              :foreign -> "VAT-ID:"
            end}
          </span>
          <span class="text-[10px]">{@sales_invoice.buyer_nip}</span>
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
      <h2 class="text-[8px] text-darkGrey text-opacity-70 font-bold">
        {case @sales_invoice.invoice_type do
          :poland -> "TOWARY LUB USŁUGI"
          :foreign -> "TOWARY LUB USŁUGI / GOODS OR SERVICES"
        end}
      </h2>
      <table class="w-full mt-1">
        <thead class="text-[8px] text-darkGrey/70">
          <%= if @sales_invoice.invoice_type == :poland  do %>
            <tr class="py-2">
              <th class="text-left">Lp.</th>
              <th class="text-left">Nazwa</th>
              <th class="text-right">Ilość</th>
              <th class="text-right">J. m.</th>
              <%= if @show_vat do %>
                <th class="text-right">Cena netto</th>
                <th class="text-center w-12 pl-5">Vat</th>
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
              <td class="py-1 max-w-40">{item.name}</td>
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
                <td :if={@show_vat} class="py-1 text-right">{item.vat_rate}%</td>
                <td class="py-1 text-right">
                  {Money.new(
                    @sales_invoice.currency,
                    item |> Firmowid.SalesInvoices.SalesInvoiceItem.get_net_value(),
                    currency_symbol: ""
                  )}
                </td>
                <td :if={@show_vat} class="py-1 text-right">
                  {Money.new(
                    @sales_invoice.currency,
                    item |> Firmowid.SalesInvoices.SalesInvoiceItem.get_gross_value(),
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
                    item |> Firmowid.SalesInvoices.SalesInvoiceItem.get_net_value()
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

  defp summary(assigns) do
    ~H"""
    <div class="bg-greyButtonBg/30 text-[10px]  gap-2 flex flex-col w-[347px] rounded-md px-4 py-2 mt-6 ml-auto">
      <h2 class=" text-[8px] text-darkGrey/70 font-bold uppercase">
        {case @sales_invoice.invoice_type do
          :poland -> "Podsumowanie"
          :foreign -> "Podsumowanie / Summary"
        end}
      </h2>

      <%= if @sales_invoice.invoice_type == :poland do %>
        <div class="flex justify-between items-center">
          <span>Wartość{if @show_vat, do: " netto"}:</span>
          <span>
            {Money.new(
              @sales_invoice.currency,
              @sales_invoice |> Firmowid.SalesInvoices.SalesInvoice.get_net_value()
            )}
          </span>
        </div>
        <%= if @show_vat do %>
          <div class="flex justify-between items-center">
            <span>Wartość całkowita VAT:</span>
            <span>
              {Money.new(
                @sales_invoice.currency,
                @sales_invoice |> Firmowid.SalesInvoices.SalesInvoice.get_vat_value()
              )}
            </span>
          </div>
          <div class="flex justify-between items-center">
            <span>Razem do zapłaty:</span>
            <span class="font-bold leading-tight text-sm">
              {Money.new(
                @sales_invoice.currency,
                @sales_invoice |> Firmowid.SalesInvoices.SalesInvoice.get_gross_value()
              )}
            </span>
          </div>
        <% end %>
      <% end %>
      <%= if @sales_invoice.invoice_type == :foreign do %>
        <div class="flex justify-between items-center">
          <span>Wartość całkowita VAT / Total VAT:</span>
          <span>
            nie dotyczy / not applicable
          </span>
        </div>
        <div class="flex font-bold justify-between items-center">
          <span>Razem do zapłaty / Total:</span>
          <span class="leading-snug text-sm">
            {Money.new!(
              @sales_invoice.currency,
              @sales_invoice |> Firmowid.SalesInvoices.SalesInvoice.get_net_value()
            )}
          </span>
        </div>
      <% end %>
    </div>
    """
  end

  attr :sales_invoice, :map, required: true

  defp payment_details(assigns) do
    ~H"""
    <h2 class="text-[8px] text-darkGrey text-opacity-70 font-bold mb-2 uppercase">
      {case @sales_invoice.invoice_type do
        :poland -> "Płatność"
        :foreign -> "Płatność / payment"
      end}
    </h2>
    <div class="flex flex-col w-fit text-[10px] gap-1 leading-[14px]">
      <%= if @sales_invoice.invoice_type == :poland do %>
        <div>
          Metoda płatności: {@sales_invoice.payment_method} | nr konta: {@sales_invoice.seller_account_number}
        </div>
      <% end %>
      <%= if @sales_invoice.invoice_type == :foreign do %>
        <div>
          Metoda płatności / Payment method: {@sales_invoice.payment_method}
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
    </div>
    """
  end

  defp footer(assigns) do
    ~H"""
    <div class="absolute flex items-end inset-x-0 justify-center text-[8px] bottom-4 w-full">
      <div class="flex flex-col items-center">
        <img src="/images/invoice_firmowid_logo.png" class="w-10 h-10 mb-2" />
        <p>
          Faktura wygenerowana za pomocą
          <a class="font-black" href="https://firmowid.pl" target="_blank" rel="noreferrer noopener">
            Firmowid.pl
          </a>
        </p>
      </div>
    </div>
    """
  end

  attr :sales_invoice, :map, required: true
  attr :show_vat, :boolean, default: true

  def sales_invoice(assigns) do
    ~H"""
    <div class="w-[calc(595px-2*32px)] h-[calc(842px-2*32px)] relative p-8 box-content mx-auto bg-white">
      <.invoice_header sales_invoice={@sales_invoice} show_vat={@show_vat} />
      <hr class="border-greyButtonBg my-6" />
      <.seller_buyer_section sales_invoice={@sales_invoice} />
      <hr class="border-greyButtonBg my-6" />
      <.items_table sales_invoice={@sales_invoice} show_vat={@show_vat} />
      <.summary sales_invoice={@sales_invoice} show_vat={@show_vat} />
      <hr class="border-greyButtonBg my-6" />
      <%= if @sales_invoice.currency != "PLN" do %>
        <div class="mb-6">
          <h2 class="text-[8px] text-darkGrey text-opacity-70 font-bold mb-2 uppercase">
            {case @sales_invoice.invoice_type do
              :poland -> "Przewalutowanie"
              :foreign -> "Przewalutowanie / Currency conversion"
            end}
          </h2>
          <div>
            <div class="text-[10px] leading-[14px]">
              Kurs {@sales_invoice.currency} / {@sales_invoice.currency} exchange rate: {@currency_rate.rate
              |> Firmowid.Cldr.Number.to_string!(format: "#0.0000 ¤¤", currency: "PLN")}
            </div>
            <div class="text-[8px] mt-1">
              Kurs waluty wg. tabeli kursów średnich nr {@currency_rate.table_number} z dnia {@currency_rate.effective_date}
              <br />
              Exchange rate according to average exchange rate table No. {@currency_rate.table_number} of {@currency_rate.effective_date}
            </div>
          </div>
        </div>
      <% end %>
      <!-- Payment Details -->
      <.payment_details sales_invoice={@sales_invoice} />
      <!-- Footer -->
      <.footer />
    </div>
    """
  end
end
