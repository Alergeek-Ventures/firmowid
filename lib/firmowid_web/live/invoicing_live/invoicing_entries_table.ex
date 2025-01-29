defmodule FirmowidWeb.InvoicingLive.InvoicingEntriesTable do
  use FirmowidWeb, :live_view

  import FirmowidWeb.CoreComponents

  alias Firmowid.Finances.Transaction
  alias Firmowid.CostInvoices.CostInvoice
  alias Firmowid.SalesInvoices.SalesInvoice

  attr :invoicing_entries, :list, required: true
  attr :has_connected_bank_account, :boolean, default: false

  @columns ["party", "sale_date", "due_date", "status", "amount"]
  @column_labels ["Kontrahent", "Wystawiono", "Termin płatności", "Status", "Kwota"]

  def table(%{invoicing_entries: [], has_connected_bank_account: true} = assigns) do
    ~H"""
    <div class="flex flex-col gap-4 justify-center items-center min-h-[300px]">
      <.icon name="hero-cloud-arrow-up" class="h-16 w-16 text-greenText" />
      <p class="text-center text-black">
        Brak transakcji i dokumentów dla wybranej daty
      </p>
      <p class="text-center text-darkGrey">
        Przeciągnij pliki, aby je wgrać
      </p>
    </div>
    """
  end

  def table(%{invoicing_entries: [], has_connected_bank_account: false} = assigns) do
    ~H"""
    <div class="flex flex-col gap-24 justify-center min-h-[300px] px-8 mx-auto mt-16">
      <div class="flex flex-col gap-8">
        <h1 class="text-xl font-bold">Witaj w Firmowidzie!</h1>
        <div class="flex flex-col gap-1">
          <p>
            Znajdujesz się w panelu, w którym pojawią się wszystkie Twoje faktury i transakcje.
          </p>
          <p>
            Do pełnej funkcjonalności jeszcze tylko 2 kroki.
          </p>
        </div>
      </div>
      <div class="flex md:flex-row md:gap-20 gap-8 items-start justify-between">
        <div class="max-w-[500px]">
          <h2 class="text-xl font-bold mb-2 flex items-end gap-2">
            <.icon name="hero-building-library" class="h-10 w-10 text-greenText" /> Krok 1.
          </h2>
          <h3 class="text-xl mb-4">Podepnij konto bankowe</h3>
          <p class="mb-8">Dzięki temu wszystkie transakcje pojawią się w Firmowidzie
            automatycznie. Co więcej, po wykryciu odpowiedniej faktury transakcja
            połączy się z dokumentem.</p>
          <.link navigate={~p"/ustawienia/bank/dodaj"} class={button_styles(%{color: "green"})}>
            Synchronizacja z bankiem
          </.link>
        </div>
        <div class="max-w-[400px]">
          <h2 class="text-xl font-bold mb-2 flex items-end gap-2">
            <.icon name="hero-cloud-arrow-up" class="h-10 w-10 text-greenText" /> Krok 2.
          </h2>
          <h3 class="text-xl mb-4">Wgraj faktury</h3>
          <p class="mb-2">Możesz to zrobić:</p>
          <ul class="list-disc space-y-2 list-outside ml-4">
            <li>
              Za pomocą przycisku <span class="font-bold">+ Dodaj dokument</span> w prawym górnym rogu
            </li>
            <li>
              <span class="font-bold">Przeciągając pliki</span> bezpośrednio do tego panelu
            </li>
            <li>
              Logując się na stronę przez telefon komórkowy i <span class="font-bold">przesyłając
                zdjęcie dokumentu</span>
            </li>
          </ul>
        </div>
      </div>
    </div>
    """
  end

  def table(assigns) do
    assigns =
      assigns
      |> assign(:columns, @columns)
      |> assign(:column_labels, @column_labels)

    ~H"""
    <table
      id="invoicing-entries"
      class="table-fixed border-separate border-spacing-y-3"
      phx-hook="ListItemRemovalAnimation"
    >
      <col
        :for={column <- @columns}
        class={
          case column do
            "sale_date" -> "w-36"
            "due_date" -> "w-44"
            "status" -> "w-40"
            "amount" -> "w-44"
            _ -> ""
          end
        }
      />
      <thead class="sticky top-[154px] bg-lightGreyBg z-20">
        <tr>
          <th
            :for={column <- @columns}
            id={"header-#{column}"}
            phx-hook="ScrollStyle"
            data-classes="border-b-4 border-solid border-darkGrey border-opacity-40"
            data-scroll-offset="90"
            class={
              [
                "pt-4 font-normal text-left text-darkGrey text-xs uppercase pb-2",
                column == "party" && "pl-5",
                column == "amount" && "hidden"
              ]
              |> Enum.join(" ")
            }
          >
            {@column_labels |> Enum.at(Enum.find_index(@columns, fn c -> c == column end))}
          </th>
          <th
            id="header-amount-standalone"
            phx-hook="ScrollStyle"
            class="pt-4"
            data-classes="border-b-4 border-solid border-darkGrey"
            data-scroll-offset="90"
          >
          </th>
        </tr>
      </thead>
      <tbody>
        <%= for invoicing_entry <- @invoicing_entries do %>
          <.table_row invoicing_entry={invoicing_entry} />
        <% end %>
      </tbody>
    </table>
    """
  end

  defp table_row(assigns) do
    assigns =
      assigns
      |> assign(:columns, @columns)
      |> assign(
        :amount,
        case assigns.invoicing_entry do
          %Transaction{} -> assigns.invoicing_entry.transaction_amount
          %CostInvoice{} -> assigns.invoicing_entry.total_amount
          %SalesInvoice{} -> SalesInvoice.get_gross_value(assigns.invoicing_entry)
        end
      )

    ~H"""
    <tr id={"#{@invoicing_entry.id}-row"}>
      <td
        :for={column <- @columns}
        class={[
          "transition-all duration-500 bg-white py-2",
          column == "party" && "rounded-l-md pl-5 pr-5 text-ellipsis max-xl:max-w-72",
          column == "sale_date" && "font-light",
          column == "due_date" && "font-light",
          column == "amount" && "rounded-r-md",
          column == "amount" &&
            Decimal.gte?(@amount, 0) &&
            "text-blueText !bg-blueBg",
          column == "amount" && Decimal.lt?(@amount, 0) &&
            "text-orangeText !bg-orangeBg"
        ]}
      >
        <div
          data-overflow-hider-id={@invoicing_entry.id}
          class={
            [
              # required to display the "dot freshness" indicator that is rendered outside of the cell
              column != "amount" && "w-full whitespace-nowrap overflow-hidden overflow-ellipsis"
            ]
          }
        >
          <.render_cell column={column} invoicing_entry={@invoicing_entry} />
        </div>
      </td>
    </tr>
    """
  end

  # amount is differently rendered (has a background color that fills the cell)
  defp render_cell(%{column: "amount", invoicing_entry: %Transaction{} = transaction} = assigns) do
    amount = Money.new(transaction.transaction_currency, transaction.transaction_amount)

    assigns =
      assigns
      |> assign(:amount, amount)

    ~H"""
    <div class={[
      "text-right pr-5 py-2 relative"
    ]}>
      {@amount}
    </div>
    """
  end

  defp render_cell(%{column: "amount", invoicing_entry: %SalesInvoice{} = invoice} = assigns) do
    amount = Money.new(invoice.currency, SalesInvoice.get_gross_value(invoice))

    assigns =
      assigns
      |> assign(:amount, amount)

    ~H"""
    <div class={[
      "text-right pr-5 py-2 relative"
    ]}>
      {@amount}
    </div>
    """
  end

  defp render_cell(%{column: "amount", invoicing_entry: %CostInvoice{} = invoice} = assigns) do
    is_fresh =
      DateTime.compare(
        invoice.inserted_at,
        DateTime.add(DateTime.utc_now(), -120, :second)
      ) ==
        :gt

    amount = Money.new(invoice.currency, invoice.total_amount)

    assigns =
      assigns
      |> assign(:is_fresh, is_fresh)
      |> assign(:amount, amount)

    ~H"""
    <div class={[
      "text-right pr-5 py-2 relative"
    ]}>
      {@amount}

      <%= if @is_fresh do %>
        <span
          id={"amount-fresh-#{@invoicing_entry.id}"}
          phx-hook="Tippy"
          data-tippy-delay="10"
          data-tippy-content="Ten dokument właśnie został dodany!"
          class="absolute top-[-10px] right-[-4px] flex h-3 w-3"
        >
          <span class={[
            "animate-ping absolute inline-flex h-full w-full",
            "rounded-full bg-blueText opacity-75"
          ]}>
          </span>
          <span class="relative inline-flex rounded-full h-3 w-3 bg-blueText"></span>
        </span>
      <% end %>
    </div>
    """
  end

  # status cell is rendered differently (has a button)
  defp render_cell(%{column: "status", status: "skipped"} = assigns) do
    ~H"""
    <div
      id={"#{@invoicing_entry.id}-container"}
      phx-hook="Tippy"
      data-tippy-delay="1000"
      data-tippy-content={
        case @invoicing_entry do
          %Transaction{} ->
            "Transakcja została pominięta. Faktury nie będą do niej przypisywane"

          _ ->
            "Dokument został pominięty. Transakcje nie będą do niego przypisywane"
        end
      }
      class="flex flex-row gap-2 w-32 overflow-hidden"
    >
      <div
        id={"#{@invoicing_entry.id}-label"}
        class={[
          "text-xs h-6",
          "flex flex-row justify-center items-center py-2 px-2 rounded-md",
          "transition-all duration-500",
          "w-20 bg-greenBg text-greenText"
        ]}
      >
        <.icon
          name={
            case @invoicing_entry do
              %Transaction{} ->
                "hero-credit-card-mini"

              _ ->
                "hero-document-text-solid"
            end
          }
          class="h-4 w-4"
        />
      </div>
      <button
        id={"#{@invoicing_entry.id}-button"}
        phx-click="toggle-skip-invoicing"
        phx-value-id={@invoicing_entry.id}
        phx-value-type={
          case @invoicing_entry do
            %Transaction{} -> "transaction"
            %CostInvoice{} -> "cost_invoice"
            %SalesInvoice{} -> "sales_invoice"
          end
        }
        class={[
          "transition-all duration-500 cursor-pointer",
          "w-20",
          "h-6 uppercase text-xs text-darkGrey bg-lightGreyBg rounded-md"
        ]}
      >
        <.icon name="hero-arrow-uturn-left-micro" class="h-4 w-4" />
      </button>
    </div>
    """
  end

  defp render_cell(%{column: "status", status: "matched"} = assigns) do
    ~H"""
    <div
      id={"status-#{@invoicing_entry.id}"}
      phx-hook="tippy"
      data-tippy-delay="1000"
      data-tippy-content={
            "Udało się połączyć transakcje i dokument - to oznacza, " <>
              "że faktura jest opłacona i przygotowana do zaksięgowania."
      }
      class="
      flex flex-row gap-2 w-32 overflow-hidden"
    >
      <div class={[
        "text-xs h-6",
        "flex flex-row justify-center items-center py-2 px-2 rounded-md",
        "transition-all duration-500",
        "w-full justify-between bg-greenBg text-greenText"
      ]}>
        <div class="font-normal uppercase">Komplet</div>
        <.icon name="hero-check-micro" class="w-5 h-5" />
      </div>
    </div>
    """
  end

  defp render_cell(%{column: "status", status: "unmatched"} = assigns) do
    ~H"""
    <div
      id={"#{@invoicing_entry.id}-container"}
      phx-hook="Tippy"
      data-tippy-delay="1000"
      data-tippy-content={
        case @invoicing_entry do
          %Transaction{} ->
            "Z Twojego konta zsynchronizowaliśmy transakcje - to znaczy, że " <>
              "do wydatku należy przyporządkować dokument. "

          _ ->
            "Dodałeś plik, zawierający fakturę kosztową. Aby potwierdzić jej " <>
              "opłacenie, przyporządkujemy odpowiednią transakcję z konta - lub " <>
              "kliknij 'pomiń', aby zasygnalizować opłacenie jej innym sposobem " <>
              "(np. gotówką)"
        end
      }
      class="flex flex-row gap-2 w-32 overflow-hidden"
    >
      <div
        id={"#{@invoicing_entry.id}-label"}
        class={[
          "text-xs h-6",
          "flex flex-row justify-center items-center py-2 px-2 rounded-md",
          "transition-all duration-500",
          "w-10",
          case @invoicing_entry do
            %Transaction{} -> "bg-redBg text-redText"
            _ -> "bg-lightGreyBg text-darkGrey"
          end
        ]}
      >
        <.icon
          name={
            case @invoicing_entry do
              %Transaction{} ->
                "hero-credit-card-mini"

              _ ->
                "hero-document-text-solid"
            end
          }
          class="h-4 w-4"
        />
      </div>
      <button
        id={"#{@invoicing_entry.id}-button"}
        phx-click="toggle-skip-invoicing"
        phx-value-id={@invoicing_entry.id}
        phx-value-type={
          case @invoicing_entry do
            %Transaction{} -> "transaction"
            %CostInvoice{} -> "cost_invoice"
            %SalesInvoice{} -> "sales_invoice"
          end
        }
        class={[
          "transition-all duration-500 cursor-pointer",
          "w-20",
          "h-6 uppercase text-xs text-darkGrey bg-lightGreyBg rounded-md"
        ]}
      >
        Pomiń
      </button>
    </div>
    """
  end

  defp render_cell(%{column: "status"} = assigns) do
    value =
      case assigns.invoicing_entry do
        %{skip_invoicing: true} ->
          "skipped"

        %CostInvoice{} = invoice ->
          if invoice.transactions != [] do
            "matched"
          else
            "unmatched"
          end

        _ ->
          "unmatched"
      end

    assigns = assigns |> assign(:status, value)

    ~H"<.render_cell column={@column} status={@status} invoicing_entry={@invoicing_entry} />"
  end

  # rest of the cells are rendered more or less in the same way

  defp render_cell(%{column: "SKIPPED"} = assigns) do
    ~H"""
    <span class="text-darkGrey opacity-50">
      &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;-
    </span>
    """
  end

  defp render_cell(%{invoicing_entry: %Transaction{} = _, column: "sale_date"} = assigns),
    do: render_cell(assigns |> assign(:column, "booking_date"))

  defp render_cell(%{invoicing_entry: %Transaction{} = _, column: "due_date"} = assigns),
    do: render_cell(assigns |> assign(:column, "SKIPPED"))

  defp render_cell(%{invoicing_entry: %Transaction{} = transaction, column: "party"} = assigns) do
    party =
      if Decimal.compare(assigns.invoicing_entry.transaction_amount, 0) == :gt do
        transaction.debtor_name
      else
        transaction.creditor_name
      end

    assigns =
      assigns
      |> assign(:party, party)
      |> assign(:description, transaction.remittance_information_unstructured)

    ~H"<.render_cell party={@party} description={@description} column={@column} />"
  end

  defp render_cell(%{invoicing_entry: %CostInvoice{} = invoice, column: "party"} = assigns) do
    assigns =
      assigns
      |> assign(:party, invoice.seller_display_name)
      |> assign(:description, invoice.description)
      |> assign(:navigate, ~p"/kosztowe/#{invoice.id}")

    ~H"<.render_cell party={@party} navigate={@navigate} description={@description} column={@column} />"
  end

  defp render_cell(%{invoicing_entry: %SalesInvoice{} = invoice, column: "party"} = assigns) do
    assigns =
      assigns
      |> assign(:party, invoice.buyer_display_name)
      |> assign(
        :description,
        invoice.sales_invoice_items |> Enum.map(& &1.name) |> Enum.join(", ")
      )
      |> assign(:navigate, ~p"/sprzedazowe/#{invoice.id}")

    ~H"<.render_cell party={@party} navigate={@navigate} description={@description} column={@column} />"
  end

  defp render_cell(%{navigate: _, party: _, description: _, column: "party"} = assigns) do
    ~H"""
    <.link navigate={@navigate} class="hover:underline">
      <.render_cell party={@party} description={@description} column={@column} />
    </.link>
    """
  end

  defp render_cell(%{party: _, description: _, column: "party"} = assigns) do
    ~H"""
    {@party} <span class="text-darkGrey opacity-50 text-sm">{@description}</span>
    """
  end

  # plain render (fallback)
  defp render_cell(%{invoicing_entry: invoicing_entry, column: column} = assigns) do
    value = get_in(invoicing_entry, [Access.key!(String.to_atom(column))])

    assigns =
      assigns
      |> assign(:value, value)

    ~H"""
    {@value}
    """
  end
end

# ~H"""
# <div
#   id={"status-#{
#     @invoicing_entry.id
#   }-#{
#     @invoicing_entry.cost_invoices
#     |> Enum.map(fn d -> d.id end)
#     |> Enum.join(",")
#   }-#{
#     @invoicing_entry.transactions
#     |> Enum.map(fn t -> t.id end)
#     |> Enum.join(",")
#   }"}
#   phx-hook="Tippy"
#   data-tippy-delay="1000"
#   data-tippy-content={
#     case @status do
#       "Komplet" ->
#         "Udało się połączyć transakcje i dokument - to oznacza, " <>
#           "że faktura jest opłacona i przygotowana do zaksięgowania."

#       "Pominięte" ->
#         if @invoicing_entry.cost_invoices != [] do
#           "Dokument został pominięty. Transakcje nie będą do niego przypisywane"
#         else
#           "Transakcja została pominięta. Faktury nie będą do niej przypisywane"
#         end
#     end
#   }
#   class="flex flex-row gap-2 w-32 overflow-hidden"
# >
#   <div class={[
#     "text-xs h-6",
#     "flex flex-row justify-center items-center py-2 px-2 rounded-md",
#     "transition-all duration-500",
#     @status != "Pominięte" && "w-10",
#     @status == "Pominięte" && "w-20 bg-greenBg text-greenText",
#     @status == "Transakcja" && "bg-redBg text-redText",
#     @status == "Dokument" && "bg-lightGreyBg text-darkGrey",
#     @status == "Komplet" && "!w-full justify-between bg-greenBg text-greenText"
#   ]}>
#     <%= if @status == "Komplet" do %>
#       <div class="font-normal uppercase">{@status}</div>
#     <% end %>
#     <.icon
#       name={
#         case @status do
#           "Transakcja" ->
#             "hero-credit-card-mini"

#           "Dokument" ->
#             "hero-document-text-solid"

#           "Komplet" ->
#             "hero-check-micro"

#           "Pominięte" ->
#             if @invoicing_entry.cost_invoices == [] do
#               "hero-credit-card-mini"
#             else
#               "hero-document-text-solid"
#             end
#         end
#       }
#       class={
#         classes([
#           "h-4 w-4",
#           @status == "Komplet" && "w-5 h-5"
#         ])
#       }
#     />
#   </div>
#   <%= if @status != "Komplet" do %>
#     <button
#       phx-click="toggle-skip-invoicing"
#       phx-value-invoice-matcher={@invoicing_entry}
#       class={[
#         "transition-all duration-500 cursor-auto",
#         @status != "Pominięte" && "w-20",
#         @status == "Pominięte" && "w-10",
#         "h-6 uppercase text-xs text-darkGrey bg-lightGreyBg rounded-md"
#       ]}
#     >
#       <%= if @status == "Pominięte" do %>
#         <.icon name="hero-arrow-uturn-left-micro" class="h-4 w-4" />
#       <% else %>
#         Pomiń
#       <% end %>
#     </button>
#   <% end %>
# </div>
# """
# end
