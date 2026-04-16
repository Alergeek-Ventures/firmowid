defmodule FirmowidWeb.Invoicing.SalesInvoices.Components.InvoicePayment do
  @moduledoc false
  use FirmowidWeb, :html

  alias FirmowidWeb.Invoicing.SalesInvoices.Utilities.PaymentDateSuggestions

  attr :invoice, :map, required: true
  attr :bank_accounts, :list, required: true
  attr :selected_bank_account, :map, required: false
  attr :payment_form, Phoenix.HTML.Form, required: true

  def invoice_payment(assigns) do
    ~H"""
    <div class="grid grid-cols-[min-content_min-content_1fr] items-center gap-x-5 gap-y-4">
      <label class="text-grey-700 whitespace-nowrap" for={@payment_form[:sale_date].id}>
        Data sprzedaży
      </label>
      <.input
        field={@payment_form[:sale_date]}
        type="date"
        phx-debounce
        class="h-8 w-43"
        new={true}
      />
      <div class="flex flex-wrap items-center gap-2">
        <.button
          :for={{suggestion, label} <- PaymentDateSuggestions.sale_date_suggestions()}
          type="button"
          size="small"
          class="h-8"
          color="light_grey"
          new={true}
          phx-click="suggest_payment_date"
          phx-value-field="sale_date"
          phx-value-suggestion={suggestion}
        >
          {label}
        </.button>
      </div>

      <label class="text-grey-700 whitespace-nowrap" for={@payment_form[:due_date].id}>
        Termin płatności
      </label>
      <.input
        field={@payment_form[:due_date]}
        type="date"
        phx-debounce
        class="h-8 w-43"
        new={true}
      />
      <div class="flex flex-wrap items-center gap-2">
        <.button
          :for={{suggestion, label} <- PaymentDateSuggestions.due_date_suggestions()}
          type="button"
          size="small"
          color="light_grey"
          new={true}
          class="h-8"
          phx-click="suggest_payment_date"
          phx-value-field="due_date"
          phx-value-suggestion={suggestion}
        >
          {label}
        </.button>
      </div>

      <label class="text-grey-700 whitespace-nowrap" for={@payment_form[:payment_method].id}>
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
        new={true}
      />
      <div></div>

      <div class={[
        "border-grey-200 col-span-2 col-start-2 grid w-min min-w-[400px] grid-cols-[min-content_1fr] items-center gap-4 gap-y-2 rounded-lg border p-4 transition-opacity duration-200",
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
          <p class="text-grey-700 col-span-2 text-sm/snug">
            Żadne z Twoich kont nie jest podpięte.
          </p>
          <.link
            class={[
              "inline-flex items-center gap-1.5",
              button_styles(%{size: "small", color: "light_grey", new: true})
            ]}
            target="_blank"
            href="/ustawienia/konta-bankowe"
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
            color="light_grey"
            new={true}
            class="col-span-2 my-4"
            phx-click={show_modal("bank_account_selector_modal")}
          >
            Wybierz konto
          </.button>
        <% end %>

        <%= if is_nil(@selected_bank_account) do %>
          <label class="text-grey-700 min-w-[150px]" for={@payment_form[:seller_account_number].id}>
            lub wpisz ręcznie:
          </label>
          <.input
            field={@payment_form[:seller_account_number]}
            type="text"
            placeholder="np. PL61109010140000071219812874"
            class="w-full"
            new={true}
          />
        <% end %>

        <%= if not Enum.empty?(@bank_accounts) and @selected_bank_account != nil do %>
          <div class="pr-2 pb-2">
            <Lucideicons.landmark class="text-grey-700 size-[42px]" />
          </div>

          <div class="flex flex-row items-center gap-2">
            <p
              :if={
                @selected_bank_account.is_default and
                  @selected_bank_account.currency == @invoice.currency
              }
              class="h-min rounded-full bg-green-200 px-4 py-1 text-sm/snug text-green-700"
            >
              domyślny <strong>{@selected_bank_account.currency}</strong>
            </p>

            <p
              :if={@selected_bank_account.currency != @invoice.currency}
              class="bg-redBg text-redText h-min rounded-full px-4 py-1 text-sm/snug"
            >
              waluta konta: <strong>{@selected_bank_account.currency}</strong>
            </p>

            <.button
              type="button"
              size="small"
              color="light_grey"
              new={true}
              class="ml-auto h-min"
              phx-click={show_modal("bank_account_selector_modal")}
            >
              Zmień
            </.button>
          </div>

          <p class="text-grey-500 text-sm/snug">Bank</p>
          <p class="text-grey-700 text-sm/snug">{@selected_bank_account.institution_name}</p>

          <p class="text-grey-500 text-sm/snug">Numer</p>
          <p class="text-grey-700 text-sm/snug">{@selected_bank_account.iban}</p>
        <% end %>
      </div>

      <%!-- Bank account selector modal --%>
      <div class="absolute">
        <.modal id="bank_account_selector_modal" class="max-w-4xl">
          <h2 class="mb-2 text-xl font-medium">Zmiana rachunku</h2>
          <p class="text-grey-600 mb-6">Wybierz rachunek bankowy, na który chcesz otrzymać wpłatę.</p>

          <div class="space-y-3">
            <%= for account <- @bank_accounts do %>
              <div class={[
                "grid grid-cols-[min-content_min-content_1fr_min-content_min-content] items-center gap-2 rounded-lg border p-4 transition-colors",
                if(@selected_bank_account && @selected_bank_account.id == account.id,
                  do: "bg-grey-50 border-grey-400",
                  else: "border-grey-200 hover:border-grey-300"
                )
              ]}>
                <Lucideicons.landmark class="text-grey-600 mr-4 size-10 shrink-0" />

                <div class="flex flex-col gap-2 text-sm">
                  <span :if={account.name} class="text-grey-500 block">Nazwa</span>
                  <span class="text-grey-500 block">Bank</span>
                  <span class="text-grey-500 block">Numer</span>
                </div>

                <div class="flex flex-col gap-2 text-sm">
                  <span :if={account.name} class="text-grey-700 block truncate">{account.name}</span>
                  <span class="text-grey-700 block truncate">{account.institution_name}</span>
                  <span class="text-grey-700 block">{account.iban}</span>
                </div>

                <p
                  :if={account.is_default and account.currency == @invoice.currency}
                  class="mx-4 rounded-full bg-green-200 px-3 py-1 text-sm/snug whitespace-nowrap text-green-700"
                >
                  domyślny <strong>{account.currency}</strong>
                </p>

                <%= if @selected_bank_account && @selected_bank_account.id == account.id do %>
                  <.button
                    type="button"
                    size="small"
                    variant="outline"
                    new={true}
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
                    new={true}
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
              color="turquoise"
              new={true}
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
