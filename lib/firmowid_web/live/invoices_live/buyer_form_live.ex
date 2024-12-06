defmodule FirmowidWeb.InvoicesLive.BuyerFormLive do
  require Logger
  use FirmowidWeb, :live_view

  attr :buyer_form, :list, required: true

  def(render(assigns)) do
    ~H"""
    <div class="max-w-2xl">
      <p class="text-darkGrey mb-4">Nabywca</p>
      <.form
        phx-submit="submit"
        for={@buyer_form}
        class="bg-greyButtonBg bg-opacity-50 p-4 px-6 rounded-md"
      >
        <div class="flex gap-2">
          <div>
            <.input field={@buyer_form[:buyer_nip]} type="text" placeholder="Nip sprzedawcy" required />
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
            <p class="text-sm text-darkGrey mt-5">Dane adresowe</p>
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
        <.button class="bg-blueText font-bold py-2 px-4 rounded mt-2">Zatwierdź</.button>
      </.form>
    </div>
    """
  end
end
