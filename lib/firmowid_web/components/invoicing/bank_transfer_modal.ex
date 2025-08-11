defmodule FirmowidWeb.Components.Invoicing.BankTransferModal do
  @moduledoc false
  use FirmowidWeb, :live_component

  attr :invoice, :map, required: true

  @impl true
  def mount(socket) do
    socket = assign(socket, skip_scans: true)

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <span>
      <button
        id="show-transfer-details-button"
        phx-click={show_modal("bank-transfer-modal")}
        type="button"
        class={[
          "text-xs h-8 w-32 uppercase",
          "shrink-0 flex flex-row justify-center items-center py-2 px-2 rounded-md",
          "transition-all duration-500",
          "bg-darkGrey text-white"
        ]}
      >
        Skopiuj dane
      </button>

      <.modal
        id="bank-transfer-modal"
        class="max-w-[1000px]"
        on_cancel={hide_modal("bank-transfer-modal")}
      >
        <div class="flex flex-col gap-12 p-4">
          <h3 class="text-center text-lg font-semibold">Dane do przelewu</h3>
          <div class="grid grid-cols-[150px,1fr,32px] gap-4">
            <%= for {label, value} <- [
            {"Odbiorca", @invoice.seller},
            {"Adres", @invoice.seller_address},
            {"Numer konta", @invoice.account_number},
            {"Tytuł przelewu", "Płatność za fakturę
                #{@invoice.invoice_identifier}"},
              {"Kwota", @invoice.total_amount |> Decimal.abs()},
              {"Waluta", @invoice.currency}
          ] do %>
              <label for={"transfer-#{label}"} class="text-sm self-start">
                {label}
              </label>
              <code id={"transfer-#{label}"} class="text-right text-black">{value}</code>
              <button
                id={"copy-#{label}"}
                onclick={"navigator.clipboard.writeText('#{value}')"}
                type="button"
                class={[
                  "h-6 w-6 text-darkGrey rounded-md",
                  "bg-greyButtonBg self-center justify-self-end",
                  "shrink-0 flex flex-row justify-center items-center",
                  "hover:border-darkGrey border border-transparent",
                  "active:bg-darkGrey active:text-lightGreyBg",
                  "transition-all transition-duration-300"
                ]}
              >
                <.icon name="hero-clipboard-document-solid" class="w-4 h-4" />
              </button>
            <% end %>
          </div>
          <div class="flex flex-row gap-6">
            <h4 class="text-center flex-grow text-orangeText bg-orangeBg rounded px-4 py-2">
              Zawsze weryfikuj kopiowane dane z fakturą!
            </h4>
            <button
              class={[
                "max-w-[300px] self-end bg-orangeText text-white",
                "hover:bg-darkGrey hover:text-lightGreyBg",
                "rounded px-4 py-2",
                "transition-all transition-duration-300"
              ]}
              phx-click={hide_modal("bank-transfer-modal")}
            >
              Gotowe
            </button>
          </div>
        </div>
      </.modal>
    </span>
    """
  end
end
