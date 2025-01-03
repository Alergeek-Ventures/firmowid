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
  attr :nip_form, :list, required: true
  attr :invoice, :map, required: true
  attr :buyers, :list, required: false, default: []
  attr :is_buyer_dirty, :boolean, required: false, default: false
  attr :buyer_form_state, :atom, required: false

  def buyer_form(assigns) do
    ~H"""
    <div class="w-full max-w-screen-lg">
      <p class="text-darkGrey mb-2">Nabywca</p>
      <%= if @invoice.is_buyer_confirmed do %>
        <div class="flex gap-2 mt-4 mb-2">
          <div
            :if={@invoice.buyer_id}
            class="text-blueText border text-sm flex justify-center items-center font-medium px-2 h-7 border-blueText rounded-md"
          >
            WYBRANY Z BAZY
          </div>
          <div
            :if={!@invoice.buyer_id}
            class="text-blueText border text-sm flex justify-center items-center font-medium px-2 h-7 border-blueText rounded-md"
          >
            WPROWADZONY RĘCZNIE
          </div>
        </div>
      <% else %>
        <div class="flex gap-2">
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
              class="bg-greyButtonBg text-darkGrey rounded-md border-none text-sm h-7 py-0 w-auto max-w-80 mb-2"
              prompt="WYBIERZ Z LISTY"
              options={
                @buyers
                |> Enum.map(fn buyer -> {Firmowid.Invoices.Buyer.get_name(buyer), buyer.id} end)
              }
            />
          </.form>
          <button
            phx-click={
              JS.push("submit", value: %{"invoice" => %{"buyer_id" => ""}})
              |> JS.push("update_buyer_state", value: %{"buyer_form_state" => :nip})
            }
            id="buyer_expand_button"
            class={[
              "uppercase border flex items-center gap-1 border-greyButtonBg text-darkGrey text-sm rounded-md h-7 px-2 mt-2 disabled:opacity-50 disabled:cursor-default",
              (@buyer_form_state == "nip" or @buyer_form_state == "expanded") &&
                (@invoice.buyer_id == "" or !@invoice.buyer_id) &&
                "bg-darkGrey text-white"
            ]}
            phx-disable-with=""
          >
            Wprowadź <.icon name="hero-plus" class="w-4 h-4" />
          </button>
        </div>
      <% end %>
      <%= if @invoice.is_buyer_confirmed do %>
        <div class="flex justify-between items-start text-sm border border-greyButtonBg rounded-md p-5">
          <div>
            <p class="font-semibold text-darkGrey mb-8">
              {case @invoice.buyer_type do
                :company -> "Firma/ Jednoosobowa Działalność Gospodarcza"
                :individual -> "Osoba prywatna"
              end}
            </p>
            <div class="flex gap-4">
              <div class="grid grid-cols-[max-content,1fr] gap-x-4 gap-y-2">
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
              <div class="grid grid-cols-[max-content,1fr] h-min justify-start gap-x-4 gap-y-2">
                <%= if @invoice.buyer_email do %>
                  <span class="text-darkGrey">e-mail</span>
                  <span>{@invoice.buyer_email}</span>
                <% end %>
                <%= if @invoice.buyer_phone do %>
                  <span class="text-darkGrey">Telefon</span>
                  <span>{@invoice.buyer_phone}</span>
                <% end %>
                <%= if @invoice.buyer_description do %>
                  <span class="text-darkGrey">Opis</span>
                  <span>{@invoice.buyer_description}</span>
                <% end %>
              </div>
            </div>
          </div>

          <.edit_button phx-click={
            JS.push("submit", value: %{"invoice" => %{"is_buyer_confirmed" => false}})
          } />
        </div>
      <% else %>
        <%= case @buyer_form_state do %>
          <% "expanded" -> %>
            <.form
              phx-submit="submit"
              class="flex flex-col gap-2"
              phx-change="change"
              id="buyer_form"
              for={@buyer_form}
            >
              <div class="bg-greyButtonBg/50 px-5 h-[50px] flex items-center rounded-md">
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
                    <.input
                      field={@buyer_form[:buyer_street]}
                      type="text"
                      placeholder="Adres"
                      required
                    />
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
                    <.input
                      field={@buyer_form[:buyer_country]}
                      type="text"
                      placeholder="Kraj"
                      required
                    />
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
                    <.input
                      field={@buyer_form[:buyer_description]}
                      type="textarea"
                      placeholder="Opis"
                    />
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
          <% "closed" -> %>
            <hr class="border-t border-t-greyButtonBg" />
          <% "nip" -> %>
            <div class="bg-greyButtonBg/50 flex flex-col p-4 rounded">
              <div class="flex flex-col items-center gap-2">
                <.form
                  id="buyer_nip_form"
                  phx-submit="submit"
                  class="gap-3 flex flex-col"
                  for={@nip_form}
                >
                  <.input field={@nip_form[:nip]} placeholder="Nip klienta" type="text" />
                  <.button class="w-full" phx-disable-with="Wyszukiwanie..." color="green">
                    Wyszukaj dane klienta
                  </.button>
                </.form>
                <div class="text-sm mt-3">
                  Lub
                  <button
                    class="text-blueText font-semibold"
                    phx-value-buyer_form_state="expanded"
                    phx-click="update_buyer_state"
                  >
                    uzupełnij dane klienta ręcznie
                  </button>
                </div>
              </div>
            </div>
        <% end %>
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
