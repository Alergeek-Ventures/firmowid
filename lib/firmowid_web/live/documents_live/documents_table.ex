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
        %{skip_invoicing: true} -> "Pominięte"
        %{documents: [], imported_transactions: _} -> "Transakcja"
        %{documents: _, imported_transactions: []} -> "Dokument"
        _ -> "Komplet"
      end
    end

    ~H"""
    <%= if length(invoice_matchers) > 0 do %>
    <table class="table-fixed border-separate border-spacing-y-3">
      <col
        :for={column <- columns}
        class={[
          column.key == "sale_date" && "max-2xl:w-36",
          column.key == "due_date" && "max-2xl:w-36",
          column.key == "status" && "w-40",
          column.key == "amount" && "w-44"
        ]}
      />
      <thead>
        <tr>
          <th
            :for={column <- columns}
            class={[
              "font-normal text-left text-darkGrey text-xs uppercase",
              column.key == "seller" && "pl-5",
              column.key == "amount" && "hidden"
            ]}
          >
            <%= column.label %>
          </th>
          <th></th>
        </tr>
      </thead>
      <tbody>
        <tr :for={invoice_matcher <- invoice_matchers}>
          <td
            :for={column <- columns}
            class={[
              "bg-white py-2",
              column.key == "seller" && "rounded-l-md pl-5 pr-5 text-ellipsis max-xl:max-w-72",
              column.key == "sale_date" && "font-light",
              column.key == "due_date" && "font-light",
              column.key == "amount" && "rounded-r-md",
              column.key == "amount" &&
                Decimal.gt?(invoice_matcher.amount_numeric, 0) &&
                "text-blueText !bg-blueBg",
              column.key == "amount" && Decimal.lt?(invoice_matcher.amount_numeric, 0) &&
                "text-orangeText !bg-orangeBg"
            ]}
          >
            <%= if column.key == "status" do %>
              <.status_cell status={get_status.(invoice_matcher)} />
            <% else %>
              <%= if column.key == "amount" do %>
                <.amount_cell
                  amount_numeric={invoice_matcher.amount_numeric}
                  amount={invoice_matcher.amount}
                />
              <% else %>
                <%= if column.key == "seller" and invoice_matcher.documents != [] do %>
                  <.link
                    class="hover:underline"
                    navigate={~p"/documents/#{hd(invoice_matcher.documents).id}"}
                  >
                    <span>
                      <%= get_in(
                        invoice_matcher,
                        [Access.key!(String.to_atom(column.key))]
                      ) %>
                    </span>
                    <span class="text-darkGrey opacity-50 text-sm">
                      <%= if invoice_matcher.imported_transactions != [] do %>
                        <%= hd(invoice_matcher.imported_transactions).remittance_information_unstructured %>
                      <% else %>
                        <%= if invoice_matcher.documents != [] do %>
                          <%= hd(invoice_matcher.documents).description %>
                        <% end %>
                      <% end %>
                    </span>
                  </.link>
                <% else %>
                  <%= if column.key == "seller" do %>
                    <span>
                      <%= get_in(
                        invoice_matcher,
                        [Access.key!(String.to_atom(column.key))]
                      ) %>
                    </span>
                    <span class="text-darkGrey opacity-50 text-sm">
                      <%= if invoice_matcher.imported_transactions != [] do %>
                        <%= hd(invoice_matcher.imported_transactions).remittance_information_unstructured %>
                      <% else %>
                        <%= if invoice_matcher.documents != [] do %>
                          <%= hd(invoice_matcher.documents).description %>
                        <% end %>
                      <% end %>
                    </span>
                  <% else %>
                    <%= if get_in(invoice_matcher,
                  [Access.key!(String.to_atom(column.key))]) != nil do %>
                      <%= get_in(
                        invoice_matcher,
                        [Access.key!(String.to_atom(column.key))]
                      ) %>
                    <% else %>
                      <span class="text-darkGrey opacity-50">
                        &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;-
                      </span>
                    <% end %>
                  <% end %>
                <% end %>
              <% end %>
            <% end %>
          </td>
        </tr>
      </tbody>
      </table>
    <% else %>
      <div class="text-center text-darkGrey">Brak dokumentów i transakcji - nie mamy niczego do wyświetlenia...</div>
    <% end %>
    """
  end

  def status_cell(assigns) do
    status = assigns.status

    ~H"""
    <div class={[
      "text-xs h-6 w-32",
      "flex flex-row justify-between items-center py-2 px-2 rounded-md",
      status == "Pominięte" && "bg-greenBg text-greenText",
      status == "Transakcja" && "bg-redBg text-redText",
      status == "Dokument" && "bg-lightGreyBg text-darkGrey",
      status == "Komplet" && "bg-greenBg text-greenText"
    ]}>
      <div class="font-normal uppercase"><%= status %></div>
      <.icon
        name={
          case status do
            "Transakcja" -> "hero-credit-card-mini"
            "Dokument" -> "hero-document-currency-dollar-mini"
            "Komplet" -> "hero-document-check-mini"
            "Pominięte" -> "hero-document-minus"
          end
        }
        class="h-4 w-4"
      />
    </div>
    """
  end

  def amount_cell(assigns) do
    amount = assigns.amount

    ~H"""
    <div class={[
      "text-right pr-5 py-2"
    ]}>
      <%= amount %>
    </div>
    """
  end
end
