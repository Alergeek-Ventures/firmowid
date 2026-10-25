defmodule FirmowidWeb.Invoicing.SalesInvoices.Components.InvoicePayment do
  @moduledoc """
  Renders and supports the payment section of the sales invoice form.

  Bank-account selection is kept here because it is shared by the creator and
  edit views.
  """
  use FirmowidWeb, :html

  import FirmowidUI.Components.Button
  import FirmowidUI.Components.Link
  import FirmowidWeb.DesignSystem.Components.CoreComponents
  import Phoenix.Component, except: [link: 1]

  alias Firmowid.Ash.Finances.BankAccount
  alias FirmowidWeb.Invoicing.SalesInvoices.Utilities.PaymentDateSuggestions

  @doc """
  Finds the account matching an IBAN and currency, falling back to the default
  account for the currency only when no IBAN is supplied.
  """
  @spec find_selected_bank_account([map()], String.t() | nil, String.t() | nil) :: map() | nil
  def find_selected_bank_account(bank_accounts, iban, currency) do
    canonical_iban = BankAccount.normalize_iban(iban)
    canonical_currency = BankAccount.normalize_currency(currency)

    case Enum.find(bank_accounts, fn account ->
           BankAccount.normalize_iban(account.iban) == canonical_iban and
             BankAccount.normalize_currency(account.currency) == canonical_currency
         end) do
      nil when canonical_iban in [nil, ""] ->
        Enum.find(bank_accounts, fn account ->
          account.is_default and
            BankAccount.normalize_currency(account.currency) == canonical_currency
        end)

      selected_bank_account ->
        selected_bank_account
    end
  end

  attr :invoice, :map, required: true
  attr :bank_accounts, :list, required: true
  attr :selected_bank_account, :map, required: false
  attr :payment_form, Phoenix.HTML.Form, required: true

  def invoice_payment(assigns) do
    ~H"""
    <div class="grid grid-cols-[min-content_min-content_1fr] items-center gap-x-5 gap-y-4">
      <label class="whitespace-nowrap text-grey-700" for={@payment_form[:sale_date].id}>
        Data sprzedaży
      </label>
      <.input
        field={@payment_form[:sale_date]}
        type="date"
        phx-debounce
        class="h-8 w-43"
      />
      <div class="flex flex-wrap items-center gap-2">
        <.button
          :for={{suggestion, label} <- PaymentDateSuggestions.sale_date_suggestions()}
          type="button"
          size="small"
          class="h-8"
          variant="secondary"
          phx-click="suggest_payment_date"
          phx-value-field="sale_date"
          phx-value-suggestion={suggestion}
        >
          {label}
        </.button>
      </div>

      <label class="whitespace-nowrap text-grey-700" for={@payment_form[:due_date].id}>
        Termin płatności
      </label>
      <.input
        field={@payment_form[:due_date]}
        type="date"
        phx-debounce
        class="h-8 w-43"
      />
      <div class="flex flex-wrap items-center gap-2">
        <.button
          :for={{suggestion, label} <- PaymentDateSuggestions.due_date_suggestions()}
          type="button"
          size="small"
          variant="secondary"
          class="h-8"
          phx-click="suggest_payment_date"
          phx-value-field="due_date"
          phx-value-suggestion={suggestion}
        >
          {label}
        </.button>
      </div>

      <label class="whitespace-nowrap text-grey-700" for={@payment_form[:payment_method].id}>
        Forma płatności
      </label>
      <.input
        field={@payment_form[:payment_method]}
        type="select"
        options={[
          {"Przelew", :transfer},
          {"Gotówka", :cash},
          {"Karta", :card}
        ]}
        container_class="w-fit"
      />
      <div></div>

      <div class={[
        "col-span-2 col-start-2 grid w-min min-w-[400px] grid-cols-[min-content_1fr] items-center gap-4 gap-y-2 rounded-lg border border-grey-200 p-4 transition-opacity duration-200",
        if(to_string(@payment_form[:payment_method].value) == "transfer",
          do: "opacity-100",
          else: "pointer-events-none opacity-0"
        )
      ]}>
        <.input
          :if={not is_nil(@selected_bank_account)}
          field={@payment_form[:seller_account_number]}
          type="hidden"
          class="hidden"
        />

        <%= if Enum.empty?(@bank_accounts) do %>
          <p class="col-span-2 text-sm/snug text-grey-700">
            Żadne z Twoich kont nie jest podpięte.
          </p>
          <.link
            kind="button"
            variant="secondary"
            size="small"
            class="inline-flex items-center gap-1.5"
            target="_blank"
            redirect={~p"/ustawienia/firma"}
          >
            <Lucideicons.plus class="inline-flex size-4" /> Podepnij konto
          </.link>
        <% end %>

        <%= if not Enum.empty?(@bank_accounts) and @selected_bank_account == nil do %>
          <p class="col-span-2">
            Brak domyślnego konta dla tej waluty
            ({Map.get(@invoice, :currency)}).
          </p>

          <.button
            type="button"
            size="small"
            variant="secondary"
            class="col-span-2 my-4"
            phx-click={show_modal("bank_account_selector_modal")}
          >
            Wybierz konto
          </.button>
        <% end %>

        <%= if is_nil(@selected_bank_account) do %>
          <label class="min-w-[150px] text-grey-700" for={@payment_form[:seller_account_number].id}>
            lub wpisz ręcznie:
          </label>
          <.input
            field={@payment_form[:seller_account_number]}
            type="text"
            placeholder="np. PL61109010140000071219812874"
            class="w-full"
          />
        <% end %>

        <%= if not Enum.empty?(@bank_accounts) and @selected_bank_account != nil do %>
          <div class="pr-2 pb-2">
            <Lucideicons.landmark class="size-[42px] text-grey-700" />
          </div>

          <div class="flex flex-row items-center gap-2">
            <.badge
              :if={
                @selected_bank_account.is_default and
                  @selected_bank_account.currency == @invoice.currency
              }
              tone="success"
            >
              domyślny <strong>{@selected_bank_account.currency}</strong>
            </.badge>

            <.badge :if={@selected_bank_account.currency != @invoice.currency} tone="danger">
              waluta konta: <strong>{@selected_bank_account.currency}</strong>
            </.badge>

            <.button
              type="button"
              size="small"
              variant="secondary"
              class="ml-auto h-min"
              phx-click={show_modal("bank_account_selector_modal")}
            >
              Zmień
            </.button>
          </div>

          <p class="text-sm/snug text-grey-500">Bank</p>
          <p class="text-sm/snug text-grey-700">{@selected_bank_account.institution_name}</p>

          <p class="text-sm/snug text-grey-500">Numer</p>
          <p class="text-sm/snug text-grey-700">{@selected_bank_account.iban}</p>
        <% end %>
      </div>

      <%!-- Bank account selector modal --%>
      <div class="absolute">
        <.modal id="bank_account_selector_modal" class="max-w-4xl">
          <h2 class="mb-2 text-xl font-medium">Zmiana rachunku</h2>
          <p class="mb-6 text-grey-600">Wybierz rachunek bankowy, na który chcesz otrzymać wpłatę.</p>

          <div class="space-y-3">
            <%= for account <- @bank_accounts do %>
              <div
                id={"bank-account-option-#{account.id}"}
                class={[
                  "grid grid-cols-[min-content_min-content_1fr_min-content_min-content] items-center gap-2 rounded-lg border p-4 transition-colors",
                  if(@selected_bank_account && @selected_bank_account.id == account.id,
                    do: "border-grey-400 bg-grey-50",
                    else: "border-grey-200 hover:border-grey-300"
                  )
                ]}
              >
                <Lucideicons.landmark class="mr-4 size-10 shrink-0 text-grey-600" />

                <div class="flex flex-col gap-2 text-sm">
                  <span :if={account.name} class="block text-grey-500">Nazwa</span>
                  <span class="block text-grey-500">Bank</span>
                  <span class="block text-grey-500">Numer</span>
                  <span class="block text-grey-500">Waluta</span>
                </div>

                <div class="flex flex-col gap-2 text-sm">
                  <span :if={account.name} class="block truncate text-grey-700">{account.name}</span>
                  <span class="block truncate text-grey-700">{account.institution_name}</span>
                  <span class="block text-grey-700">{account.iban}</span>
                  <span class="block text-grey-700">{account.currency}</span>
                </div>

                <.badge
                  :if={account.is_default and account.currency == @invoice.currency}
                  tone="success"
                  class="mx-4"
                >
                  domyślny <strong>{account.currency}</strong>
                </.badge>

                <%= if @selected_bank_account && @selected_bank_account.id == account.id do %>
                  <.button
                    type="button"
                    size="small"
                    variant="outline"
                    phx-click="select_bank_account"
                    phx-value-account_id={account.id}
                  >
                    Odznacz
                  </.button>
                <% else %>
                  <.button
                    type="button"
                    size="small"
                    variant="outline"
                    phx-click="select_bank_account"
                    phx-value-account_id={account.id}
                  >
                    Wybierz
                  </.button>
                <% end %>
              </div>
            <% end %>
          </div>

          <div class="mt-6 flex justify-end">
            <.button
              type="button"
              variant="primary"
              accent="teal"
              phx-click={hide_modal("bank_account_selector_modal")}
            >
              Dalej
            </.button>
          </div>
        </.modal>
      </div>
    </div>
    """
  end
end
