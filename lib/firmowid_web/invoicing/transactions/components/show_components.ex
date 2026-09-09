defmodule FirmowidWeb.Invoicing.Transactions.Components.ShowComponents do
  @moduledoc """
  Presentational components for the transaction details LiveView.
  """

  use FirmowidWeb, :html

  import FirmowidWeb.DesignSystem.Components.Button
  import FirmowidWeb.DesignSystem.Components.CoreComponents
  import FirmowidWeb.DesignSystem.Components.InvoicingBadges
  import FirmowidWeb.DesignSystem.Components.Link
  import FirmowidWeb.Invoicing.Components.StatusButton
  import Phoenix.Component, except: [link: 1]

  alias Firmowid.Ash.Assistant.InvoiceMatching
  alias Firmowid.Ash.Finances.Transaction
  alias Firmowid.Ash.Invoicing.CostInvoice
  alias Firmowid.Ash.Invoicing.SalesInvoice
  alias FirmowidWeb.Invoicing.Components.InvoiceAssistant
  alias FirmowidWeb.Invoicing.Components.InvoiceDetails
  alias FirmowidWeb.Invoicing.Utilities.Navigation

  @transaction_suggested_messages [
    "Ta transakcja opłaciła kilka faktur z poprzedniego miesiąca",
    "To był przelew zbiorczy za kilka dokumentów",
    "Na fakturach kontrahent może występować pod inną nazwą"
  ]

  attr :transaction, Transaction, required: true
  attr :return_to, :string, default: nil

  def header(assigns) do
    ~H"""
    <header class={header_styles(@transaction)}>
      <.back
        navigate={@return_to || default_return_path(@transaction)}
        icon_only
      />

      <div class="flex min-w-0 flex-col gap-2">
        <h1 class="truncate text-lg/tight font-medium lg:text-2xl">
          {counterparty_name(@transaction)}
        </h1>
        <h2 class="text-darkGrey line-clamp-2">{transaction_summary(@transaction)}</h2>
      </div>

      <div class="ml-auto flex shrink-0 items-center gap-4">
        <div class="text-right">
          <p class="text-darkGrey text-sm/snug">{header_account_label(@transaction)}</p>
          <p class="text-darkGrey text-sm/snug">{bank_name(@transaction)}</p>
        </div>
        <.bank_badge institution={Map.get(@transaction, :bank_account)} size="full" />
      </div>
    </header>
    """
  end

  attr :transaction, Transaction, required: true

  def details_sidebar(assigns) do
    {incoming, amount} = transaction_presentation(assigns.transaction)
    assigns = assign(assigns, incoming: incoming, amount: amount)

    ~H"""
    <InvoiceDetails.aside>
      <div class="flex h-full flex-col gap-8">
        <section class="space-y-3">
          <h2 class="text-lg/tight font-medium">Szczegóły transakcji</h2>

          <InvoiceDetails.invoice_metadata>
            <InvoiceDetails.invoice_metadata_piece
              label="Wykonano"
              value={@transaction.value_date}
            />
            <InvoiceDetails.invoice_metadata_piece
              label="Zaksięgowano"
              value={@transaction.booking_date}
            />
            <InvoiceDetails.invoice_metadata_piece
              label="Opis przelewu"
              value={present(@transaction.remittance_information_unstructured)}
              multiline
            />
          </InvoiceDetails.invoice_metadata>
        </section>

        <section class="space-y-3">
          <h2 class="text-lg/tight font-medium">Strony transakcji</h2>

          <InvoiceDetails.invoice_metadata>
            <InvoiceDetails.invoice_metadata_piece
              label="Nadawca"
              value={present(@transaction.debtor_name)}
            />
            <InvoiceDetails.invoice_metadata_piece
              label="Konto nadawcy"
              value={present(@transaction.debtor_account)}
            />
            <InvoiceDetails.invoice_metadata_piece
              label="Odbiorca"
              value={present(@transaction.creditor_name)}
            />
            <InvoiceDetails.invoice_metadata_piece
              label="Konto odbiorcy"
              value={present(@transaction.creditor_account)}
            />
          </InvoiceDetails.invoice_metadata>
        </section>

        <div class="pt-2">
          <.transaction_amount_summary
            incoming={@incoming}
            amount={@amount}
          />
        </div>
      </div>
    </InvoiceDetails.aside>
    """
  end

  attr :transaction, Transaction, required: true
  attr :current_user, :map, required: true
  attr :scope, :map, required: true
  attr :return_to, :string, default: nil

  def assistant_state(assigns) do
    ~H"""
    <.live_component
      module={InvoiceAssistant}
      id="invoice-assistant"
      entry_context={InvoiceMatching.entry_context_for_transaction(@transaction)}
      assistant_config={assistant_config(@transaction)}
      current_user={@current_user}
      scope={@scope}
      return_path={assistant_return_path(@transaction, @return_to)}
      close_target="#transaction-show"
    />
    """
  end

  attr :transaction, Transaction, required: true
  attr :return_to, :string, default: nil

  def linked_state(assigns) do
    assigns =
      assign(assigns, :cards, linked_invoice_cards(assigns.transaction, assigns.return_to))

    ~H"""
    <section class="space-y-8">
      <div class="flex flex-row items-center justify-between">
        <p class="text-lg/tight font-medium">Dopasowanie</p>

        <div class="flex flex-row gap-2">
          <div class="flex flex-row items-center self-stretch rounded-md bg-green-200 px-[14.5px]">
            <p class="text-sm/tight font-medium text-green-700">Komplet</p>
          </div>
          <.status_button phx-click="unlink_all" icon="hero-arrow-uturn-left-micro" />
        </div>
      </div>

      <div class="flex flex-col gap-4">
        <.linked_invoice_card :for={card <- @cards} card={card} />
      </div>

      <div class="space-y-6">
        <h3 class="leading-tight font-medium">Co jeszcze możesz zrobić?</h3>

        <div class="grid grid-cols-[1fr_8rem] gap-6 lg:gap-x-10">
          <div class="col-span-full grid grid-cols-subgrid">
            <p class="text-grey-700 self-center text-sm/snug text-balance">
              Poproś Firmowida o pomoc w znalezieniu kolejnych faktur dla tej transakcji.
            </p>

            <.button
              phx-click="show_chat"
              class="w-full"
              variant="primary"
              accent={assistant_accent(@transaction)}
              size="small"
            >
              Zapytaj
            </.button>
          </div>
        </div>
      </div>
    </section>
    """
  end

  attr :transaction, Transaction, required: true
  attr :can_write, :boolean, default: true

  def empty_state(assigns) do
    ~H"""
    <div class="flex flex-col gap-18">
      <div class="flex flex-col items-center gap-4 px-4 pt-8 pb-6">
        <Lucideicons.file_question_mark class="size-12" />

        <div class="space-y-2 text-center">
          <h3 class="text-lg/tight font-medium">Brak rekomendacji</h3>
          <p class="max-w-96 text-balance">
            Firmowid nie znalazł jeszcze żadnych faktur, które potencjalnie pasowałyby do tej transakcji.
          </p>
        </div>

        <.button
          phx-click="show_chat"
          class="mt-2"
          variant="primary"
          accent={assistant_accent(@transaction)}
          size="small"
        >
          Poproś Firmowida o pomoc
        </.button>
      </div>

      <div :if={@can_write} class="space-y-6">
        <h3 class="leading-tight font-medium">Co jeszcze możesz zrobić?</h3>

        <div class="grid grid-cols-[1fr_8rem] gap-6 lg:gap-x-10">
          <div class="col-span-full grid grid-cols-subgrid items-center">
            <p class="text-grey-700 text-sm/snug text-balance">
              {skip_transaction_copy(@transaction)}
            </p>

            <div class="flex h-8 w-full flex-row items-start gap-2">
              <div class="bg-grey-200 text-grey-700 flex items-center justify-center rounded-md p-2">
                <.icon name="hero-document-text-solid" class="size-4" />
              </div>

              <.button
                phx-click="toggle-invoicing"
                class="size-full"
                variant="secondary"
                size="small"
              >
                {skip_transaction_button_label(@transaction)}
              </.button>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :card, :map, required: true

  def linked_invoice_card(assigns) do
    ~H"""
    <div class="flex flex-col gap-4 rounded-md bg-[#D0E6CE66] p-4">
      <div :if={@card.badge_variant} class="flex flex-row items-center justify-between">
        <div class="space-y-1">
          <p class="text-grey-700 text-sm/snug">{@card.type_label}</p>
          <.link kind="unstyled" navigate={@card.navigate} class="leading-snug hover:underline">
            {@card.number}
          </.link>
        </div>

        <.invoice_source_badge variant={@card.badge_variant} size="small" />
      </div>

      <div class="grid grid-flow-col grid-cols-[2fr_1fr_1fr] grid-rows-2 gap-x-4 gap-y-6">
        <div :if={is_nil(@card.badge_variant)} class="space-y-1">
          <p class="text-grey-700 text-sm/snug">{@card.type_label}</p>
          <.link kind="unstyled" navigate={@card.navigate} class="leading-snug hover:underline">
            {@card.number}
          </.link>
        </div>

        <%= for {label, val} <- @card.metadata do %>
          <div class="space-y-1">
            <p class="text-grey-700 text-sm/snug">{label}</p>
            <p class="leading-snug">{val}</p>
          </div>
        <% end %>

        <div class="row-span-2 flex items-end justify-end text-right">
          <p class="text-lg/snug text-green-700">{@card.amount}</p>
        </div>
      </div>
    </div>
    """
  end

  attr :can_write, :boolean, default: true

  def transaction_skipped_view(assigns) do
    ~H"""
    <div class="space-y-4 pt-8">
      <div class="flex flex-row items-center justify-between">
        <p class="text-lg/tight font-medium">Transakcja pominięta</p>
        <div :if={@can_write} class="flex w-32 flex-row gap-2">
          <div class="flex flex-1 items-center justify-center rounded-md bg-green-200 px-2 text-green-700">
            <.icon name="hero-document-text-micro" class="size-4" />
          </div>
          <.status_button
            phx-click="toggle-invoicing"
            class="flex-1"
            icon="hero-arrow-uturn-left-micro"
          />
        </div>
      </div>

      <div class="bg-grey-100 flex flex-col gap-6 rounded p-6">
        <p class="text-base/snug">
          Transakcja została pominięta w dopasowywaniu. Przywróć ją, jeśli jednak chcesz połączyć ją z dokumentem.
        </p>
      </div>
    </div>
    """
  end

  attr :incoming, :boolean, required: true
  attr :amount, :any, required: true

  def transaction_amount_summary(assigns) do
    ~H"""
    <div class="flex flex-col items-end justify-between gap-2 pl-1">
      <label class="text-grey-700 text-sm/snug" for="transaction-amount">Kwota transakcji</label>
      <p
        id="transaction-amount"
        class={[
          "rounded bg-[#DEDEDE4C] px-4 py-2 text-lg/tight",
          @incoming && "text-turquoise-700",
          !@incoming && "text-orange-700"
        ]}
      >
        {@amount}
      </p>
    </div>
    """
  end

  defp header_styles(transaction) do
    [
      "flex flex-row items-center gap-4 px-4 py-7 lg:gap-8 lg:px-8",
      if(incoming?(transaction), do: "bg-turquoise-200", else: "bg-orange-200")
    ]
  end

  defp transaction_presentation(transaction) do
    {transaction.direction == :income, transaction.signed_amount}
  end

  defp counterparty_name(transaction) do
    transaction.counterparty_display_name
  end

  defp transaction_summary(transaction) do
    case transaction.remittance_information_unstructured do
      value when is_binary(value) and value != "" -> value
      _ -> internal_account_name(transaction)
    end
  end

  defp assistant_accent(transaction) do
    if incoming?(transaction), do: "turquoise", else: "orange"
  end

  defp assistant_config(%Transaction{} = transaction) do
    %{
      displayed_party_label: if(transaction.direction == :income, do: "Nadawca", else: "Odbiorca"),
      suggested_messages: @transaction_suggested_messages
    }
  end

  defp assistant_return_path(transaction, return_to) do
    return_to || Navigation.transaction_show_path(transaction)
  end

  defp skip_transaction_copy(%Transaction{skip_invoicing: true}) do
    "Ta transakcja jest pominięta w dopasowywaniu. Przywróć ją, jeśli jednak chcesz szukać dla niej faktury."
  end

  defp skip_transaction_copy(%Transaction{}) do
    "A może żadna faktura nie pasuje do tej transakcji? Pomiń jej szukanie. Firmowid oznaczy ją jako rozliczoną poza systemem."
  end

  defp skip_transaction_button_label(%Transaction{skip_invoicing: true}), do: "Przywróć"
  defp skip_transaction_button_label(%Transaction{}), do: "Pomiń"

  defp internal_account_name(transaction), do: bank_account_name(transaction)

  defp header_account_label(%Transaction{bank_account: %{name: name, iban: iban}})
       when is_binary(name) and name != "" and is_binary(iban) and iban != "" do
    "#{name} · #{iban}"
  end

  defp header_account_label(%Transaction{bank_account: %{iban: iban}}) when is_binary(iban) and iban != "" do
    iban
  end

  defp header_account_label(transaction), do: bank_account_name(transaction)

  defp bank_account_name(%Transaction{bank_account: %{name: name}}) when is_binary(name) and name != "", do: name

  defp bank_account_name(%Transaction{bank_account: %{iban: iban}}) when is_binary(iban) and iban != "", do: iban

  defp bank_account_name(_transaction), do: "Rachunek bankowy"

  defp bank_name(%Transaction{bank_account: %{institution_name: institution_name}}), do: present(institution_name)

  defp bank_name(_transaction), do: "—"

  defp incoming?(%Transaction{} = transaction), do: transaction.direction == :income

  defp linked_invoice_cards(transaction, return_to) do
    invoice_return_to = Navigation.transaction_show_path(transaction, return_to)

    Enum.map(transaction.sales_invoices, &sales_invoice_card(&1, invoice_return_to)) ++
      Enum.map(transaction.cost_invoices, &cost_invoice_card(&1, invoice_return_to))
  end

  defp sales_invoice_card(%SalesInvoice{} = invoice, return_to) do
    %{
      navigate: Navigation.sales_invoice_show_path(invoice, return_to),
      type_label: "Faktura sprzedażowa",
      number: present(invoice.invoice_number),
      amount: invoice.amount,
      badge_variant: nil,
      metadata: [
        {"Na fakturze", first_sales_item_name(invoice)},
        {"Kontrahent", present(invoice.buyer_display_name_label)},
        {"Wystawiono", invoice.issue_date}
      ]
    }
  end

  defp cost_invoice_card(%CostInvoice{} = invoice, return_to) do
    variant = invoice_source_badge_variant(invoice)

    %{
      navigate: Navigation.cost_invoice_show_path(invoice, return_to),
      type_label: "Faktura kosztowa",
      number: present(invoice.invoice_identifier),
      amount: invoice.effective_amount,
      badge_variant: variant,
      metadata: [
        {"Kontrahent", present(invoice.effective_seller_display_name)},
        {"Źródło", invoice_source_badge_label(variant)},
        {"Wystawiono", invoice.issue_date},
        {"Typ", "Faktura kosztowa"}
      ]
    }
  end

  defp present(nil), do: "—"
  defp present(""), do: "—"
  defp present(value), do: value

  defp first_sales_item_name(%SalesInvoice{sales_invoice_items: [%{name: name} | _]})
       when is_binary(name) and name != "" do
    name
  end

  defp first_sales_item_name(%SalesInvoice{}), do: "—"

  defp default_return_path(transaction) do
    Navigation.default_invoicing_path(transaction.booking_date)
  end
end
