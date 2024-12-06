defmodule FirmowidWeb.InvoicesLive.SellerFormLive do
  require Logger
  use FirmowidWeb, :live_view

  attr :seller_form, :list, required: true

  def(render(assigns)) do
    ~H"""
    <div class="max-w-2xl">
      <p class="text-darkGrey mb-4">Sprzedawca</p>
      <.form
        phx-submit="submit"
        for={@seller_form}
        class="bg-greyButtonBg bg-opacity-50 p-4 px-6 rounded-md"
      >
        <div class="flex flex-col gap-2">
          <div>
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
          <div>
            <p class="text-sm text-darkGrey mt-2">Dane adresowe</p>
            <.input field={@seller_form[:seller_address]} type="text" placeholder="Adres" required />
          </div>
        </div>
        <p class="text-sm text-darkGrey mt-2">Numer konta</p>
        <.input field={@seller_form[:seller_account_number]} type="text" required />
        <.button class="bg-blueText font-bold py-2 px-4 rounded mt-2">Zatwierdź</.button>
      </.form>
    </div>
    """
  end
end
