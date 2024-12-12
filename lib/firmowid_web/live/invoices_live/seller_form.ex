defmodule FirmowidWeb.InvoicesLive.SellerForm do
  require Logger
  import FirmowidWeb.InvoicesLive.EditButton
  use FirmowidWeb, :html

  attr :seller_form, :list, required: true
  attr :invoice, :map, required: true

  def seller_form(assigns) do
    ~H"""
    <div class="max-w-2xl">
      <p class="text-darkGrey mb-4">Sprzedający</p>
      <%= if @invoice.is_seller_confirmed do %>
        <div class="w-[571px] flex justify-between items-start border border-greyButtonBg rounded-md p-5">
          <div class="grid grid-cols-[auto,1fr] gap-x-4 gap-y-2">
            <span class="text-darkGrey">NIP</span>
            <span><%= @invoice.seller_nip %></span>
            <span class="text-darkGrey">Nazwa firmy</span>
            <span><%= @invoice.seller_display_name %></span>
            <span class="text-darkGrey">Imię i nazwisko</span>
            <span><%= @invoice.seller_name %> <%= @invoice.seller_surname %></span>
            <span class="text-darkGrey">Adres </span>
            <span><%= @invoice.seller_address %></span>
            <span class="text-darkGrey">Nr konta </span>
            <span><%= @invoice.seller_account_number %></span>
          </div>
          <.edit_button phx-click={
            JS.push("submit", value: %{"invoice" => %{"is_seller_confirmed" => false}})
          } />
        </div>
      <% else %>
        <.form
          phx-submit="submit"
          for={@seller_form}
          class="bg-greyButtonBg bg-opacity-50 p-4 px-6 rounded-md"
        >
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
          <.input
            type="hidden"
            class="hidden"
            field={@seller_form[:is_seller_confirmed]}
            value="true"
          />
          <.button
            phx-disable-with="Zapisywanie..."
            class="bg-blueText font-bold py-2 px-4 rounded mt-2"
          >
            Zatwierdź
          </.button>
        </.form>
      <% end %>
    </div>
    """
  end
end
