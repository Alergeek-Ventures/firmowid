defmodule FirmowidWeb.Invoicing.Components.EntriesTable do
  @moduledoc false
  use FirmowidWeb, :html

  import FirmowidWeb.DesignSystem.Components.CoreComponents, except: [button: 1]
  import FirmowidWeb.DesignSystem.Components.InvoicingBadges
  import FirmowidWeb.DesignSystem.Components.Link
  import FirmowidWeb.Invoicing.Components.StatusButton
  import Phoenix.Component, except: [link: 1]

  alias Firmowid.Ash.Finances.Transaction
  alias Firmowid.Ash.Invoicing.CostInvoice
  alias Firmowid.Ash.Invoicing.SalesInvoice
  alias Firmowid.Ash.Invoicing.TransactionGroup
  alias Firmowid.Ash.Ksef
  alias Firmowid.Ash.Ksef.SubmissionInfo
  alias FirmowidWeb.Infrastructure.Utilities.PolishQuantity
  alias FirmowidWeb.Invoicing.Utilities.BankBadges
  alias FirmowidWeb.Invoicing.Utilities.Navigation

  attr :invoicing_entries, :list, required: true
  attr :mode, :atom, required: true
  attr :return_to, :string, default: nil

  @default_columns ["party", "issue_or_value_date", "due_or_booking_date", "status", "amount"]

  @invoice_columns ["party", "issue_date", "due_date", "status", "amount"]
  @transaction_columns ["party", "value_date", "booking_date", "status", "amount"]

  @column_labels [
    party: "Kontrahent",
    issue_date: "Wystawiono",
    value_date: "Wykonano",
    issue_or_value_date: "Wystawiono / Wykonano",
    due_date: "Termin płatności",
    booking_date: "Zaksięgowano",
    due_or_booking_date: "Termin płatności / Zaksięgowano",
    status: "Status",
    amount: "Kwota"
  ]

  # Using map pattern match to avoid Dialyzer false positive about
  # LiveView internal assign fields (:__given__, etc.)
  defp get_sales_invoice_buyer_name(%{__struct__: SalesInvoice} = invoice) do
    invoice.buyer_display_name_label || ""
  end

  def table(%{invoicing_entries: []} = assigns) do
    ~H"""
    <div class="flex min-h-[300px] flex-col items-center justify-center gap-4">
      <.icon name="hero-cloud-arrow-up" class="text-greenText size-16" />
      <p class="text-center text-black">
        Brak transakcji i dokumentów dla wybranej daty
      </p>
      <p class="text-darkGrey text-center">
        Przeciągnij pliki, aby je wgrać
      </p>
    </div>
    """
  end

  def table(assigns) do
    assigns =
      assigns
      |> assign_new(:return_to, fn -> nil end)
      |> assign(
        :columns,
        case assigns.mode do
          :invoices -> @invoice_columns
          :transactions -> @transaction_columns
          _ -> @default_columns
        end
      )

    ~H"""
    <table
      id="invoicing-entries"
      class="-mt-8 table-fixed border-separate border-spacing-y-3"
    >
      <col
        :for={column <- @columns}
        class={[
          case column do
            "issue_date" -> "w-36"
            "booking_date" -> "w-44"
            "issue_or_value_date" -> "w-36"
            "due_date" -> "w-44"
            "value_date" -> "w-36"
            "due_or_booking_date" -> "w-44"
            "status" -> "w-40"
            "amount" -> "w-44"
            _ -> ""
          end
        ]}
      />
      <thead class="bg-lightGreyBg sticky top-[130px] z-1">
        <tr>
          <th
            :for={column <- @columns}
            id={"header-#{column}"}
            phx-hook="ScrollStyle"
            data-classes="border-b-4 border-solid border-darkGrey/40"
            data-scroll-offset="90"
            class={[
              "text-darkGrey h-[60px] py-2 text-left align-bottom text-xs font-normal uppercase",
              column == "party" && "pl-5"
            ]}
          >
            <.column_label column={column} />
          </th>
        </tr>
      </thead>
      <tbody>
        <%= for entry <- @invoicing_entries do %>
          <%= case entry do %>
            <% %TransactionGroup{} = group -> %>
              <.group_row group={group} columns={@columns} return_to={@return_to} />
            <% invoicing_entry -> %>
              <.table_row
                columns={@columns}
                invoicing_entry={invoicing_entry}
                return_to={@return_to}
              />
          <% end %>
        <% end %>
      </tbody>
    </table>
    """
  end

  defp column_label(assigns) do
    assigns =
      assign(
        assigns,
        :label,
        Keyword.get(@column_labels, String.to_existing_atom(assigns.column))
      )

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
      assigns
      |> assign(
        :amount,
        case assigns.invoicing_entry do
          %Transaction{} -> Money.to_decimal(assigns.invoicing_entry.amount)
          %CostInvoice{} -> Money.to_decimal(assigns.invoicing_entry.effective_amount)
          %SalesInvoice{} -> Money.to_decimal(assigns.invoicing_entry.effective_amount)
        end
      )
      |> assign(
        :is_draft,
        case assigns.invoicing_entry do
          %SalesInvoice{} = invoice -> is_nil(invoice.invoice_number)
          _ -> false
        end
      )
      |> assign(:is_income, income_for_entry(assigns.invoicing_entry))

    ~H"""
    <tr id={"#{@invoicing_entry.id}-row"}>
      <td
        :for={column <- @columns}
        class={
          [
            "bg-white py-2 transition-all duration-500",
            column == "party" && "rounded-l-md px-5 text-ellipsis max-xl:max-w-72",
            String.ends_with?(column, "date") && "font-light",
            column == "amount" && "rounded-r-md",
            column == "amount" && @is_income && "bg-blueBg! text-blueText",
            column == "amount" && !@is_income && "bg-orangeBg! text-orangeText",
            # Draft invoices get a dotted border
            @is_draft && column == "party" && "border-darkGrey/50 border-y-2 border-l-2 border-dashed",
            @is_draft && column == "amount" &&
              "border-darkGrey/50 border-y-2 border-r-2 border-dashed",
            @is_draft && column not in ["party", "amount"] &&
              "border-darkGrey/50 border-y-2 border-dashed"
          ]
        }
      >
        <div class={
          [
            # this column has no defined width, so we limit the worst offenders "manually"
            column == "party" && "max-w-[50vw]",
            # required to display the "dot freshness" indicator that is rendered outside of the cell
            column != "amount" && "w-full truncate"
          ]
        }>
          <.render_cell column={column} invoicing_entry={@invoicing_entry} return_to={@return_to} />
        </div>
      </td>
    </tr>
    """
  end

  # amount is differently rendered (has a background color that fills the cell)
  defp render_cell(%{column: "amount", invoicing_entry: %Transaction{} = transaction} = assigns) do
    amount = transaction.signed_amount

    assigns = assign(assigns, :amount, amount)

    ~H"""
    <div class="relative py-2 pr-5 text-right">
      {@amount}
    </div>
    """
  end

  defp render_cell(%{column: "amount", invoicing_entry: %SalesInvoice{} = invoice} = assigns) do
    amount = invoice.effective_amount

    assigns = assign(assigns, :amount, amount)

    ~H"""
    <div class="relative py-2 pr-5 text-right">
      {@amount}
    </div>
    """
  end

  defp render_cell(%{column: "amount", invoicing_entry: %CostInvoice{} = invoice} = assigns) do
    is_fresh =
      invoice.transactions == [] &&
        DateTime.after?(
          invoice.inserted_at,
          DateTime.shift(DateTime.utc_now(), minute: -2)
        )

    amount = invoice.effective_amount

    assigns =
      assigns
      |> assign(:is_fresh, is_fresh)
      |> assign(:amount, amount)

    ~H"""
    <div class="relative py-2 pr-5 text-right">
      {@amount}

      <%= if @is_fresh do %>
        <span
          id={"amount-fresh-#{@invoicing_entry.id}"}
          phx-hook="Tippy"
          data-tippy-delay="10"
          data-tippy-content="Ten dokument właśnie został dodany!"
          class="absolute top-[-10px] right-[-4px] flex size-3"
        >
          <span class="bg-blueText absolute inline-flex size-full animate-ping rounded-full opacity-75"></span>
          <span class="bg-blueText relative inline-flex size-3 rounded-full"></span>
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
      class="flex w-32 flex-row gap-2 overflow-hidden"
    >
      <div
        id={"#{@invoicing_entry.id}-label"}
        class="bg-greenBg text-greenText flex h-6 w-20 flex-row items-center justify-center rounded-md p-2 text-xs transition-all duration-500"
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
          class="size-4"
        />
      </div>
      <.status_button
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
        icon="hero-arrow-uturn-left-micro"
        class="transition-all duration-500"
      />
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
      class="flex w-32 flex-row gap-2 overflow-hidden"
    >
      <div class="text-darkGrey flex h-6 w-full flex-row items-center justify-center rounded-md p-2 text-xs">
        <div class="font-normal uppercase">Wysyłanie...</div>
        <.icon name="hero-arrow-path" class="size-4 animate-spin" />
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
      class="flex w-32 flex-row gap-2 overflow-hidden"
    >
      <div class="animate-error-pulse flex h-6 w-full flex-row items-center justify-center rounded-md p-2 text-xs">
        <div class="font-normal uppercase">Błąd wysyłania</div>
        <.icon name="hero-exclamation-triangle-mini" class="size-4" />
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
      class="flex w-32 flex-row gap-2 overflow-hidden"
    >
      <div class={[
        "bg-greenBg text-greenText flex h-6 w-full flex-row items-center justify-between rounded-md p-2 text-xs transition-all duration-500"
      ]}>
        <div class="font-normal uppercase">Komplet</div>
        <.icon name="hero-check-micro" class="size-5" />
      </div>
    </div>
    """
  end

  defp render_cell(%{column: "status", status: "draft"} = assigns) do
    ~H"""
    <div
      id={"status-#{@invoicing_entry.id}"}
      phx-hook="Tippy"
      data-tippy-delay="1000"
      data-tippy-content="To szkic faktury — dokument nie został jeszcze wystawiony."
      class="flex w-32 flex-row gap-2 overflow-hidden"
    >
      <div class="border-greyButtonBg text-darkGrey flex h-6 w-full flex-row items-center justify-between rounded-md border-2 bg-white p-2 text-xs uppercase transition-all duration-500">
        <p>Szkic</p>
        <.icon name="hero-pencil-square-solid" class="size-4" />
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
      class="flex w-32 flex-row gap-2 overflow-hidden"
    >
      <div
        id={"#{@invoicing_entry.id}-label"}
        class={[
          "flex h-6 w-10 flex-row items-center justify-center rounded-md p-2 text-xs transition-all duration-500",
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
          class="size-4"
        />
      </div>
      <.status_button
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
        label="Pomiń"
        class="transition-all duration-500"
      />
    </div>
    """
  end

  defp render_cell(%{column: "status"} = assigns) do
    assigns = assign(assigns, :status, status_for_entry(assigns.invoicing_entry))

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

  defp render_cell(%{invoicing_entry: %CostInvoice{} = invoice, column: "due_date"} = assigns) do
    assigns = assign(assigns, :value, invoice.effective_due_date)

    ~H"""
    {@value}
    """
  end

  defp render_cell(%{invoicing_entry: %SalesInvoice{} = invoice, column: "due_date"} = assigns) do
    assigns = assign(assigns, :value, invoice.effective_due_date)

    ~H"""
    {@value}
    """
  end

  defp render_cell(%{invoicing_entry: %CostInvoice{}, column: "issue_or_value_date"} = assigns),
    do: assigns |> assign(:column, "issue_date") |> render_cell()

  defp render_cell(%{invoicing_entry: %SalesInvoice{}, column: "issue_or_value_date"} = assigns),
    do: assigns |> assign(:column, "issue_date") |> render_cell()

  defp render_cell(%{invoicing_entry: %Transaction{} = transaction, column: "party"} = assigns) do
    party = transaction.counterparty_display_name

    assigns =
      assigns
      |> assign(:party, party)
      |> assign(:bank_badge, Map.get(transaction, :bank_account))
      |> assign(:invoice_source_badge_variant, nil)
      |> assign(:description, transaction.remittance_information_unstructured)
      |> assign(
        :navigate,
        Navigation.transaction_show_path(transaction, Map.get(assigns, :return_to))
      )

    ~H"<.render_cell
  party={@party}
  navigate={@navigate}
  description={@description}
  bank_badge={@bank_badge}
  invoice_source_badge_variant={@invoice_source_badge_variant}
  column={@column}
/>"
  end

  defp render_cell(%{invoicing_entry: %CostInvoice{} = invoice, column: "party"} = assigns) do
    assigns =
      assigns
      |> assign(:party, invoice.effective_seller_display_name || invoice.seller)
      |> assign(:bank_badge, nil)
      |> assign(:invoice_source_badge_variant, invoice_source_badge_variant(invoice))
      |> assign(:description, invoice.description)
      |> assign(
        :navigate,
        Navigation.cost_invoice_show_path(invoice, Map.get(assigns, :return_to))
      )

    ~H"<.render_cell
  party={@party}
  navigate={@navigate}
  description={@description}
  bank_badge={@bank_badge}
  invoice_source_badge_variant={@invoice_source_badge_variant}
  column={@column}
/>"
  end

  defp render_cell(%{invoicing_entry: %SalesInvoice{} = invoice, column: "party"} = assigns) do
    party = get_sales_invoice_buyer_name(invoice)

    assigns =
      assigns
      |> assign(:party, party)
      |> assign(:bank_badge, nil)
      |> assign(:invoice_source_badge_variant, invoice_source_badge_variant(invoice))
      |> assign(
        :description,
        case {
          party,
          Enum.map_join(invoice.sales_invoice_items, ", ", & &1.name)
        } do
          {"", ""} -> "szkic faktury sprzedażowej"
          {_party, ""} -> ""
          {_party, description} -> description
        end
      )
      |> assign(
        :navigate,
        Navigation.sales_invoice_show_path(invoice, Map.get(assigns, :return_to))
      )

    ~H"<.render_cell
  party={@party}
  navigate={@navigate}
  description={@description}
  bank_badge={@bank_badge}
  invoice_source_badge_variant={@invoice_source_badge_variant}
  column={@column}
/>"
  end

  defp render_cell(
         %{navigate: nil, party: _, description: _, bank_badge: _, invoice_source_badge_variant: _, column: "party"} =
           assigns
       ) do
    ~H"""
    <.party_cell_content
      party={@party}
      description={@description}
      bank_badge={@bank_badge}
      invoice_source_badge_variant={@invoice_source_badge_variant}
    />
    """
  end

  defp render_cell(
         %{navigate: _, party: _, description: _, bank_badge: _, invoice_source_badge_variant: _, column: "party"} =
           assigns
       ) do
    ~H"""
    <.link kind="unstyled" navigate={@navigate} class="hover:underline">
      <.party_cell_content
        party={@party}
        description={@description}
        bank_badge={@bank_badge}
        invoice_source_badge_variant={@invoice_source_badge_variant}
      />
    </.link>
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

  defp status_for_entry(%{skip_invoicing: true}), do: "skipped"

  defp status_for_entry(%CostInvoice{transactions: []}), do: "unmatched"
  defp status_for_entry(%CostInvoice{}), do: "matched"

  defp status_for_entry(%SalesInvoice{} = invoice) do
    submission_info = Ksef.get_submission_info(invoice)

    cond do
      is_nil(invoice.invoice_number) -> "draft"
      SubmissionInfo.submitting?(submission_info) -> "ksef_sending"
      SubmissionInfo.failed?(submission_info) -> "ksef_failed"
      true -> if invoice.transactions == [], do: "unmatched", else: "matched"
    end
  end

  defp status_for_entry(%Transaction{} = t) do
    if t.cost_invoices != [] or t.sales_invoices != [],
      do: "matched",
      else: "unmatched"
  end

  defp status_for_entry(_), do: "unmatched"

  attr :group, TransactionGroup, required: true
  attr :columns, :list, required: true
  attr :return_to, :string, default: nil

  defp group_row(assigns) do
    assigns = assign(assigns, :bank_badge, bank_badge_for_group(assigns.group))

    ~H"""
    <tr
      id={"#{@group.id}-row"}
      class="cursor-pointer duration-200"
      phx-click={
        JS.toggle_class("rotate-90", to: "#chevron-#{@group.id}")
        |> JS.toggle_class("opacity-50", to: "##{@group.id}-row")
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
          "bg-white py-2 transition-all duration-500",
          column == "party" && "rounded-l-md px-5 text-ellipsis max-xl:max-w-72",
          String.ends_with?(column, "date") && "font-light",
          column == "amount" && "rounded-r-md",
          column == "amount" && Decimal.gte?(@group.total, 0) && "bg-blueBg! text-blueText",
          column == "amount" && Decimal.lt?(@group.total, 0) && "bg-orangeBg! text-orangeText"
        ]}
      >
        <div class={[
          column == "party" && "max-w-[50vw]",
          column != "amount" && "w-full truncate"
        ]}>
          <%= if column == "party" do %>
            <div class="flex min-w-0 items-center gap-2.5">
              <.bank_badge bank={@bank_badge} size="mini" class="shrink-0" />
              <span class="min-w-0 truncate">
                <span>{@group.party}</span>
                <span
                  id={"chevron-#{@group.id}"}
                  class="mx-1 inline-flex size-4 items-center justify-center transition-transform"
                >
                  <.icon name="hero-chevron-right" class="size-3" />
                </span>
                <span class="text-darkGrey text-sm opacity-50">
                  {pluralize_transaction_count(@group.count)}
                </span>
              </span>
            </div>
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
            "bg-white py-2 transition-all duration-500",
            column == "party" && "rounded-l-md px-5 text-ellipsis max-xl:max-w-72",
            String.ends_with?(column, "date") && "font-light",
            column == "amount" && "rounded-r-md",
            column == "amount" && transaction.direction == :income &&
              "bg-blueBg! text-blueText",
            column == "amount" && transaction.direction != :income &&
              "bg-orangeBg! text-orangeText"
          ]}
        >
          <div class={[
            column == "party" && "max-w-[50vw]",
            column != "amount" && "w-full truncate"
          ]}>
            <%= if column == "party" do %>
              <div class="flex items-center gap-2">
                <.icon name="hero-arrow-turn-down-right" class="text-darkGrey size-3 opacity-50" />
                <.render_cell
                  column={column}
                  invoicing_entry={transaction}
                  return_to={@return_to}
                />
              </div>
            <% else %>
              <.render_cell
                column={column}
                invoicing_entry={transaction}
                return_to={@return_to}
              />
            <% end %>
          </div>
        </td>
      </tr>
    <% end %>
    """
  end

  defp render_group_cell(%{column: "amount"} = assigns) do
    ~H"""
    <div class="relative py-2 pr-5 text-right">
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
    assigns =
      assigns
      |> assign(:is_unmatched, "status" in assigns.columns)
      |> assign(:all_skipped, Enum.all?(assigns.group.transactions, & &1.skip_invoicing))

    ~H"""
    <%= cond do %>
      <% not @is_unmatched -> %>
      <% @all_skipped -> %>
        <div class="flex w-32 flex-row gap-2 overflow-hidden">
          <div
            id={"#{@group.id}-label"}
            class="bg-greenBg text-greenText flex h-6 w-20 flex-row items-center justify-center rounded-md p-2 text-xs transition-all duration-500"
          >
            <.icon name="hero-credit-card-mini" class="size-4" />
          </div>
          <.status_button
            id={"#{@group.id}-button"}
            phx-click={
              JS.push("toggle-skip-invoicing-group",
                value: %{transaction_ids: Enum.map(@group.transactions, & &1.id)}
              )
            }
            icon="hero-arrow-uturn-left-micro"
            class="transition-all duration-500"
          />
        </div>
      <% true -> %>
        <div class="flex w-32 flex-row gap-2 overflow-hidden">
          <div class="bg-redBg text-redText flex h-6 w-10 flex-row items-center justify-center rounded-md p-2 text-xs transition-all duration-500">
            <.icon name="hero-credit-card-mini" class="size-4" />
          </div>
          <.status_button
            id={"#{@group.id}-button"}
            phx-click={
              JS.push("toggle-skip-invoicing-group",
                value: %{transaction_ids: Enum.map(@group.transactions, & &1.id)}
              )
            }
            label="Pomiń"
            class="transition-all duration-500"
          />
        </div>
    <% end %>
    """
  end

  defp render_group_cell(assigns) do
    ~H"""
    """
  end

  attr :party, :string, default: nil
  attr :description, :string, default: nil
  attr :bank_badge, :any, default: nil
  attr :invoice_source_badge_variant, :string, default: nil

  defp party_cell_content(assigns) do
    ~H"""
    <div class="flex min-w-0 items-center gap-2.5">
      <.bank_badge :if={@bank_badge} institution={@bank_badge} size="mini" class="shrink-0" />
      <.invoice_source_badge
        :if={@invoice_source_badge_variant}
        variant={@invoice_source_badge_variant}
        size="small"
        class="shrink-0"
      />
      <span class="min-w-0 truncate">
        {@party}
        <span :if={@description not in [nil, ""]} class="text-darkGrey text-sm opacity-50">
          {@description}
        </span>
      </span>
    </div>
    """
  end

  defp pluralize_transaction_count(count) do
    PolishQuantity.quantity(count, "transakcja", "transakcje", "transakcji")
  end

  defp bank_badge_for_group(%TransactionGroup{transactions: transactions}) do
    case transactions |> Enum.map(&BankBadges.badge_for_transaction/1) |> Enum.uniq() do
      [bank_badge] -> bank_badge
      _ -> "Default"
    end
  end

  defp income_for_entry(%Transaction{} = transaction), do: transaction.direction == :income

  defp income_for_entry(%CostInvoice{effective_amount: %Money{} = amount}), do: Money.positive?(amount)

  defp income_for_entry(%CostInvoice{amount: amount}), do: Money.positive?(amount)

  defp income_for_entry(%SalesInvoice{effective_amount: %Money{} = amount}), do: Money.positive?(amount)

  defp income_for_entry(%SalesInvoice{amount: amount}), do: Money.positive?(amount)

  defp income_for_entry(%{amount: amount}), do: Money.positive?(amount)
end
