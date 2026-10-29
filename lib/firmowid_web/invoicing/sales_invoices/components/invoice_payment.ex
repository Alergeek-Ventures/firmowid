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

  alias Firmowid.Finances.BankAccount
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

  attr :kind, :atom, values: [:default, :account], required: true
  attr :currency, :string, required: true

  defp currency_label(assigns) do
    case_result =
      case assigns.kind do
        :default -> gettext("default %{currency}", currency: "__CURRENCY__")
        :account -> gettext("account currency: %{currency}", currency: "__CURRENCY__")
      end

    [label_before, label_after] = String.split(case_result, "__CURRENCY__", parts: 2)

    assigns = assign(assigns, label_before: label_before, label_after: label_after)

    ~H"{@label_before}<strong>{@currency}</strong>{@label_after}"
  end

  attr :invoice, :map, required: true
  attr :bank_accounts, :list, required: true
  attr :selected_bank_account, :map, required: false
  attr :payment_form, Phoenix.HTML.Form, required: true

  def invoice_payment(assigns) do
    ~H"""
    <div class="grid grid-cols-[min-content_min-content_1fr] items-center gap-x-5 gap-y-4">
      <label class="whitespace-nowrap text-grey-700" for={@payment_form[:sale_date].id}>
        {gettext("Sale date")}
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
        {gettext("Payment due date")}
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
        {gettext("Payment method")}
      </label>
      <.input
        field={@payment_form[:payment_method]}
        type="select"
        options={[
          {gettext("Transfer"), :transfer},
          {gettext("Cash"), :cash},
          {gettext("Card"), :card}
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
            {gettext("None of your accounts is connected.")}
          </p>
          <.link
            kind="button"
            variant="secondary"
            size="small"
            class="inline-flex items-center gap-1.5"
            target="_blank"
            redirect={~p"/ustawienia/firma"}
          >
            <Lucideicons.plus class="inline-flex size-4" /> {gettext("Connect an account")}
          </.link>
        <% end %>

        <%= if not Enum.empty?(@bank_accounts) and @selected_bank_account == nil do %>
          <p class="col-span-2">
            {gettext("No default account for this currency (%{currency}).",
              currency: Map.get(@invoice, :currency)
            )}
          </p>

          <.button
            type="button"
            size="small"
            variant="secondary"
            class="col-span-2 my-4"
            phx-click={show_modal("bank_account_selector_modal")}
          >
            {gettext("Choose an account")}
          </.button>
        <% end %>

        <%= if is_nil(@selected_bank_account) do %>
          <label class="min-w-[150px] text-grey-700" for={@payment_form[:seller_account_number].id}>
            {gettext("or enter it manually:")}
          </label>
          <.input
            field={@payment_form[:seller_account_number]}
            type="text"
            placeholder={gettext("e.g. PL61109010140000071219812874")}
            class="w-full"
          />
        <% end %>

        <%= if not Enum.empty?(@bank_accounts) and @selected_bank_account != nil do %>
          <div class="pr-2 pb-2">
            <Lucideicons.landmark class="size-[42px] text-grey-700" />
          </div>

          <div class="flex flex-row items-center gap-2">
            <p
              :if={
                @selected_bank_account.is_default and
                  @selected_bank_account.currency == @invoice.currency
              }
              class="h-min rounded-full bg-moss-200 px-4 py-1 text-sm/snug text-moss-700"
            >
              <.currency_label kind={:default} currency={@selected_bank_account.currency} />
            </p>

            <p
              :if={@selected_bank_account.currency != @invoice.currency}
              class="h-min rounded-full bg-brick-200 px-4 py-1 text-sm/snug text-brick-700"
            >
              <.currency_label kind={:account} currency={@selected_bank_account.currency} />
            </p>

            <.button
              type="button"
              size="small"
              variant="secondary"
              class="ml-auto h-min"
              phx-click={show_modal("bank_account_selector_modal")}
            >
              {pgettext("bank account", "Change")}
            </.button>
          </div>

          <p class="text-sm/snug text-grey-500">{pgettext("bank account", "Bank")}</p>
          <p class="text-sm/snug text-grey-700">{@selected_bank_account.institution_name}</p>

          <p class="text-sm/snug text-grey-500">{pgettext("bank account", "Number")}</p>
          <p class="text-sm/snug text-grey-700">{@selected_bank_account.iban}</p>
        <% end %>
      </div>

      <%!-- Bank account selector modal --%>
      <div class="absolute">
        <.modal id="bank_account_selector_modal" class="max-w-4xl">
          <h2 class="mb-2 text-xl font-medium">{gettext("Change account")}</h2>
          <p class="mb-6 text-grey-600">
            {gettext("Choose the bank account to receive the payment.")}
          </p>

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
                  <span :if={account.name} class="block text-grey-500">
                    {gettext("Name")}
                  </span>
                  <span class="block text-grey-500">{pgettext("bank account", "Bank")}</span>
                  <span class="block text-grey-500">{pgettext("bank account", "Number")}</span>
                  <span class="block text-grey-500">{gettext("Currency")}</span>
                </div>

                <div class="flex flex-col gap-2 text-sm">
                  <span :if={account.name} class="block truncate text-grey-700">{account.name}</span>
                  <span class="block truncate text-grey-700">{account.institution_name}</span>
                  <span class="block text-grey-700">{account.iban}</span>
                  <span class="block text-grey-700">{account.currency}</span>
                </div>

                <p
                  :if={account.is_default and account.currency == @invoice.currency}
                  class="mx-4 rounded-full bg-moss-200 px-3 py-1 text-sm/snug whitespace-nowrap text-moss-700"
                >
                  <.currency_label kind={:default} currency={account.currency} />
                </p>

                <%= if @selected_bank_account && @selected_bank_account.id == account.id do %>
                  <.button
                    type="button"
                    size="small"
                    variant="outline"
                    phx-click="select_bank_account"
                    phx-value-account_id={account.id}
                  >
                    {pgettext("bank account", "Deselect")}
                  </.button>
                <% else %>
                  <.button
                    type="button"
                    size="small"
                    variant="outline"
                    phx-click="select_bank_account"
                    phx-value-account_id={account.id}
                  >
                    {pgettext("bank account", "Select")}
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
              {pgettext("sales invoice creator", "Next")}
            </.button>
          </div>
        </.modal>
      </div>
    </div>
    """
  end
end
