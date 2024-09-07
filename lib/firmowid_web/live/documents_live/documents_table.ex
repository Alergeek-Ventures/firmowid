defmodule FirmowidWeb.DocumentsLive.DocumentsTable do
  import FirmowidWeb.CoreComponents
  use FirmowidWeb, :live_view

  use Phoenix.Component

  attr :invoice_matchers, :list, required: true

  def table(assigns) do
    invoice_matchers = assigns.invoice_matchers

    columns = [
      %{label: "Kontrahent", key: "seller"},
      %{label: "Wystawiono", key: "sale_date"},
      %{label: "Termin płatności", key: "due_date"},
      %{label: "Status", key: "status"},
      %{label: "Kwota", key: "amount"}
    ]

    get_status = fn invoice_matcher ->
      case invoice_matcher do
        %{documents: [], imported_transactions: _} -> "Transakcja"
        %{documents: _, imported_transactions: []} -> "Dokument"
        _ -> "Komplet"
      end
    end

    # <pre>
    # <%= inspect(hd(invoice_matchers)) %>
    # </pre>

    ~H"""
    <table class="table-fixed">
      <thead>
        <tr>
          <th
            :for={column <- columns}
            class={[
              "text-left",
              column.key == "amount" && "text-right"
            ]}
          >
            <%= column.label %>
          </th>
        </tr>
      </thead>
      <tbody>
        <tr
          :for={invoice_matcher <- invoice_matchers}
          phx-click={
            if length(invoice_matcher.documents) == 0 do
              JS.navigate(
                ~p"/finances/imported-transactions/#{hd(invoice_matcher.imported_transactions).id}"
              )
            else
              JS.navigate(~p"/documents/#{hd(invoice_matcher.documents).id}")
            end
          }
        >
          <td :for={column <- columns}>
            <%= if column.key == "status" do %>
              <.status_cell status={get_status.(invoice_matcher)} />
            <% else %>
              <%= if column.key == "amount" do %>
                <.amount_cell
                  amount_numeric={invoice_matcher.amount_numeric}
                  amount={invoice_matcher.amount}
                />
              <% else %>
                <div>
                  <%= if get_in(invoice_matcher,
                  [Access.key!(String.to_atom(column.key))]) != nil do %>
                    <%= get_in(
                      invoice_matcher,
                      [Access.key!(String.to_atom(column.key))]
                    ) %>
                  <% else %>
                    <span class="text-zinc-400">-</span>
                  <% end %>
                </div>
              <% end %>
            <% end %>
          </td>
        </tr>
      </tbody>
    </table>
    """
  end

  def status_cell(assigns) do
    status = assigns.status

    ~H"""
    <div class={[
      "flex flex-row justify-between items-center py-2 px-3 rounded-md mr-2",
      status == "Transakcja" && "bg-red-200 text-red-800",
      status == "Dokument" && "bg-gray-200 text-gray-800",
      status == "Komplet" && "bg-green-200 text-green-800"
    ]}>
      <div class="font-bold uppercase"><%= status %></div>
      <.icon
        name={
          case status do
            "Transakcja" -> "hero-credit-card"
            "Dokument" -> "hero-document-text"
            "Komplet" -> "hero-check-circle"
          end
        }
        class="h-4 w-4"
      />
    </div>
    """
  end

  def amount_cell(assigns) do
    amount = assigns.amount
    amount_numeric = assigns.amount_numeric

    ~H"""
    <pre>
    </pre>
    <div class={[
      "flex flex-row justify-end items-center py-2 px-3 rounded-md ml-2",
      "text-right",
      amount_numeric >= 0 && "text-blue-400",
      amount_numeric < 0 && "text-red-400"
    ]}>
      <div class="font-bold"><%= amount %></div>
    </div>
    """
  end
end
