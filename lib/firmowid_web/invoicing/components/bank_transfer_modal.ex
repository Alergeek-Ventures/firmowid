defmodule FirmowidWeb.Invoicing.Components.BankTransferModal do
  @moduledoc false
  use FirmowidWeb, :live_component

  import FirmowidWeb.DesignSystem.Components.Button
  import FirmowidWeb.DesignSystem.Components.CoreComponents, except: [button: 1]

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
        variant="tertiary"
        size="small"
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
            {"Adres", @invoice.effective_seller_address},
            {"Numer konta", @invoice.effective_account_number},
            {"Tytuł przelewu", "Płatność za fakturę
                #{@invoice.invoice_identifier}"},
            {"Kwota", @invoice.effective_amount |> Money.abs() |> Money.to_decimal()},
            {"Waluta", @invoice.effective_amount.currency}
          ] do %>
              <label for={"transfer-#{label}"} class="self-start text-sm text-nowrap">
                {label}
              </label>
              <code id={"transfer-#{label}"} class="text-right text-black">{value}</code>
              <.button
                id={"copy-#{label}"}
                onclick={"navigator.clipboard.writeText('#{value}')"}
                type="button"
                class="size-6"
                variant="secondary"
                size="small"
              >
                <.icon name="hero-clipboard-document-solid" class="size-4 shrink-0" />
              </.button>
            <% end %>
          </div>
          <div class="flex flex-row gap-6">
            <div class="flex grow items-center justify-center rounded-lg bg-orange-200 px-4 py-2">
              <h4 class="text-orange-700">
                Zawsze weryfikuj kopiowane dane z fakturą!
              </h4>
            </div>
            <.button
              variant="primary"
              accent="orange"
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
