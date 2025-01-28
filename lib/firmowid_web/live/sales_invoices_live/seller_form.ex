defmodule FirmowidWeb.SalesInvoicesLive.SellerForm do
  require Logger
  import FirmowidWeb.SalesInvoicesLive.EditButton

  use FirmowidWeb, :html

  attr :seller_form, :list, required: true
  attr :sales_invoice, :map, required: true
  attr :sellers, :list, required: false, default: []
  attr :is_seller_dirty, :boolean, required: false, default: false

  def seller_form(assigns) do
    ~H"""
    <div class="w-full max-w-screen-lg">
      <p class="text-darkGrey mb-4">Sprzedający</p>

      <.form phx-change="submit" for={@seller_form}>
        <.input
          type="hidden"
          field={@seller_form[:is_seller_confirmed]}
          value={
            if !@sales_invoice.seller_id or @sales_invoice.seller_id == "" do
              "true"
            else
              "false"
            end
          }
        />
        <.input
          field={@seller_form[:seller_id]}
          type="select"
          class="bg-greyButtonBg text-darkGrey rounded-md border-none text-sm h-7 py-0 w-auto max-w-80 mb-2"
          prompt="WYBIERZ Z LISTY"
          options={@sellers |> Enum.map(fn s -> {s.display_name, s.id} end)}
        />
      </.form>
      <%= if @sales_invoice.is_seller_confirmed do %>
        <div class="w-full flex justify-between items-start text-sm border border-greyButtonBg rounded-md p-5">
          <div class="grid grid-cols-[auto,1fr] gap-x-4 gap-y-2">
            <span class="text-darkGrey">NIP</span>
            <span>{@sales_invoice.seller_nip}</span>
            <span class="text-darkGrey">Nazwa firmy</span>
            <span>{@sales_invoice.seller_display_name}</span>
            <%= if !!@sales_invoice.seller_name or !!@sales_invoice.seller_surname do %>
              <span class="text-darkGrey">Imię i nazwisko</span>
              <span>{@sales_invoice.seller_name} {@sales_invoice.seller_surname}</span>
            <% end %>
            <span class="text-darkGrey">Adres </span>
            <span>{@sales_invoice.seller_address}</span>
            <span class="text-darkGrey">Nr konta </span>
            <span>{@sales_invoice.seller_account_number}</span>
          </div>
          <.edit_button phx-click={
            JS.push("submit", value: %{"sales_invoice" => %{"is_seller_confirmed" => false}})
          } />
        </div>
      <% else %>
        <.form phx-submit="submit" id="seller_form" phx-change="change" for={@seller_form}>
          <div class="bg-greyButtonBg bg-opacity-50 p-4 px-6 rounded-md">
            <div class="flex gap-2 items-end">
              <div class="flex flex-col w-1/2">
                <p class="text-sm text-darkGrey">NIP</p>
                <.input
                  field={@seller_form[:seller_nip]}
                  type="text"
                  placeholder="Nip sprzedawcy"
                  required
                />
                <p class="text-sm text-darkGrey mt-5">Dane podstawowe</p>
                <.input
                  field={@seller_form[:seller_display_name]}
                  type="text"
                  placeholder="Nazwa firmy"
                  required
                />
                <div class="flex gap-2">
                  <.input field={@seller_form[:seller_name]} type="text" placeholder="Imię" />
                  <.input field={@seller_form[:seller_surname]} type="text" placeholder="Nazwisko" />
                </div>
              </div>
              <div class="flex flex-col w-1/2">
                <div>
                  <p class="text-sm text-darkGrey">Dane adresowe</p>
                  <.input
                    field={@seller_form[:seller_address]}
                    type="text"
                    placeholder="Adres"
                    required
                  />
                </div>
                <p class="text-sm text-darkGrey mt-5">Numer konta</p>
                <.input field={@seller_form[:seller_account_number]} type="text" required />
              </div>
            </div>
            <div class="flex flex-row-reverse justify-start gap-2">
              <.button
                phx-disable-with="Zapisywanie..."
                name={@seller_form[:is_seller_confirmed].name}
                value="true"
                color="green"
                class="mt-2"
                id="seller_confirm_button"
              >
                Zatwierdź
              </.button>
              <%= if !@sales_invoice.seller_id or @sales_invoice.seller_id == "" do %>
                <.button
                  phx-disable-with="Dodawanie..."
                  variant="outline"
                  name="action"
                  value="add_or_update_seller"
                  color="green"
                  class="mt-2"
                >
                  Dodaj
                </.button>
              <% else %>
                <.button
                  phx-disable-with="Aktualizowanie..."
                  variant="outline"
                  name="action"
                  value="add_or_update_seller"
                  color="green"
                  class="mt-2"
                  disabled={not @is_seller_dirty}
                >
                  Aktualizuj
                </.button>
              <% end %>
            </div>
          </div>
        </.form>
      <% end %>
    </div>
    """
  end
end
