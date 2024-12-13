defmodule FirmowidWeb.InvoicesLive.BuyerForm do
  require Logger
  import FirmowidWeb.InvoicesLive.EditButton
  use FirmowidWeb, :html

  attr :buyer_form, :list, required: true
  attr :invoice, :map, required: true
  attr :buyers, :list, required: false, default: []

  def buyer_form(assigns) do
    ~H"""
    <div class="max-w-2xl">
      <p class="text-darkGrey mb-4">Nabywca</p>
      <.form phx-change="submit" for={@buyer_form}>
        <.input
          type="hidden"
          field={@buyer_form[:is_buyer_confirmed]}
          value={
            if !@invoice.buyer_id or @invoice.buyer_id == "" do
              "true"
            else
              "false"
            end
          }
        />
        <.input
          field={@buyer_form[:buyer_id]}
          type="select"
          class="bg-greyButtonBg text-darkGrey rounded-md border-none text-sm h-6 py-0 w-48 mb-2"
          prompt="WYBIERZ Z LISTY"
          options={@buyers |> Enum.map(fn s -> {s.display_name, s.id} end)}
        />
      </.form>
      <%= if @invoice.is_buyer_confirmed do %>
        <div class="w-[664px] flex justify-between items-start border border-greyButtonBg rounded-md p-5">
          <div class="grid grid-cols-[auto,1fr] gap-x-4 gap-y-2">
            <span class="text-darkGrey">NIP</span>
            <span>{@invoice.buyer_nip}</span>
            <span class="text-darkGrey">Nazwa firmy</span>
            <span>{@invoice.buyer_display_name}</span>
            <span class="text-darkGrey">Imię i nazwisko</span>
            <span>{@invoice.buyer_name} {@invoice.buyer_surname}</span>
            <span class="text-darkGrey">Adres </span>
            <span>{Firmowid.Invoices.Invoice.get_address_lines(@invoice)}</span>
          </div>

          <.edit_button phx-click={
            JS.push("submit", value: %{"invoice" => %{"is_buyer_confirmed" => false}})
          } />
        </div>
      <% else %>
        <.form
          phx-submit="submit"
          phx-change="change"
          for={@buyer_form}
          class="bg-greyButtonBg bg-opacity-50 p-4 px-6 rounded-md"
        >
          <div class="flex items-end gap-2">
            <div>
              <p class="text-sm text-darkGrey">NIP</p>
              <.input
                field={@buyer_form[:buyer_nip]}
                type="text"
                placeholder="Nip sprzedawcy"
                required
              />
              <p class="text-sm text-darkGrey mt-5">Dane podstawowe</p>
              <.input
                field={@buyer_form[:buyer_display_name]}
                type="text"
                placeholder="Nazwa firmy"
                required
              />
              <div class="flex gap-2">
                <.input field={@buyer_form[:buyer_name]} type="text" placeholder="Imię" />
                <.input field={@buyer_form[:buyer_surname]} type="text" placeholder="Nazwisko" />
              </div>
            </div>
            <div>
              <p class="text-sm text-darkGrey">Dane adresowe</p>
              <div class="flex gap-2 items-center">
                <.input field={@buyer_form[:buyer_street]} type="text" placeholder="Ulica" required />
                <.input field={@buyer_form[:buyer_house_number]} class="w-12" type="text" />
                <p class="mt-2">/</p>
                <.input field={@buyer_form[:buyer_apartment_number]} class="w-12" type="text" />
              </div>
              <div class="flex gap-2">
                <.input
                  field={@buyer_form[:buyer_postal_code]}
                  type="text"
                  placeholder="Kod pocztowy"
                  required
                />
                <.input
                  field={@buyer_form[:buyer_city]}
                  type="text"
                  placeholder="Miejscowość"
                  required
                />
              </div>
              <.input field={@buyer_form[:buyer_country]} type="text" placeholder="Kraj" required />
            </div>
          </div>
          <.input type="hidden" class="hidden" field={@buyer_form[:is_buyer_confirmed]} value="true" />
          <.input type="hidden" class="hidden" field={@buyer_form[:is_buyer_confirmed]} value="true" />
          <div class="flex flex-row-reverse justify-start gap-2">
            <.button phx-disable-with="Zapisywanie..." color="green" class="mt-2">
              Zatwierdź
            </.button>
            <.button
              phx-disable-with="Dodawanie..."
              name="action"
              value="add_and_confirm_buyer"
              variant="outline"
              color="green"
              class="mt-2"
            >
              <%= if !@invoice.buyer_id or @invoice.buyer_id == "" do %>
                Dodaj i zatwierdź
              <% else %>
                Zaktualizuj i zatwierdź
              <% end %>
            </.button>
          </div>
        </.form>
      <% end %>
    </div>
    """
  end
end
