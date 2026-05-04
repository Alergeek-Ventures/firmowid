defmodule FirmowidWeb.Invoicing.Assistant.Components.PendingMatch do
  @moduledoc """
  Pending match preview rows rendered inside the invoicing assistant.
  """
  use FirmowidWeb, :html

  alias Firmowid.Ash.Invoicing.CostInvoice
  alias Firmowid.Ash.Invoicing.SalesInvoice

  attr :invoice, :map, required: true

  def invoice_item(%{invoice: %CostInvoice{} = invoice} = assigns) do
    assigns =
      assigns
      |> assign(:number, invoice.invoice_identifier || "—")
      |> assign(:party, invoice.effective_seller_display_name || invoice.seller || "—")
      |> assign(
        :amount,
        display_money(invoice.effective_currency, invoice.effective_total_amount)
      )

    ~H"""
    <li class="bg-grey-50 flex flex-row items-start justify-between gap-4 rounded px-3 py-2">
      <div class="grid grid-cols-[min-content_1fr] gap-x-3">
        <span class="text-grey-700 text-sm">Typ</span>
        <span class="text-black">Faktura kosztowa</span>
        <span class="text-grey-700 text-sm">Numer</span>
        <span class="truncate text-black">{@number}</span>
        <span class="text-grey-700 text-sm">Kontrahent</span>
        <span class="truncate text-black">{@party}</span>
      </div>
      <div class="flex flex-row items-center gap-3 text-right">
        <span>{@amount}</span>
        <.icon name="hero-document-text-micro" class="text-grey-700" />
      </div>
    </li>
    """
  end

  def invoice_item(%{invoice: %SalesInvoice{} = invoice} = assigns) do
    assigns =
      assigns
      |> assign(:number, invoice.invoice_number || "—")
      |> assign(:party, invoice.buyer_display_name_label || invoice.buyer_full_name || "—")
      |> assign(:amount, display_money(invoice.currency, invoice.gross_value))

    ~H"""
    <li class="bg-grey-50 flex flex-row items-start justify-between gap-4 rounded px-3 py-2">
      <div class="grid grid-cols-[min-content_1fr] gap-x-3">
        <span class="text-grey-700 text-sm">Typ</span>
        <span class="text-black">Faktura sprzedażowa</span>
        <span class="text-grey-700 text-sm">Numer</span>
        <span class="truncate text-black">{@number}</span>
        <span class="text-grey-700 text-sm">Kontrahent</span>
        <span class="truncate text-black">{@party}</span>
      </div>
      <div class="flex flex-row items-center gap-3 text-right">
        <span>{@amount}</span>
        <.icon name="hero-document-text-micro" class="text-grey-700" />
      </div>
    </li>
    """
  end

  attr :transaction, :map, required: true
  attr :displayed_party_label, :string, required: true

  def transaction_item(assigns) do
    ~H"""
    <li class="bg-grey-50 flex flex-row items-start justify-between gap-4 rounded px-3 py-2">
      <div class="grid grid-cols-[min-content_1fr] gap-x-3">
        <span class="text-grey-700 text-sm">{@displayed_party_label}</span>
        <span class="truncate text-black">
          {displayed_party(@transaction, @displayed_party_label)}
        </span>
        <span class="text-grey-700 text-sm">Zaksięgowano</span>
        <span class="text-black">{@transaction.booking_date}</span>
      </div>
      <div class="flex flex-row items-center gap-3">
        {@transaction.amount}
        <.icon name="hero-credit-card-micro" class="text-grey-700" />
      </div>
    </li>
    """
  end

  defp displayed_party(transaction, "Nadawca"), do: transaction.debtor_name
  defp displayed_party(transaction, "Odbiorca"), do: transaction.creditor_name

  defp display_money(currency, amount) do
    case Money.new(currency, amount) do
      %Money{} = money -> money
      _ -> "—"
    end
  end
end
