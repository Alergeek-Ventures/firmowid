defmodule FirmowidWeb.Invoicing.Components.BankTransferModal do
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
      <.button
        id="show-transfer-details-button"
        phx-click={show_modal("bank-transfer-modal")}
        type="button"
        class="w-full"
        color="grey"
        size="small"
        new={true}
      >
        Skopiuj dane
      </.button>

      <.modal
        id="bank-transfer-modal"
        class="max-w-[1000px]"
        on_cancel={hide_modal("bank-transfer-modal")}
      >
        <div class="flex flex-col gap-12">
          <h3 class="text-center text-lg font-semibold">Dane do przelewu</h3>
          <div class="grid grid-cols-[min-content_1fr_min-content] items-center gap-4">
            <%= for {label, value} <- [
            {"Odbiorca", @invoice.seller},
            {"Adres", @invoice.seller_address},
            {"Numer konta", @invoice.account_number},
            {"Tytuł przelewu", "Płatność za fakturę
                #{@invoice.invoice_identifier}"},
            {"Kwota", @invoice.total_amount |> Decimal.abs()},
            {"Waluta", @invoice.currency}
          ] do %>
              <label for={"transfer-#{label}"} class="text-sm self-start text-nowrap">
                {label}
              </label>
              <code id={"transfer-#{label}"} class="text-right text-black">{value}</code>
              <.button
                id={"copy-#{label}"}
                onclick={"navigator.clipboard.writeText('#{value}')"}
                type="button"
                class="size-6"
                color="light_grey"
                size="small"
                new={true}
              >
                <.icon name="hero-clipboard-document-solid" class="size-4 shrink-0" />
              </.button>
            <% end %>
          </div>
          <div class="flex flex-row gap-6">
            <div class="flex items-center justify-center grow bg-orange-200 px-4 py-2 rounded-lg">
              <h4 class="text-orange-700">
                Zawsze weryfikuj kopiowane dane z fakturą!
              </h4>
            </div>
            <.button
              color="orange"
              new={true}
              phx-click={hide_modal("bank-transfer-modal")}
            >
              Gotowe
            </.button>
          </div>
        </div>
      </.modal>
    </span>
    """
  end
end
