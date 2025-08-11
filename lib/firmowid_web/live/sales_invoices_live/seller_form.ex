defmodule FirmowidWeb.SalesInvoicesLive.SellerForm do
  require Logger
  import FirmowidWeb.SalesInvoicesLive.EditButton

  use FirmowidWeb, :html

  attr :seller_form, :list, required: true
  attr :sales_invoice, :map, required: true
  attr :bank_accounts, :list, required: true
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
            if @sales_invoice.seller_account_number != "" do
              "true"
            else
              "false"
            end
          }
        />
        <.input
          field={@seller_form[:seller_account_number]}
          type="select"
          class="bg-greyButtonBg text-darkGrey rounded-md border-none text-sm h-7 py-0 w-auto max-w-80 mb-2"
          prompt="WYBIERZ Z LISTY"
          options={
            @bank_accounts
            |> Enum.map(fn bank_account ->
              display_institution =
                cond do
                  bank_account.name && bank_account.name != "" -> bank_account.name
                  bank_account.institution_name == "Manual" -> "wprowadzone ręcznie"
                  true -> bank_account.institution_name
                end

              label =
                "[#{bank_account.currency}] #{display_institution} #{bank_account.iban} " <>
                  if bank_account.is_default and bank_account.currency == @sales_invoice.currency,
                    do: "[domyślne dla waluty]",
                    else: ""

              {label, bank_account.iban}
            end)
          }
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
            <span>
              {case @sales_invoice.seller_account_number do
                nil -> "Wybierz z listy powyżej lub wprowadź ręcznie"
                account_number -> account_number
              end}
            </span>
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
            </div>
          </div>
        </.form>
      <% end %>
    </div>
    """
  end
end
