defmodule FirmowidWeb.Delegations.Components.Settlement.ForeignCurrency do
  @moduledoc "Function components for foreign-currency delegation expense settlement."

  use FirmowidWeb, :html

  import FirmowidWeb.DesignSystem.Components.Button
  import FirmowidWeb.DesignSystem.Components.CoreComponents, except: [button: 1]
  import FirmowidWeb.DesignSystem.Components.Link
  import Phoenix.Component, except: [link: 1]

  alias Phoenix.HTML.Form
  alias Phoenix.LiveView.Rendered

  @company_currency "PLN"

  @doc "Renders document number, amount, currency, and foreign-currency settlement fields."
  @spec document_fields(map()) :: Rendered.t()
  attr :expense, :any, required: true
  attr :form, Form, required: true
  attr :currency, :string, default: nil
  attr :foreign_currency_mode, :atom, default: :notice
  attr :nbp_settlement, :map, default: nil
  attr :statement_upload, :any, required: true
  attr :statement_blob, :any, default: nil
  attr :statement_expense_id, :string, default: nil

  def document_fields(assigns) do
    amount_field = assigns.form[:expense_amount]
    currency = assigns.currency || expense_currency(amount_field.value)

    assigns =
      assigns
      |> assign(:amount_field, amount_field)
      |> assign(:currency, currency)
      |> assign(:foreign_currency?, currency != @company_currency)

    ~H"""
    <.input id={"document-number-#{@expense.id}"} field={@form[:document_number]} type="text" new>
      <:label_slot>
        <span class="inline-flex items-center gap-1">
          <Lucideicons.sparkles class="size-4" aria-hidden="true" /> Nr dokumentu
        </span>
      </:label_slot>
    </.input>
    <div class="flex items-end gap-2">
      <div class="w-25 shrink-0">
        <.input
          id={"expense-amount-#{@expense.id}"}
          field={@form[:expense_amount]}
          value={expense_amount_value(@form[:expense_amount].value)}
          type="number"
          new
          min="0"
          step="0.01"
          input_class="w-25"
        >
          <:label_slot>
            <span class="inline-flex items-center gap-1">
              <Lucideicons.sparkles class="size-4" aria-hidden="true" /> Kwota
            </span>
          </:label_slot>
        </.input>
      </div>
      <.input
        id={"expense-currency-#{@expense.id}"}
        name={"expense_currencies[#{@expense.id}]"}
        value={@currency}
        type="select"
        new
        options={currency_options()}
        input_class={["w-24 shrink-0", @foreign_currency? && "bg-turquoise-100"]}
        aria-label="Waluta"
      />
    </div>
    <.foreign_currency_settlement
      :if={@foreign_currency?}
      expense={@expense}
      form={@form}
      currency={@currency}
      mode={@foreign_currency_mode}
      nbp_settlement={@nbp_settlement}
      statement_upload={@statement_upload}
      statement_blob={@statement_blob}
      statement_expense_id={@statement_expense_id}
    />
    """
  end

  attr :expense, :any, required: true
  attr :form, Form, required: true
  attr :currency, :string, required: true
  attr :mode, :atom, required: true
  attr :nbp_settlement, :map, default: nil
  attr :statement_upload, :any, required: true
  attr :statement_blob, :any, default: nil
  attr :statement_expense_id, :string, default: nil

  defp foreign_currency_settlement(%{mode: :notice} = assigns) do
    ~H"""
    <section
      id={"foreign-currency-notice-#{@expense.id}"}
      class="bg-turquoise-100 border-grey-200 text-turquoise-700 mt-1 flex w-full flex-wrap items-center justify-between gap-3 rounded-lg border p-6 sm:col-span-2 lg:col-span-3"
    >
      <p>Wykryto obcą walutę</p>
      <div class="flex gap-2">
        <.button
          type="button"
          variant="primary"
          accent="turquoise"
          size="small"
          phx-click="foreign-currency-action"
          phx-value-action="statement"
          phx-value-expense-id={@expense.id}
        >Mam kwotę z wyciągu</.button>
        <.button
          type="button"
          variant="primary"
          accent="turquoise"
          size="small"
          phx-click="foreign-currency-action"
          phx-value-action="nbp"
          phx-value-expense-id={@expense.id}
        >Przelicz wg kursu NBP</.button>
      </div>
    </section>
    """
  end

  defp foreign_currency_settlement(assigns) do
    statement_entry =
      if assigns.statement_expense_id == assigns.expense.id do
        List.first(assigns.statement_upload.entries)
      end

    assigns =
      assigns
      |> assign(:mode_label, mode_label(assigns.mode))
      |> assign(:statement_entry, statement_entry)

    ~H"""
    <section class="mt-1 grid w-full grid-cols-subgrid gap-3 sm:col-span-2 lg:col-span-3">
      <div class="flex items-start">
        <.button
          type="button"
          variant="unstyled"
          class="text-turquoise-700 inline-flex cursor-pointer items-center gap-1 text-sm/6 font-medium"
          phx-click="foreign-currency-action"
          phx-value-action="notice"
          phx-value-expense-id={@expense.id}
        ><Lucideicons.chevron_left class="size-4" />{@mode_label}</.button>
      </div>
      <%= if @mode == :statement do %>
        <div>
          <.label for={@statement_upload.ref} class="mb-2">Wyciąg z rachunku</.label>
          <.statement_document :if={@statement_blob} expense_id={@expense.id} blob={@statement_blob} />
          <.document_pill
            :if={!@statement_blob && @statement_entry}
            filename={@statement_entry.client_name}
            loading?
          />
          <.button
            :if={!@statement_blob && !@statement_entry}
            as="label"
            for={@statement_upload.ref}
            type="button"
            variant="secondary"
            size="small"
            class="bg-grey-200 border-grey-200"
            phx-click="select-statement-expense"
            phx-value-id={@expense.id}
          >Wgraj dokument</.button>
        </div>
        <.settlement_amount_field form={@form} expense_id={@expense.id} currency="PLN" />
      <% else %>
        <div>
          <.label class="mb-2">Kurs | {format_date(@nbp_settlement && @nbp_settlement.date)}</.label>
          <div class="border-grey-200 text-grey-700 rounded-lg border bg-transparent px-3 py-1.5 text-base/tight">
            {format_rate(@currency, @nbp_settlement, "PLN")}
          </div>
        </div>
        <.nbp_amount_field
          expense_id={@expense.id}
          amount={@nbp_settlement && @nbp_settlement.amount}
          currency="PLN"
        />
      <% end %>
    </section>
    """
  end

  attr :expense_id, :string, required: true
  attr :blob, :any, required: true

  defp statement_document(assigns) do
    ~H"""
    <.document_pill filename={@blob.original_filename} url={@blob.url}>
      <:action>
        <.button
          type="button"
          variant="unstyled"
          class="text-grey-500 cursor-pointer"
          phx-click="remove-statement-document"
          phx-value-expense-id={@expense_id}
          aria-label={"Usuń #{@blob.original_filename}"}
        ><Lucideicons.x class="size-3" /></.button>
      </:action>
    </.document_pill>
    """
  end

  @doc "Renders a document pill with an optional action."
  @spec document_pill(map()) :: Rendered.t()
  attr :filename, :string, required: true
  attr :url, :string, default: nil
  attr :loading?, :boolean, default: false
  slot :action

  def document_pill(assigns) do
    ~H"""
    <span
      aria-busy={@loading?}
      class={[
        "bg-grey-200 text-grey-600 inline-flex max-w-full items-center gap-1 rounded px-2 py-1 text-sm font-medium",
        @loading? && "animate-pulse"
      ]}
    >
      <.link
        :if={@url}
        kind="unstyled"
        external={@url}
        target="_blank"
        rel="noopener noreferrer"
        class="inline-flex min-w-0 items-center gap-1"
      ><Lucideicons.file class="size-4 shrink-0" /><span
        class="max-w-[220px] truncate"
        title={@filename}
      >{@filename}</span></.link>
      <span :if={!@url} class="inline-flex min-w-0 items-center gap-1">
        <Lucideicons.file class="size-4 shrink-0" />
        <span class="max-w-[220px] truncate" title={@filename}>{@filename}</span>
      </span>
      {render_slot(@action)}
    </span>
    """
  end

  attr :form, Form, required: true
  attr :expense_id, :string, required: true
  attr :currency, :string, required: true

  defp settlement_amount_field(assigns) do
    ~H"""
    <div class="flex items-end gap-2">
      <div class="w-25 shrink-0">
        <.input
          id={"settlement-amount-#{@expense_id}"}
          field={@form[:settlement_amount]}
          type="number"
          new
          label={"Kwota w #{@currency}"}
          min="0"
          step="0.01"
          placeholder="0,00"
          input_class="w-25"
        />
      </div><span
        id={"settlement-currency-#{@expense_id}"}
        class="text-grey-500 shrink-0 pb-2 text-sm whitespace-nowrap"
      >{@currency}</span>
    </div>
    """
  end

  attr :expense_id, :string, required: true
  attr :amount, :any, default: nil
  attr :currency, :string, required: true

  defp nbp_amount_field(assigns) do
    ~H"""
    <div class="flex items-end gap-2">
      <div class="w-25 shrink-0">
        <.label class="mb-2">Po przeliczeniu</.label><div
          id={"settlement-amount-#{@expense_id}"}
          class="border-grey-200 text-grey-700 rounded-lg border bg-transparent px-3 py-1.5 text-base/tight"
        >
          {Money.to_string!(@amount, fractional_digits: 2, currency_symbol: "")}
        </div>
      </div><span
        id={"settlement-currency-#{@expense_id}"}
        class="text-grey-500 shrink-0 pb-2 text-sm whitespace-nowrap"
      >{@currency}</span>
    </div>
    """
  end

  defp currency_options do
    popular = ~w(PLN EUR GBP USD)
    currencies = Enum.map(Money.known_current_currencies(), &Atom.to_string/1)
    [{"Najczęściej używane", popular}, {"Wszystkie waluty", currencies -- popular}]
  end

  defp mode_label(:statement), do: "Mam kwotę z wyciągu"
  defp mode_label(:nbp), do: "Przelicz wg kursu NBP"
  defp format_date(nil), do: "—"
  defp format_date(date), do: Calendar.strftime(date, "%d.%m.%Y")
  defp format_rate(_source, nil, _target), do: "Nie udało się pobrać kursu"

  defp format_rate(source, %{rate: rate}, target),
    do: "1 #{source} = #{rate |> Decimal.to_string(:normal) |> String.replace(".", ",")} #{target}"

  defp expense_currency(%Money{} = amount), do: amount |> Money.to_currency_code() |> Atom.to_string()

  defp expense_currency(%{"currency" => currency}) when is_binary(currency), do: currency
  defp expense_currency(_amount), do: @company_currency
  defp expense_amount_value(%Money{} = amount), do: Money.to_decimal(amount)
  defp expense_amount_value(amount), do: amount
end
