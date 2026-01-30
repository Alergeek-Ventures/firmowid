defmodule FirmowidWeb.InvoicingLive.InvoicingEntriesTable do
  @moduledoc false
  use FirmowidWeb, :live_view

  import FirmowidWeb.CoreComponents

  alias Firmowid.CostInvoices.CostInvoice
  alias Firmowid.Finances.Transaction
  alias Firmowid.Ksef
  alias Firmowid.SalesInvoices.SalesInvoice
  alias FirmowidWeb.InvoicingLive.TransactionGroup

  attr :invoicing_entries, :list, required: true
  attr :has_connected_bank_account, :boolean, default: false
  attr :mode, :atom, required: true

  @default_columns ["party", "issue_or_value_date", "due_or_booking_date", "status", "amount"]

  @invoice_columns ["party", "issue_date", "due_date", "status", "amount"]
  @transaction_columns ["party", "value_date", "booking_date", "status", "amount"]

  @column_labels [
    party: "Kontrahent",
    issue_date: "Wystawiono",
    value_date: "Wykonano",
    issue_or_value_date: "Wystawiono / Wykonano",
    due_date: "Termin płatności",
    booking_date: "Zaksięgowano",
    due_or_booking_date: "Termin płatności / Zaksięgowano",
    status: "Status",
    amount: "Kwota"
  ]

  # Using map pattern match to avoid Dialyzer false positive about
  # LiveView internal assign fields (:__given__, etc.)
  defp get_sales_invoice_buyer_name(%{__struct__: SalesInvoice} = invoice) do
    Firmowid.SalesInvoices.buyer_display_name(invoice) || ""
  end

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
      assign(
        assigns,
        :columns,
        case assigns.mode do
          :invoices -> @invoice_columns
          :transactions -> @transaction_columns
          _ -> @default_columns
        end
      )

    ~H"""
    <style>
      /* needed for groups' chevrons (rotates on expand/collapse) */
      [id^="chevron-"] {
        transform-origin: center center;
        will-change: transform;
      }
      [id^="chevron-"].rotate-90 {
        transform: rotate(90deg);
      }
    </style>

    <table
      id="invoicing-entries"
      class="table-fixed border-separate border-spacing-y-3"
      phx-hook="ListItemRemovalAnimation"
    >
      <col
        :for={column <- @columns}
        class={
          case column do
            "issue_date" -> "w-36"
            "booking_date" -> "w-36"
            "issue_or_value_date" -> "w-36"
            "due_date" -> "w-44"
            "value_date" -> "w-44"
            "due_or_booking_date" -> "w-44"
            "status" -> "w-40"
            "amount" -> "w-44"
            _ -> ""
          end
        }
      />
      <thead class="sticky top-[130px] bg-lightGreyBg z-[1]">
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
            <.column_label column={column} />
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
        <%= for entry <- @invoicing_entries do %>
          <%= case entry do %>
            <% %TransactionGroup{} = group -> %>
              <.group_row group={group} columns={@columns} />
            <% invoicing_entry -> %>
              <.table_row columns={@columns} invoicing_entry={invoicing_entry} />
          <% end %>
        <% end %>
      </tbody>
    </table>
    """
  end

  defp column_label(assigns) do
    assigns = assign(assigns, :label, Keyword.get(@column_labels, String.to_existing_atom(assigns.column)))

    is_special_column =
      case assigns.column do
        "issue_or_value_date" -> true
        "due_or_booking_date" -> true
        _ -> false
      end

    if is_special_column do
      ~H"""
      <span
        id={"header-#{@column}-label"}
        class="inline-block"
        phx-hook="Tippy"
        data-tippy-content={
          case @column do
            "issue_or_value_date" ->
              "W przypadku faktur będzie to data wystawienia, w przypadku transakcji to data wykonania"

            "due_or_booking_date" ->
              "W przypadku faktur to termin płatności, w przypadku transakcji to data zaksięgowania płatnosci"
          end
        }
      >
        {@label}
      </span>
      """
    else
      ~H"""
      {@label}
      """
    end
  end

  defp table_row(assigns) do
    assigns =
      assign(
        assigns,
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
          String.ends_with?(column, "date") && "font-light",
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
              # this column has no defined width, so we limit the worst offenders "manually"
              column == "party" && "max-w-[50vw]",
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

    assigns = assign(assigns, :amount, amount)

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

    assigns = assign(assigns, :amount, amount)

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
      invoice.transactions == [] &&
        DateTime.after?(
          invoice.inserted_at,
          DateTime.add(DateTime.utc_now(), -120, :second)
        )

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
          "h-6 uppercase text-xs text-darkGrey bg-greyButtonBg rounded-md"
        ]}
      >
        <.icon name="hero-arrow-uturn-left-micro" class="h-4 w-4" />
      </button>
    </div>
    """
  end

  defp render_cell(%{column: "status", status: "ksef_sending"} = assigns) do
    ~H"""
    <div
      id={"status-#{@invoicing_entry.id}"}
      phx-hook="Tippy"
      data-tippy-delay="1000"
      data-tippy-content="Faktura jest wysyłana do KSeF. Proszę czekać na potwierdzenie."
      class="flex flex-row gap-2 w-32 overflow-hidden"
    >
      <div class={[
        "text-xs h-6",
        "flex flex-row justify-center items-center py-2 px-2 rounded-md",
        "w-full justify-between text-darkGrey"
      ]}>
        <div class="font-normal uppercase">Wysyłanie...</div>
        <.icon name="hero-arrow-path" class="w-4 h-4 animate-spin" />
      </div>
    </div>
    """
  end

  defp render_cell(%{column: "status", status: "ksef_failed"} = assigns) do
    ~H"""
    <div
      id={"status-#{@invoicing_entry.id}"}
      phx-hook="Tippy"
      data-tippy-delay="1000"
      data-tippy-content="Wysyłanie faktury do KSeF nie powiodło się. Nasz zespół został poinformowany i działa nad naprawą problemu."
      class="flex flex-row gap-2 w-32 overflow-hidden"
    >
      <div class={[
        "text-xs h-6",
        "flex flex-row justify-center items-center py-2 px-2 rounded-md",
        "w-full justify-between animate-error-pulse"
      ]}>
        <div class="font-normal uppercase">Błąd wysyłania</div>
        <.icon name="hero-exclamation-triangle-mini" class="w-4 h-4" />
      </div>
    </div>
    """
  end

  defp render_cell(%{column: "status", status: "matched"} = assigns) do
    ~H"""
    <div
      id={"status-#{@invoicing_entry.id}"}
      phx-hook="Tippy"
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
            _ -> "bg-greyButtonBg text-darkGrey"
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
          "h-6 uppercase text-xs text-darkGrey bg-greyButtonBg rounded-md"
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
          if invoice.transactions == [] do
            "unmatched"
          else
            "matched"
          end

        %SalesInvoice{} = invoice ->
          case Ksef.get_submission_info(invoice).status do
            :submitting -> "ksef_sending"
            :failed -> "ksef_failed"
            # :submitted or :not_submitted - use standard matched/unmatched logic
            _ -> if invoice.transactions == [], do: "unmatched", else: "matched"
          end

        %Transaction{} = transaction ->
          if transaction.cost_invoices_transactions != [] or
               transaction.sales_invoices_transactions != [] do
            "matched"
          else
            "unmatched"
          end

        _ ->
          "unmatched"
      end

    assigns = assign(assigns, :status, value)

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

  defp render_cell(%{invoicing_entry: %Transaction{}, column: "issue_date"} = assigns),
    do: assigns |> assign(:column, "booking_date") |> render_cell()

  defp render_cell(%{invoicing_entry: %Transaction{}, column: "due_date"} = assigns),
    do: assigns |> assign(:column, "SKIPPED") |> render_cell()

  defp render_cell(%{invoicing_entry: %Transaction{}, column: "issue_or_value_date"} = assigns),
    do: assigns |> assign(:column, "booking_date") |> render_cell()

  defp render_cell(%{invoicing_entry: %Transaction{}, column: "due_or_booking_date"} = assigns),
    do: assigns |> assign(:column, "booking_date") |> render_cell()

  defp render_cell(%{invoicing_entry: %CostInvoice{}, column: "due_or_booking_date"} = assigns),
    do: assigns |> assign(:column, "due_date") |> render_cell()

  defp render_cell(%{invoicing_entry: %SalesInvoice{}, column: "due_or_booking_date"} = assigns),
    do: assigns |> assign(:column, "due_date") |> render_cell()

  defp render_cell(%{invoicing_entry: %CostInvoice{}, column: "issue_or_value_date"} = assigns),
    do: assigns |> assign(:column, "issue_date") |> render_cell()

  defp render_cell(%{invoicing_entry: %SalesInvoice{}, column: "issue_or_value_date"} = assigns),
    do: assigns |> assign(:column, "issue_date") |> render_cell()

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
      |> assign(
        :navigate,
        if transaction.sales_invoices_transactions == [] do
          if transaction.cost_invoices_transactions != [] do
            ~p"/kosztowe/#{List.first(transaction.cost_invoices_transactions).id}"
          end
        else
          ~p"/sprzedazowe/#{List.first(transaction.sales_invoices_transactions).id}"
        end
      )

    ~H"<.render_cell party={@party} navigate={@navigate} description={@description} column={@column} />"
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
    party = get_sales_invoice_buyer_name(invoice)

    assigns =
      assigns
      |> assign(:party, party)
      |> assign(
        :description,
        case {
          party,
          Enum.map_join(invoice.sales_invoice_items, ", ", & &1.name)
        } do
          {nil, ""} -> "szkic faktury sprzedażowej"
          {"", ""} -> "szkic faktury sprzedażowej"
          {_party, ""} -> ""
          {_party, description} -> description
        end
      )
      |> assign(:navigate, ~p"/sprzedazowe/#{invoice.id}")

    ~H"<.render_cell party={@party} navigate={@navigate} description={@description} column={@column} />"
  end

  defp render_cell(%{navigate: nil, party: _, description: _, column: "party"} = assigns) do
    ~H"""
    <.render_cell party={@party} description={@description} column={@column} />
    """
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
    # Use existing atoms to avoid atom exhaustion
    value = get_in(invoicing_entry, [Access.key!(String.to_existing_atom(column))])

    assigns = assign(assigns, :value, value)

    ~H"""
    {@value}
    """
  end

  attr :group, TransactionGroup, required: true
  attr :columns, :list, required: true

  defp group_row(assigns) do
    ~H"""
    <!-- Group header row - styled like a regular transaction -->
    <tr
      id={"#{@group.id}-row"}
      class="cursor-pointer"
      phx-click={
        JS.toggle_class("rotate-90", to: "#chevron-#{@group.id}")
        |> JS.toggle(
          to: "[data-group-transactions='#{@group.id}']",
          in: {"ease-out duration-300", "opacity-0", "opacity-100"},
          out: {"ease-in duration-200", "opacity-100", "opacity-0"}
        )
      }
    >
      <td
        :for={column <- @columns}
        class={[
          "transition-all duration-500 bg-white py-2",
          column == "party" && "rounded-l-md pl-5 pr-5 text-ellipsis max-xl:max-w-72",
          String.ends_with?(column, "date") && "font-light",
          column == "amount" && "rounded-r-md",
          column == "amount" && "text-orangeText !bg-orangeBg"
        ]}
      >
        <div
          data-overflow-hider-id={@group.id}
          class={[
            column == "party" && "max-w-[50vw]",
            column != "amount" && "w-full whitespace-nowrap overflow-hidden overflow-ellipsis"
          ]}
        >
          <%= if column == "party" do %>
            <span>{@group.party}</span>
            <span
              id={"chevron-#{@group.id}"}
              class="inline-flex items-center justify-center w-4 h-4 mx-1 transition-transform"
            >
              <.icon name="hero-chevron-right" class="w-3 h-3" />
            </span>
            <span class="text-darkGrey opacity-50 text-sm">
              {pluralize_transaction_count(@group.count)}
            </span>
          <% else %>
            <.render_group_cell column={column} group={@group} columns={@columns} />
          <% end %>
        </div>
      </td>
    </tr>
    <!-- Group transaction rows (hidden by default) -->
    <%= for transaction <- @group.transactions do %>
      <tr data-group-transactions={@group.id} class="hidden">
        <td
          :for={column <- @columns}
          class={[
            "transition-all duration-500 bg-white py-2",
            column == "party" && "rounded-l-md pl-5 pr-5 text-ellipsis max-xl:max-w-72",
            String.ends_with?(column, "date") && "font-light",
            column == "amount" && "rounded-r-md",
            column == "amount" &&
              Decimal.gte?(transaction.transaction_amount, 0) &&
              "text-blueText !bg-blueBg",
            column == "amount" &&
              Decimal.lt?(transaction.transaction_amount, 0) &&
              "text-orangeText !bg-orangeBg"
          ]}
        >
          <div
            data-overflow-hider-id={transaction.id}
            class={[
              column == "party" && "max-w-[50vw]",
              column != "amount" && "w-full whitespace-nowrap overflow-hidden overflow-ellipsis"
            ]}
          >
            <%= if column == "party" do %>
              <div class="flex items-center gap-2">
                <.icon name="hero-arrow-turn-down-right" class="w-3 h-3 text-darkGrey opacity-50" />
                <.render_cell column={column} invoicing_entry={transaction} />
              </div>
            <% else %>
              <.render_cell column={column} invoicing_entry={transaction} />
            <% end %>
          </div>
        </td>
      </tr>
    <% end %>
    """
  end

  defp render_group_cell(%{column: "amount"} = assigns) do
    ~H"""
    <div class="text-right pr-5 py-2 relative">
      {Money.new(@group.currency, @group.total)}
    </div>
    """
  end

  defp render_group_cell(%{column: column, group: _group} = assigns)
       when column in ["issue_or_value_date", "value_date", "due_or_booking_date", "booking_date"] do
    ~H"""
    {Date.to_iso8601(@group.date)}
    """
  end

  defp render_group_cell(%{column: column, group: _group} = assigns) when column in ["issue_date", "due_date"] do
    ~H"""
    """
  end

  defp render_group_cell(%{column: "status"} = assigns) do
    # Check if we're in unmatched filter by checking columns
    assigns = assign(assigns, :is_unmatched, "status" in assigns.columns)

    ~H"""
    <%= if @is_unmatched do %>
      <div class="flex flex-row gap-2 w-32 overflow-hidden">
        <div class={[
          "text-xs h-6",
          "flex flex-row justify-center items-center py-2 px-2 rounded-md",
          "transition-all duration-500",
          "w-10 bg-redBg text-redText"
        ]}>
          <.icon name="hero-credit-card-mini" class="h-4 w-4" />
        </div>
        <button
          id={"#{@group.id}-button"}
          phx-click={
            JS.push("toggle-skip-invoicing-group",
              value: %{group_id: @group.id, transaction_ids: Enum.map(@group.transactions, & &1.id)}
            )
          }
          class={[
            "transition-all duration-500 cursor-pointer",
            "w-20",
            "h-6 uppercase text-xs text-darkGrey bg-greyButtonBg rounded-md"
          ]}
        >
          Pomiń
        </button>
      </div>
    <% end %>
    """
  end

  defp render_group_cell(assigns) do
    ~H"""
    """
  end

  defp pluralize_transaction_count(1), do: "1 transakcja"
  defp pluralize_transaction_count(n) when n in 2..4, do: "#{n} transakcje"
  defp pluralize_transaction_count(n), do: "#{n} transakcji"
end
