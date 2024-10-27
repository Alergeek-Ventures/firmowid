defmodule FirmowidWeb.DocumentsLive.DocumentsTable do
  import FirmowidWeb.CoreComponents
  use FirmowidWeb, :live_view

  use Phoenix.Component

  attr :invoice_matchers, :list, required: true

  def table(assigns) do
    columns = [
      %{label: "Kontrahent", key: "seller"},
      %{label: "Wystawiono", key: "sale_date"},
      %{label: "Termin płatności", key: "due_date"},
      %{label: "Status", key: "status"},
      %{label: "Kwota", key: "amount"}
    ]

    assigns = assign(assigns, :columns, columns)

    get_status = fn invoice_matcher ->
      case invoice_matcher do
        %{skip_invoicing: true} -> "Pominięte"
        %{documents: [], imported_transactions: _} -> "Transakcja"
        %{documents: _, imported_transactions: []} -> "Dokument"
        _ -> "Komplet"
      end
    end

    assigns = assign(assigns, :get_status, get_status)

    ~H"""
    <%= if length(@invoice_matchers) > 0 do %>
      <table class="table-fixed border-separate border-spacing-y-3">
        <col
          :for={column <- @columns}
          class={[
            column.key == "sale_date" && "w-36",
            column.key == "due_date" && "w-44",
            column.key == "status" && "w-40",
            column.key == "amount" && "w-44"
          ]}
        />
        <thead>
          <tr>
            <th
              :for={column <- @columns}
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
          <tr :for={invoice_matcher <- @invoice_matchers}>
            <td
              :for={column <- @columns}
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
                <.status_cell
                  status={@get_status.(invoice_matcher)}
                  invoice_matcher={invoice_matcher}
                />
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
      <div class="text-center text-darkGrey">
        Brak dokumentów i transakcji - nie mamy niczego do wyświetlenia...
      </div>
    <% end %>
    """
  end

  def status_cell(assigns) do
    ~H"""
    <div
      id={"status-#{
        @invoice_matcher.id
      }-#{
        @invoice_matcher.documents
        |> Enum.map(fn d -> d.id end)
        |> Enum.join(",")
      }-#{
        @invoice_matcher.imported_transactions
        |> Enum.map(fn t -> t.id end)
        |> Enum.join(",")
      }"}
      phx-hook="tippy"
      data-tippy-delay="1000"
      data-tippy-content={
        case @status do
          "Komplet" ->
            "Udało się połączyć transakcje i dokument - to oznacza, " <>
              "że faktura jest opłacona i przygotowana do zaksięgowania."

          "Transakcja" ->
            "Z Twojego konta zsynchronizowaliśmy transakcje - to znaczy, że " <>
              "do wydatku należy przyporządkować dokument. "

          "Dokument" ->
            "Dodałeś plik, zawierający fakturę kosztową. Aby potwierdzić jej " <>
              "opłacenie, przyporządkujemy odpowiednią transakcję z konta - lub " <>
              "kliknij 'pomiń', aby zasygnalizować opłacenie jej innym sposobem " <>
              "(np. gotówką)"

          "Pominięte" ->
            if @invoice_matcher.documents != [] do
              "Dokument został pominięty. Transakcje nie będą do niego przypisywane"
            else
              "Transakcja została pominięta. Dokumenty nie będą do niej przypisywane"
            end
        end
      }
      class="flex flex-row gap-2 w-32 overflow-hidden"
    >
      <div class={[
        "text-xs h-6",
        "flex flex-row justify-center items-center py-2 px-2 rounded-md",
        "transition-all duration-500",
        @status != "Pominięte" && "w-10",
        @status == "Pominięte" && "w-20 bg-greenBg text-greenText",
        @status == "Transakcja" && "bg-redBg text-redText",
        @status == "Dokument" && "bg-lightGreyBg text-darkGrey",
        @status == "Komplet" && "!w-full justify-between bg-greenBg text-greenText"
      ]}>
        <%= if @status == "Komplet" do %>
          <div class="font-normal uppercase"><%= @status %></div>
        <% end %>
        <.icon
          name={
            case @status do
              "Transakcja" ->
                "hero-credit-card-mini"

              "Dokument" ->
                "hero-document-text-solid"

              "Komplet" ->
                "hero-check-micro"

              "Pominięte" ->
                if @invoice_matcher.documents == [] do
                  "hero-credit-card-mini"
                else
                  "hero-document-text-solid"
                end
            end
          }
          class={[
            "h-4 w-4",
            @status == "Komplet" && "w-5 h-5"
          ]}
        />
      </div>
      <%= if @status != "Komplet" do %>
        <button
          phx-click="skip-invoicing"
          phx-value-invoice-matcher={@invoice_matcher}
          class={[
            "transition-all duration-500 cursor-auto",
            @status != "Pominięte" && "w-20",
            @status == "Pominięte" && "w-10",
            "h-6 uppercase text-xs text-darkGrey bg-lightGreyBg rounded-md"
          ]}
        >
          <%= if @status == "Pominięte" do %>
            <.icon name="hero-arrow-uturn-left-micro" class="h-4 w-4" />
          <% else %>
            Pomiń
          <% end %>
        </button>
      <% end %>
    </div>
    """
  end

  def amount_cell(assigns) do
    ~H"""
    <div class={[
      "text-right pr-5 py-2"
    ]}>
      <%= @amount %>
    </div>
    """
  end
end
