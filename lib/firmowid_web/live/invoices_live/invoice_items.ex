defmodule FirmowidWeb.InvoicesLive.InvoiceItems do
  use FirmowidWeb, :live_view

  import FirmowidWeb.InvoicesLive.EditButton
  import FirmowidWeb.Icons

  attr :form, :list, required: true
  attr :invoice, :map, required: true

  def invoice_items(assigns) do
    ~H"""
    <.form phx-submit="submit" phx-change="change" for={@form}>
      <div class="flex justify-between">
        <p class="text-darkGrey mb-4">
          Pozycje na fakturze
        </p>
        <%= if !@invoice.are_invoice_items_confirmed do %>
          <.button
            type="button"
            name="invoice[items_sort][]"
            value="true"
            phx-click={JS.dispatch("change")}
            class="bg-greyButtonBg size-8 !p-0"
          >
            <.icon name="hero-plus" class="text-darkGrey h-4 w-4" />
          </.button>
        <% end %>
      </div>
      <%= if @invoice.are_invoice_items_confirmed do %>
        <div class="border flex justify-between items-start border-greyButtonBg rounded-md p-5">
          <table class="w-full">
            <tr class="text-darkGrey  font-normal">
              <th class="text-left max-w-lg font-normal">
                Nazwa towaru/usługi
              </th>
              <th class="pr-2 pb-1  text-left font-normal">
                Ilość
              </th>
              <th class="pr-2 pb-1 text-left font-normal">
                Jednostka
              </th>
              <th class="pr-2  pb-1 text-left font-normal">
                Cena netto
              </th>
              <th class="pr-2 pb-1 text-left font-normal">
                VAT %
              </th>
              <%= if  @invoice.invoice_type == :poland do %>
                <th class="pr-2 pb-1 text-left font-normal">
                  Wartość netto
                </th>
                <th class="pr-2 pb-1 text-left font-normal">
                  Wartość brutto
                </th>
              <% end %>
              <%= if @invoice.invoice_type == :foreign do %>
                <th class="pr-2 pb-1 text-left font-normal">
                  Wartość
                </th>
              <% end %>
            </tr>
            <%= for item <- @invoice.invoice_items do %>
              <tr class="pt-3">
                <td class="pt-3">
                  {item.name}
                </td>
                <td>
                  {item.quantity}
                </td>
                <td>
                  {item.unit}
                </td>
                <td>
                  {item.unit_price}
                </td>
                <td>
                  <%= if  @invoice.invoice_type == :poland do %>
                    {item.vat_rate}%
                  <% end %>
                  <%= if @invoice.invoice_type == :foreign do %>
                    np.
                  <% end %>
                </td>
                <%= if  @invoice.invoice_type == :poland do %>
                  <td>
                    {Money.new(
                      :PLN,
                      Decimal.mult(item.quantity, item.unit_price)
                    )
                    |> Money.to_string!(currency_symbol: "")}
                  </td>
                  <td>
                    {Money.new(
                      :PLN,
                      Decimal.mult(item.quantity, item.unit_price)
                      |> Decimal.mult(
                        item.vat_rate
                        |> Decimal.div(100)
                        |> Decimal.add(1)
                      )
                    )
                    |> Money.to_string!(currency_symbol: "")}
                  </td>
                <% end %>
                <%= if @invoice.invoice_type == :foreign do %>
                  <td>
                    {Money.new(
                      @invoice.currency,
                      Decimal.mult(item.quantity, item.unit_price)
                    )
                    |> Money.to_string!(currency_symbol: "")}
                  </td>
                <% end %>
              </tr>
            <% end %>
          </table>
          <.edit_button phx-click={
            JS.push("submit", value: %{"invoice" => %{"are_invoice_items_confirmed" => false}})
          } />
        </div>
      <% else %>
        <div class="bg-greyButtonBg bg-opacity-50 p-4 rounded-md">
          <div class="grid grid-cols-[repeat(13,_1fr)] gap-4">
            <div class="col-span-2 text-darkGrey">
              Nazwa towaru/usługi
            </div>
            <div class="col-span-1 text-darkGrey">
              Ilość
            </div>
            <div class="col-span-2 text-darkGrey">
              Jednostka
            </div>
            <div class="col-span-2 text-darkGrey">
              Cena netto
            </div>
            <div class="col-span-1 text-darkGrey">
              VAT %
            </div>
            <%= if  @invoice.invoice_type == :poland do %>
              <div class="col-span-2 text-darkGrey">
                Wartość netto
              </div>
              <div class="col-span-2 text-darkGrey">
                Wartość brutto
              </div>
            <% end %>
            <%= if @invoice.invoice_type == :foreign do %>
              <div class="col-span-4 text-darkGrey">
                Wartość
              </div>
            <% end %>

            <.inputs_for :let={item} field={@form[:invoice_items]}>
              <input type="hidden" name="invoice[items_sort][]" value={item.index} />
              <div class="col-span-2">
                <.input field={item[:name]} type="text" required />
              </div>
              <div class="col-span-1">
                <.input field={item[:quantity]} type="number" required />
              </div>
              <div class="col-span-2">
                <.input field={item[:unit]} type="text" required />
              </div>
              <div class="col-span-2">
                <.input field={item[:unit_price]} type="number" required />
              </div>
              <div class="col-span-1">
                <%= if  @invoice.invoice_type == :poland do %>
                  <.input field={item[:vat_rate]} type="number" required />
                <% end %>
                <%= if @invoice.invoice_type == :foreign do %>
                  <.input name={item[:vat_rate].name} type="text" disabled readonly value="np." />
                <% end %>
              </div>
              <%= if  @invoice.invoice_type == :poland do %>
                <div class="col-span-2">
                  <.input
                    type="text"
                    name={"net_value_#{item.index}"}
                    readonly
                    value={
                      Money.new(
                        :PLN,
                        Decimal.mult(item[:quantity].value, item[:unit_price].value)
                      )
                      |> Money.to_string!(currency_symbol: "")
                    }
                  />
                </div>
                <div class="col-span-2">
                  <.input
                    type="text"
                    name={"gross_value_#{item.index}"}
                    readonly
                    value={
                      Money.new(
                        :PLN,
                        Decimal.mult(item[:quantity].value, item[:unit_price].value)
                        |> Decimal.mult(
                          item[:vat_rate].value
                          |> Decimal.div(100)
                          |> Decimal.add(1)
                        )
                      )
                      |> Money.to_string!(currency_symbol: "")
                    }
                  />
                </div>
              <% end %>
              <%= if @invoice.invoice_type == :foreign do %>
                <div class="col-span-4">
                  <.input
                    type="text"
                    class="max-w-56"
                    name={"gross_value_#{item.index}"}
                    readonly
                    value={
                      Money.new(
                        @invoice.currency,
                        Decimal.mult(item[:quantity].value, item[:unit_price].value)
                      )
                      |> Money.to_string!(currency_symbol: "")
                    }
                  />
                </div>
              <% end %>
              <.button
                type="button"
                name="invoice[items_drop][]"
                value={item.index}
                phx-click={JS.dispatch("change")}
                class="col-span-1 h-7 w-9 bg-redBg self-center flex justify-center items-center !text-redText hover:border border-none hover:!bg-darkGrey/50 size-8 ml-5 mt-2 hover:!text-greyButtonBg !p-0"
              >
                <.trash_icon class="w-4 h-4" />
              </.button>
            </.inputs_for>
          </div>
          <input type="hidden" name="invoice[items_drop][]" />
          <div class="flex justify-between mt-6">
            <.button
              type="button"
              name="invoice[items_sort][]"
              value="true"
              phx-click={JS.dispatch("change")}
              class="border-greyButtonBg border h-8 flex items-center gap-1 hover:bg-greyButtonBg !text-darkGrey text-sm bg-lightGreyBg font-medium uppercase !px-2 !py-1"
            >
              Dodaj pozycję <.icon name="hero-plus" class="text-darkGrey h-4 w-4" />
            </.button>
            <.input type="hidden" field={@form[:are_invoice_items_confirmed]} value="true" />
            <.button phx-disable-with="Zapisywanie..." type="submit" color="green">
              Zatwierdź
            </.button>
          </div>
        </div>
      <% end %>
    </.form>
    """
  end
end
