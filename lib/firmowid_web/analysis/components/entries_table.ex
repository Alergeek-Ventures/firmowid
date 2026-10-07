defmodule FirmowidWeb.Analysis.Components.EntriesTable do
  @moduledoc "Documents underlying the analysis charts with category assignment controls."
  use FirmowidWeb, :html

  import FirmowidWeb.DesignSystem.Components.Link
  import Phoenix.Component, except: [link: 1]

  alias Firmowid.Ash.Finances.Transaction
  alias Firmowid.Ash.Invoicing.CostInvoice
  alias Firmowid.Ash.Invoicing.SalesInvoice

  attr :entries, :list, required: true
  attr :categories, :list, default: []
  attr :can_write, :boolean, default: false

  @doc "Renders full document amounts and category controls for authorized users."
  @spec table(map()) :: Phoenix.LiveView.Rendered.t()
  def table(assigns) do
    ~H"""
    <table class="w-full table-fixed border-separate border-spacing-y-2">
      <col /><col class="w-32" /><col class="w-48" /><col class="w-36" />
      <thead>
        <tr>
          <th class="text-darkGrey py-2 pl-5 text-left text-xs font-normal uppercase">Kontrahent</th>
          <th class="text-darkGrey py-2 text-left text-xs font-normal uppercase">Data sprzedaży</th>
          <th class="text-darkGrey py-2 text-left text-xs font-normal uppercase">
            {gettext("Categories")}
          </th>
          <th class="text-darkGrey py-2 text-left text-xs font-normal uppercase">Kwota</th>
        </tr>
      </thead>
      <tbody>
        <tr :if={@entries == []}>
          <td colspan="4" class="text-darkGrey py-8 text-center">Brak wpisów</td>
        </tr>
        <.row :for={entry <- @entries} entry={entry} categories={@categories} can_write={@can_write} />
      </tbody>
    </table>
    """
  end

  defp row(%{entry: %SalesInvoice{} = invoice} = assigns) do
    assigns =
      assigns
      |> assign(:party, invoice.buyer_display_name_label || "")
      |> assign(:description, Enum.map_join(invoice.sales_invoice_items, ", ", & &1.name))
      |> assign(:date, invoice.sale_date || invoice.issue_date)
      |> assign(:amount, invoice.effective_amount)
      |> assign(:income, Money.positive?(invoice.effective_amount))
      |> assign(:navigate, ~p"/sprzedazowe/#{invoice.id}")

    ~H"<.entry_row {assigns} />"
  end

  defp row(%{entry: %CostInvoice{} = invoice} = assigns) do
    assigns =
      assigns
      |> assign(
        :party,
        invoice.effective_seller_display_name || invoice.seller_display_name || invoice.seller ||
          ""
      )
      |> assign(:description, invoice.description)
      |> assign(:date, invoice.effective_sale_date || invoice.sale_date)
      |> assign(:amount, invoice.effective_amount)
      |> assign(:income, Money.negative?(invoice.effective_amount))
      |> assign(:navigate, ~p"/kosztowe/#{invoice.id}")

    ~H"<.entry_row {assigns} />"
  end

  defp row(%{entry: %Transaction{} = transaction} = assigns) do
    assigns =
      assigns
      |> assign(
        :party,
        if(Money.positive?(transaction.amount),
          do: transaction.debtor_name,
          else: transaction.creditor_name
        ) || ""
      )
      |> assign(:description, transaction.remittance_information_unstructured)
      |> assign(:date, transaction.booking_date)
      |> assign(:amount, transaction.amount)
      |> assign(:income, Money.positive?(transaction.amount))
      |> assign(:navigate, nil)

    ~H"<.entry_row {assigns} />"
  end

  defp entry_row(assigns) do
    ~H"""
    <tr>
      <td class="rounded-l-md bg-white px-5 py-2">
        <div class="truncate">
          <%= if @navigate do %>
            <.link kind="unstyled" navigate={@navigate} class="hover:underline">
              <.party_cell party={@party} description={@description} />
            </.link>
          <% else %>
            <.party_cell party={@party} description={@description} />
          <% end %>
        </div>
      </td>
      <td class="bg-white py-2 font-light">{@date}</td>
      <td class="bg-white py-2">
        <FirmowidWeb.Analysis.Components.CategorySelector.cell
          entry={@entry}
          categories={@categories}
          can_write={@can_write}
        />
      </td>
      <td class={[
        "rounded-r-md py-2",
        if(@income, do: "bg-blueBg text-blueText", else: "bg-orangeBg text-orangeText")
      ]}>
        <div class="py-1 pr-5 text-right">{@amount}</div>
      </td>
    </tr>
    """
  end

  defp party_cell(assigns) do
    ~H"""
    {@party}
    <span :if={@description not in [nil, ""]} class="text-darkGrey text-sm opacity-50">{@description}</span>
    """
  end
end
