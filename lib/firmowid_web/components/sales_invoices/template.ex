defmodule FirmowidWeb.SalesInvoices.Template do
  @moduledoc false
  use FirmowidWeb, :html

  attr :sales_invoice, :map, required: true
  attr :show_vat, :boolean, default: true
  attr :logo_data_uri, :string, default: nil

  defp invoice_header(assigns) do
    ~H"""
    <div class="flex justify-between mt-1 text-[10px]">
      <div class="flex flex-col gap-x-2">
        <div class="text-sm uppercase font-bold">
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
                  ["Faktura korygująca / Correction Invoice:"]
              end
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
        <%= if @sales_invoice.ksef_invoice_kind == :kor do %>
          <div class="mt-1">
            <span>
              {case @sales_invoice.invoice_type do
                :poland -> "Faktura korygowana:"
                :foreign -> "Faktura korygowana / Corrected invoice:"
              end}
            </span>
            <span class="font-bold">{@sales_invoice.corrected_invoice.invoice_number}</span>
            <span class="text-darkGrey/70">
              {case @sales_invoice.invoice_type do
                :poland -> "z dnia"
                :foreign -> "z dnia / dated"
              end}
            </span>
            <span class="font-bold">
              {@sales_invoice.corrected_invoice.issue_date |> Calendar.strftime("%d.%m.%Y")}
            </span>
          </div>
        <% end %>
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
          <%= if @logo_data_uri do %>
            <img src={@logo_data_uri} class="w-8 h-8" />
          <% else %>
            <img :if={@sales_invoice.logo_url} src={@sales_invoice.logo_url} class="w-8 h-8" />
          <% end %>
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
        <div class="grid grid-cols-[auto_1fr] gap-1">
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
        <h2 class=" text-darkGrey/70 text-[8px] font-bold mb-2">
          {case @sales_invoice.invoice_type do
            :poland -> "NABYWCA"
            :foreign -> "NABYWCA / BUYER"
          end}
        </h2>
        <div class="grid grid-cols-[auto_1fr] gap-1">
          <%= if @sales_invoice.buyer_type == :company do %>
            <span>
              {case @sales_invoice.invoice_type do
                :poland -> "Nazwa:"
                :foreign -> "Nazwa / Name:"
              end}
            </span>
            <span class="font-bold ">
              {@sales_invoice.buyer_full_name}
            </span>
          <% end %>

          <%= if @sales_invoice.buyer_type == :individual do %>
            <span>
              {case @sales_invoice.invoice_type do
                :poland -> "Imię i nazwisko:"
                :foreign -> "Imię i nazwisko / Name and surname:"
              end}
            </span>
            <span>{@sales_invoice.buyer_given_name} {@sales_invoice.buyer_surname}</span>
          <% end %>

          <%= if @sales_invoice.buyer_address && @sales_invoice.buyer_address != "" do %>
            <span>
              {case @sales_invoice.invoice_type do
                :poland -> "Adres:"
                :foreign -> "Adres / Address:"
              end}
            </span>
            <span>{@sales_invoice.buyer_address}</span>
          <% end %>

          <%= if @sales_invoice.buyer_type == :individual and @sales_invoice.invoice_type == :poland do %>
            <span>PESEL:</span>
            <span class="text-[10px]">{@sales_invoice.buyer_pesel}</span>
          <% else %>
            <span>
              {case @sales_invoice.invoice_type do
                :poland -> "NIP:"
                :foreign -> "VAT-ID:"
              end}
            </span>
            <span class="text-[10px]">{@sales_invoice.buyer_id}</span>
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
      <h2 class="text-[8px] text-darkGrey/70 font-bold">
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
                <td :if={@show_vat} class="py-1 text-right">
                  {Firmowid.Ksef.VatRate.label(item.vat_rate)}
                </td>
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
  attr :items, :list, required: true
  attr :title, :string, required: true

  defp correction_items_section(assigns) do
    ~H"""
    <div class="mb-4">
      <h2 class="text-[8px] text-darkGrey/70 font-bold uppercase">
        {@title}
      </h2>
      <table class="w-full mt-1">
        <thead class="text-[8px] text-darkGrey/70">
          <%= if @sales_invoice.invoice_type == :poland do %>
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
          <%= for {item, index} <- Enum.with_index(@items, 1) do %>
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
                <td :if={@show_vat} class="py-1 text-right">
                  {Firmowid.Ksef.VatRate.label(item.vat_rate)}
                </td>
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
    <div>
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
  attr :show_vat, :boolean, default: true
  attr :reference_invoice, :map, required: true

  defp correction_summary(assigns) do
    alias Firmowid.SalesInvoices.SalesInvoice

    invoice = assigns.sales_invoice
    reference = assigns.reference_invoice
    currency = invoice.currency

    before_net = SalesInvoice.get_net_value(reference)
    before_vat = SalesInvoice.get_vat_value(reference)
    before_gross = SalesInvoice.get_gross_value(reference)

    after_net = SalesInvoice.get_net_value(invoice)
    after_vat = SalesInvoice.get_vat_value(invoice)
    after_gross = SalesInvoice.get_gross_value(invoice)

    delta_net = Decimal.sub(after_net, before_net)
    delta_vat = Decimal.sub(after_vat, before_vat)
    delta_gross = Decimal.sub(after_gross, before_gross)

    assigns =
      assigns
      |> assign(:currency, currency)
      |> assign(:before_net, before_net)
      |> assign(:before_vat, before_vat)
      |> assign(:before_gross, before_gross)
      |> assign(:after_net, after_net)
      |> assign(:after_vat, after_vat)
      |> assign(:after_gross, after_gross)
      |> assign(:delta_net, delta_net)
      |> assign(:delta_vat, delta_vat)
      |> assign(:delta_gross, delta_gross)

    ~H"""
    <div class="bg-greyButtonBg/30 text-[10px] rounded-md px-4 py-2 mt-6 ml-auto">
      <h2 class="text-[8px] text-darkGrey/70 font-bold uppercase mb-2">
        {case @sales_invoice.invoice_type do
          :poland -> "Podsumowanie korekty"
          :foreign -> "Podsumowanie korekty / Correction summary"
        end}
      </h2>

      <table class="w-full">
        <thead class="text-[8px] text-darkGrey/70">
          <%= if @sales_invoice.invoice_type == :poland do %>
            <tr>
              <th class="text-left"></th>
              <th class="text-right px-2">Przed</th>
              <th class="text-right px-2">Po</th>
              <th class="text-right">Różnica</th>
            </tr>
          <% else %>
            <tr>
              <th class="text-left"></th>
              <th class="text-right px-2">Przed / Before</th>
              <th class="text-right px-2">Po / After</th>
              <th class="text-right">Różnica / Diff</th>
            </tr>
          <% end %>
        </thead>
        <tbody>
          <tr>
            <td class="py-1">
              {if @sales_invoice.invoice_type == :poland,
                do: "Wartość#{if @show_vat, do: " netto"}:",
                else: "Wartość netto / Net value:"}
            </td>
            <td class="py-1 text-right px-2">{Money.new(@currency, @before_net)}</td>
            <td class="py-1 text-right px-2">{Money.new(@currency, @after_net)}</td>
            <td class="py-1 text-right font-medium">{Money.new(@currency, @delta_net)}</td>
          </tr>
          <%= if @show_vat do %>
            <tr>
              <td class="py-1">
                {if @sales_invoice.invoice_type == :poland,
                  do: "Całkowita wartość VAT:",
                  else: "Wartość całkowita VAT / Total VAT:"}
              </td>
              <td class="py-1 text-right px-2">{Money.new(@currency, @before_vat)}</td>
              <td class="py-1 text-right px-2">{Money.new(@currency, @after_vat)}</td>
              <td class="py-1 text-right font-medium">{Money.new(@currency, @delta_vat)}</td>
            </tr>
            <tr class="font-bold">
              <td class="py-1">
                {if @sales_invoice.invoice_type == :poland,
                  do: "Brutto:",
                  else: "Brutto / Gross:"}
              </td>
              <td class="py-1 text-right px-2">{Money.new(@currency, @before_gross)}</td>
              <td class="py-1 text-right px-2">{Money.new(@currency, @after_gross)}</td>
              <td class="py-1 text-right">{Money.new(@currency, @delta_gross)}</td>
            </tr>
          <% end %>
        </tbody>
      </table>
    </div>
    """
  end

  attr :sales_invoice, :map, required: true

  defp payment_details(assigns) do
    ~H"""
    <h2 class="text-[8px] text-darkGrey/70 font-bold mb-2 uppercase">
      {case @sales_invoice.invoice_type do
        :poland -> "Płatność"
        :foreign -> "Płatność / payment"
      end}
    </h2>
    <div class="flex flex-col w-fit text-[10px] gap-1 leading-[14px]">
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
    </div>
    """
  end

  attr :footer_logo_data_uri, :string, default: nil

  defp footer(assigns) do
    ~H"""
    <div class="absolute flex items-end inset-x-0 justify-center text-[8px] bottom-4 w-full">
      <div class="flex flex-col items-center">
        <%= if @footer_logo_data_uri do %>
          <img src={@footer_logo_data_uri} class="w-10 h-10 mb-2" />
        <% else %>
          <img src="/images/invoice_firmowid_logo.png" class="w-10 h-10 mb-2" />
        <% end %>
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
  attr :logo_data_uri, :string, default: nil
  attr :footer_logo_data_uri, :string, default: nil
  attr :reference_invoice, :map, default: nil

  def sales_invoice(assigns) do
    if assigns.sales_invoice.ksef_invoice_kind == :kor and is_nil(assigns.reference_invoice) do
      raise ArgumentError,
            "reference_invoice is required when rendering a correction invoice (ksef_invoice_kind: :kor)"
    end

    ~H"""
    <div class="w-[calc(595px-2*32px)] h-[calc(842px-2*32px)] relative p-8 box-content mx-auto bg-white">
      <.invoice_header
        sales_invoice={@sales_invoice}
        show_vat={@show_vat}
        logo_data_uri={@logo_data_uri}
      />
      <hr class="border-greyButtonBg my-6" />
      <.seller_buyer_section sales_invoice={@sales_invoice} />
      <hr class="border-greyButtonBg my-6" />
      <%= if @sales_invoice.ksef_invoice_kind == :kor do %>
        <%= if Firmowid.Ksef.InvoiceRenderer.invoice_items_changed?(
          @sales_invoice,
          @reference_invoice
        ) do %>
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
        <div class="mb-6">
          <h2 class="text-[8px] text-darkGrey/70 font-bold mb-2 uppercase">
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
      <.payment_details sales_invoice={@sales_invoice} />
      <.footer footer_logo_data_uri={@footer_logo_data_uri} />
    </div>
    """
  end
end
