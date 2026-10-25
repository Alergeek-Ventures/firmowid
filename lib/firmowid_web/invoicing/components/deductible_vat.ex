defmodule FirmowidWeb.Invoicing.Components.DeductibleVat do
  @moduledoc """
  Manually qualified deductible VAT of a cost invoice and its corrections, used
  only by planned tax reserves.

  An empty field means unknown and `0` means no deduction. The amount is never
  derived from the gross amount or a default VAT rate.
  """
  use FirmowidWeb, :live_component

  import FirmowidUI.Components.Button

  alias Firmowid.Ash.Invoicing.CostInvoice

  @impl true
  def mount(socket) do
    # Amounts saved here: the parent's invoice keeps its value from the page mount.
    {:ok, assign(socket, saved: %{}, errors: %{})}
  end

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign(:documents, [assigns.invoice | assigns.invoice.correction_invoices])}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section id={@id} class="flex flex-col gap-3 py-2">
      <div class="flex flex-col gap-1">
        <h3 class="text-sm/snug font-medium text-grey-700">
          {gettext("Deductible VAT for the tax reserve")}
        </h3>
        <p class="text-xs text-grey-600">
          {gettext(
            "Enter the VAT you deduct from the document yourself. Leave the field empty when it is unknown, enter 0 when nothing is deducted and a negative amount for a correction that lowers the VAT. Firmowid never derives it from the gross amount."
          )}
        </p>
      </div>

      <.form
        :for={document <- @documents}
        for={%{}}
        id={"#{@id}-#{document.id}"}
        phx-target={@myself}
        phx-submit="save"
        class="flex flex-col gap-1"
      >
        <input type="hidden" name="document_id" value={document.id} />
        <label for={"#{@id}-#{document.id}-amount"} class="text-sm/snug text-grey-700">
          {document_label(document, @invoice)}
        </label>
        <div class="flex items-center gap-2">
          <.input
            type="number"
            id={"#{@id}-#{document.id}-amount"}
            name="amount"
            value={input_value(amount(document, @saved))}
            step="0.01"
            errors={List.wrap(@errors[document.id])}
            show_error={false}
            class="w-36"
          />
          <%= if document.amount.currency == :PLN and currency_value(document, @saved) == :PLN do %>
            <input type="hidden" name="currency" value="PLN" />
            <span class="text-sm text-grey-700">PLN</span>
          <% else %>
            <.input
              type="select"
              id={"#{@id}-#{document.id}-currency"}
              name="currency"
              value={currency_value(document, @saved)}
              options={currencies(document)}
              prompt={recorded_currency(document, @saved)}
              required
              input_class="w-24 shrink-0"
              aria-label={gettext("Currency")}
            />
          <% end %>
          <.button type="submit" variant="secondary" size="small">{gettext("Save")}</.button>
        </div>
        <p class="text-xs text-grey-600">{recorded_text(amount(document, @saved))}</p>
        <p :if={document.amount.currency != :PLN} class="text-xs text-grey-600">
          {gettext(
            "Enter the VAT in PLN or %{currency}. An amount in %{currency} is converted at the NBP rate from the last business day before the earlier of the document's issue and sale dates; without that rate, it counts as missing data.",
            currency: document.amount.currency
          )}
        </p>
        <p :if={@errors[document.id]} class="text-xs text-brick-700">{@errors[document.id]}</p>
      </.form>
    </section>
    """
  end

  @impl true
  def handle_event("save", %{"document_id" => id, "amount" => amount, "currency" => code}, socket) do
    document = Enum.find(socket.assigns.documents, &(&1.id == id))

    with {:ok, currency} <-
           document |> currencies() |> Map.new(&{Atom.to_string(&1), &1}) |> Map.fetch(code),
         {:ok, value} <- parse_amount(amount, currency),
         {:ok, updated} <-
           CostInvoice.update_tax_forecast_vat(document, %{deductible_vat_amount: value}, scope: socket.assigns.scope) do
      {:noreply,
       socket
       |> update(:saved, &Map.put(&1, id, updated.deductible_vat_amount))
       |> update(:errors, &Map.delete(&1, id))
       |> put_flash(:info, gettext("Deductible VAT saved."))}
    else
      :error -> {:noreply, put_invalid_amount(socket, id)}
      {:error, %Ash.Error.Invalid{}} -> {:noreply, put_invalid_amount(socket, id)}
    end
  end

  defp put_invalid_amount(socket, id) do
    message = gettext("Enter an amount with up to two decimal places, or leave the field empty.")
    update(socket, :errors, &Map.put(&1, id, message))
  end

  defp amount(document, saved), do: Map.get(saved, document.id, document.deductible_vat_amount)

  # The tax reserve takes VAT in PLN as recorded and converts VAT in the document's
  # currency at its NBP rate. It counts any other currency as missing data.
  defp currencies(document), do: Enum.uniq([document.amount.currency, :PLN])

  # Preselects the recorded currency, so saving an unchanged amount keeps it as recorded.
  # Any other recorded currency selects nothing: the select shows it as its placeholder
  # and, being required, blocks saving until PLN or the document's currency is chosen.
  defp currency_value(document, saved) do
    case amount(document, saved) do
      %Money{currency: currency} -> if currency in currencies(document), do: currency
      nil -> document.amount.currency
    end
  end

  defp recorded_currency(document, saved) do
    case amount(document, saved) do
      %Money{currency: currency} -> Atom.to_string(currency)
      nil -> nil
    end
  end

  defp document_label(%{id: id} = document, %{id: id}),
    do: gettext("Invoice %{number}", number: document.invoice_identifier)

  defp document_label(document, _invoice), do: gettext("Correction %{number}", number: document.invoice_identifier)

  defp input_value(nil), do: ""
  defp input_value(amount), do: amount |> Money.to_decimal() |> Decimal.to_string(:normal)

  defp recorded_text(nil), do: gettext("Not recorded: the tax reserve counts this document as missing data.")

  defp recorded_text(amount) do
    if Money.zero?(amount),
      do: gettext("Recorded: nothing to deduct."),
      else: gettext("Recorded: %{amount}", amount: Money.to_string!(amount))
  end

  defp parse_amount(amount, currency) do
    case String.trim(amount) do
      "" ->
        {:ok, nil}

      value ->
        case Decimal.parse(value) do
          {decimal, ""} -> {:ok, Money.new(currency, decimal)}
          _invalid -> :error
        end
    end
  end
end
