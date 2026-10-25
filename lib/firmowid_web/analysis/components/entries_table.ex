defmodule FirmowidWeb.Analysis.Components.EntriesTable do
  @moduledoc "Documents underlying the analysis charts with category assignment controls."
  use FirmowidWeb, :html

  import FirmowidUI.Components.Link
  import Phoenix.Component, except: [link: 1]

  alias Firmowid.Ash.Finances.Transaction
  alias Firmowid.Ash.Invoicing.CostInvoice
  alias Firmowid.Ash.Invoicing.SalesInvoice

  attr :entries, :list, required: true
  attr :categories, :list, default: []
  attr :colors, :map, required: true
  attr :can_write, :boolean, default: false

  attr :unrealized, :boolean,
    default: false,
    doc: "show overdue days with dashed borders instead of categories"

  @doc "Renders full document amounts and category controls for authorized users."
  @spec table(map()) :: Phoenix.LiveView.Rendered.t()
  def table(assigns) do
    assigns =
      assign(
        assigns,
        :show_overdue,
        assigns.unrealized and Enum.any?(assigns.entries, &overdue_days/1)
      )

    ~H"""
    <table class="w-full table-fixed border-separate border-spacing-y-2">
      <col /><col :if={@show_overdue} class="w-40" /><col :if={not @unrealized} class="w-96" />
      <col class="w-36" />
      <thead>
        <tr>
          <th class="py-2 pl-5 text-left text-xs font-normal text-grey-700 uppercase">Kontrahent</th>
          <th :if={@show_overdue}></th>
          <th
            :if={not @unrealized}
            class="py-2 pr-6 text-right text-xs font-normal text-grey-700 uppercase"
          >
            {gettext("Categories")}
          </th>
          <th class="py-2 text-left text-xs font-normal text-grey-700 uppercase">Kwota</th>
        </tr>
      </thead>
      <tbody>
        <tr :if={@entries == []}>
          <td colspan="4" class="py-8 text-center text-grey-700">Brak wpisów</td>
        </tr>
        <.row
          :for={entry <- @entries}
          entry={entry}
          categories={@categories}
          colors={@colors}
          can_write={@can_write}
          unrealized={@unrealized}
          show_overdue={@show_overdue}
        />
      </tbody>
    </table>
    """
  end

  defp row(%{entry: %SalesInvoice{} = invoice} = assigns) do
    assigns =
      assigns
      |> assign(:party, invoice.buyer_display_name_label || "")
      |> assign(:description, Enum.map_join(invoice.sales_invoice_items, ", ", & &1.name))
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
      |> assign(:amount, invoice.effective_amount)
      |> assign(:income, Money.positive?(invoice.effective_amount))
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
      |> assign(:amount, transaction.amount)
      |> assign(:income, Money.positive?(transaction.amount))
      |> assign(:navigate, nil)

    ~H"<.entry_row {assigns} />"
  end

  defp entry_row(assigns) do
    ~H"""
    <tr>
      <td class={[
        "rounded-l-md bg-white px-5 py-2",
        @unrealized && "border-y-2 border-l-2 border-dashed border-grey-700/50"
      ]}>
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
      <td
        :if={@unrealized and @show_overdue}
        class="border-y-2 border-dashed border-grey-700/50 bg-white py-2 text-brick-700"
      >
        <.overdue days={overdue_days(@entry)} />
      </td>
      <td :if={not @unrealized} class="bg-white py-2 pr-4">
        <FirmowidWeb.Analysis.Components.CategorySelector.cell
          entry={@entry}
          categories={@categories}
          colors={@colors}
          can_write={@can_write}
        />
      </td>
      <td class={[
        "rounded-r-md py-2",
        if(@income, do: "bg-teal-200 text-teal-800", else: "bg-rust-200 text-rust-700"),
        @unrealized && "border-y-2 border-r-2 border-dashed border-grey-700/50"
      ]}>
        <div class="py-1 pr-5 text-right">{@amount}</div>
      </td>
    </tr>
    """
  end

  defp overdue(%{days: nil} = assigns), do: ~H""

  defp overdue(assigns) do
    ~H"""
    {ngettext("%{count} day overdue", "%{count} days overdue", @days)}
    """
  end

  defp overdue_days(%{effective_due_date: %Date{} = due_date}) do
    days = Date.diff(Date.utc_today(), due_date)
    if days > 0, do: days
  end

  defp overdue_days(_entry), do: nil

  defp party_cell(assigns) do
    ~H"""
    {@party}
    <span :if={@description not in [nil, ""]} class="text-sm text-grey-700 opacity-50">{@description}</span>
    """
  end
end
