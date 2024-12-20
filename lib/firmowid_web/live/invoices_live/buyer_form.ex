defmodule FirmowidWeb.InvoicesLive.BuyerForm do
  require Logger
  import FirmowidWeb.InvoicesLive.EditButton
  use FirmowidWeb, :html

  attr :buyer_form, :list, required: true

  defp different_mail_address(assigns) do
    ~H"""
    <div>
      <.input field={@buyer_form[:buyer_mail_street]} type="text" placeholder="Ulica" required />
      <div class="flex gap-2">
        <.input
          field={@buyer_form[:buyer_mail_postal_code]}
          type="text"
          class="flex-1"
          placeholder="Kod pocztowy"
          required
        />
        <.input
          field={@buyer_form[:buyer_mail_city]}
          type="text"
          class="flex-1"
          placeholder="Miejscowość"
          required
        />
      </div>
      <.input field={@buyer_form[:buyer_mail_country]} type="text" placeholder="Kraj" required />
    </div>
    """
  end

  attr :buyer_form, :list, required: true
  attr :invoice, :map, required: true
  attr :buyers, :list, required: false, default: []
  attr :is_buyer_dirty, :boolean, required: false, default: false

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
          options={
            @buyers |> Enum.map(fn buyer -> {Firmowid.Invoices.Buyer.get_name(buyer), buyer.id} end)
          }
        />
      </.form>
      <%= if @invoice.is_buyer_confirmed do %>
        <div class="w-[664px] flex justify-between items-start border border-greyButtonBg rounded-md p-5">
          <div class="grid grid-cols-[auto,1fr] gap-x-4 gap-y-2">
            <%= if @invoice.buyer_type == :company do %>
              <span class="text-darkGrey">NIP</span>
              <span>{@invoice.buyer_nip}</span>
              <span class="text-darkGrey">Nazwa firmy</span>
              <span>{@invoice.buyer_display_name}</span>
            <% end %>
            <%= if !!@invoice.buyer_name or !!@invoice.buyer_surname do %>
              <span class="text-darkGrey">Imię i nazwisko</span>
              <span>{@invoice.buyer_name} {@invoice.buyer_surname}</span>
            <% end %>
            <%= if !!@invoice.buyer_pesel and @invoice.buyer_type == :individual do %>
              <span class="text-darkGrey">PESEL</span>
              <span>{@invoice.buyer_pesel}</span>
            <% end %>
            <span class="text-darkGrey">Adres </span>
            <span>{Firmowid.Invoices.Invoice.get_address_lines(@invoice)}</span>
          </div>

          <.edit_button phx-click={
            JS.push("submit", value: %{"invoice" => %{"is_buyer_confirmed" => false}})
          } />
        </div>
      <% else %>
        <.form phx-submit="submit" class="flex flex-col gap-2" phx-change="change" for={@buyer_form}>
          <div class="bg-greyButtonBg/50 px-5 h-[50px] flex items-center  rounded-md">
            <.radio_group class="gap-8" field={@buyer_form[:buyer_type]}>
              <:radio value="company">Firma/ Jednoosobowa Działalność Gospodarcza</:radio>
              <:radio value="individual">Osoba prywatna</:radio>
            </.radio_group>
          </div>
          <div class="bg-greyButtonBg/50 py-4 px-5 rounded-md">
            <div class="flex gap-2">
              <div>
                <.input
                  :if={to_string(@buyer_form[:buyer_type].value) == "company"}
                  field={@buyer_form[:buyer_nip]}
                  type="text"
                  input_class="mt-0 mb-5"
                  placeholder="Nip klienta"
                  required
                />
                <p class="text-sm text-darkGrey">Dane podstawowe</p>
                <.input
                  :if={to_string(@buyer_form[:buyer_type].value) == "company"}
                  field={@buyer_form[:buyer_display_name]}
                  type="text"
                  required
                  placeholder="Nazwa firmy"
                />
                <div class="flex gap-2">
                  <.input
                    field={@buyer_form[:buyer_name]}
                    type="text"
                    placeholder="Imię"
                    required={to_string(@buyer_form[:buyer_type].value) == "individual"}
                  />
                  <.input
                    field={@buyer_form[:buyer_surname]}
                    type="text"
                    placeholder="Nazwisko"
                    required={to_string(@buyer_form[:buyer_type].value) == "individual"}
                  />
                </div>
                <.input
                  :if={to_string(@buyer_form[:buyer_type].value) == "individual"}
                  field={@buyer_form[:buyer_pesel]}
                  type="text"
                  placeholder="PESEL (opcjonalnie)"
                />
              </div>
              <div class={to_string(@buyer_form[:buyer_type].value) == "company" && "mt-3"}>
                <p class="text-sm text-darkGrey">Dane adresowe</p>
                <.input field={@buyer_form[:buyer_street]} type="text" placeholder="Adres" required />
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
            <div
              class="accordion-panel grid grid-rows-[0fr] data-[expanded]:grid-rows-[1fr] transition-all transform ease-in duration-200"
              id="seller-form-panel"
              role="region"
            >
              <div class="overflow-hidden">
                <.input
                  type="checkbox"
                  field={@buyer_form[:buyer_is_different_mail_address]}
                  class="text-darkGrey font-normal mt-2"
                  label="Inny adres korespondencyjny"
                />
                <.different_mail_address
                  :if={to_string(@buyer_form[:buyer_is_different_mail_address].value) == "true"}
                  buyer_form={@buyer_form}
                />
                <p class="text-sm text-darkGrey mt-2">Dodatkowe informacje</p>
                <div class="flex gap-2 items-end">
                  <.input
                    class="flex-1"
                    field={@buyer_form[:buyer_email]}
                    type="email"
                    placeholder="E-mail"
                  />
                  <.input
                    class="flex-1"
                    field={@buyer_form[:buyer_phone]}
                    type="tel"
                    placeholder="Telefon"
                  />
                </div>
                <.input field={@buyer_form[:buyer_description]} type="textarea" placeholder="Opis" />
              </div>
            </div>
            <div class="flex justify-between items-center">
              <h3>
                <button
                  aria-controls="seller-form-panel"
                  class={[
                    "accordion-trigger text-blueText flex gap-2 items-center justify-center [&_.accordion-trigger-icon]:aria-expanded:rotate-180"
                  ]}
                  id="seller-form-trigger"
                  phx-click={handle_open()}
                  type="button"
                >
                  więcej
                  <.icon
                    class="accordion-trigger-icon h-5 w-5 mt-1 transition-all ease-in-out duration-300"
                    name="hero-chevron-down"
                  />
                </button>
              </h3>
              <div class="flex flex-row-reverse justify-start gap-2 h-fit">
                <.button
                  name={@buyer_form[:is_buyer_confirmed].name}
                  value="true"
                  phx-disable-with="Zapisywanie..."
                  color="green"
                  class="mt-2"
                >
                  Zatwierdź
                </.button>
                <%= if !@invoice.buyer_id or @invoice.buyer_id == "" do %>
                  <.button
                    phx-disable-with="Dodawanie..."
                    name="action"
                    value="add_or_update_buyer"
                    variant="outline"
                    color="green"
                    class="mt-2"
                  >
                    Dodaj
                  </.button>
                <% else %>
                  <.button
                    phx-disable-with="Aktualizowanie..."
                    name="action"
                    value="add_or_update_buyer"
                    variant="outline"
                    color="green"
                    class="mt-2"
                    disabled={not @is_buyer_dirty}
                  >
                    Zaktualizuj
                  </.button>
                <% end %>
              </div>
            </div>
          </div>
        </.form>
      <% end %>
    </div>
    """
  end

  defp handle_open() do
    {"aria-expanded", "true", "false"}
    |> JS.toggle_attribute(to: "#seller-form-trigger")
    |> JS.toggle_attribute({"data-expanded", ""}, to: "#seller-form-panel")
  end
end
