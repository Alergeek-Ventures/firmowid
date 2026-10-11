defmodule FirmowidWeb.Invoicing.SalesInvoices.Components.InvoiceReview do
  @moduledoc "Shared final review of invoice numbering, notes and delivery options."
  use FirmowidWeb, :html

  import FirmowidWeb.DesignSystem.Components.Button

  attr :invoice, :map, required: true
  attr :preview_invoice, :map, required: true
  attr :invoice_number, :string, required: true
  attr :invoice_warnings, :list, required: true
  attr :invoice_number_errors, :list, default: []
  attr :series_suggestions, :map, required: true
  attr :organization, :map, required: true
  attr :currency_rate, :any, required: true
  attr :logo_url, :any, required: true
  attr :counterparty_check, :map, required: true
  attr :should_send_emails, :boolean, required: true
  attr :ksef_connected?, :boolean, required: true
  slot :back, required: true
  slot :header, required: true

  @doc "Renders the final review shared by the creator and saved invoice drafts."
  @spec invoice_review(map()) :: Phoenix.LiveView.Rendered.t()
  def invoice_review(assigns) do
    ~H"""
    <div id="invoice-review" class="relative mx-auto my-4 flex w-full max-w-6xl flex-1 flex-col">
      {render_slot(@back)}
      <div class="px-9">
        {render_slot(@header)}
        <div class="mbs-8 flex gap-6">
          <div class="max-w-[650px] flex-1">
            <div class="overflow-clip rounded-lg border border-grey-200 bg-white shadow-sm">
              <FirmowidWeb.Invoicing.SalesInvoices.Components.Pdf.sales_invoice
                sales_invoice={@preview_invoice}
                currency_rate={@currency_rate}
                show_vat={@organization.is_vat_payer}
                logo_url={@logo_url}
              />
            </div>
          </div>

          <div class="space-y-6">
            <h2 class="mbe-4 text-lg font-medium text-grey-700">Dane faktury</h2>
            <form
              id="invoice-number-form"
              phx-change="update_invoice_number"
              phx-submit={if @ksef_connected?, do: "send_to_ksef", else: "confirm_invoice"}
            >
              <label for="invoice-number" class="mbe-2 block text-sm text-grey-500">Numer faktury</label>
              <input
                id="invoice-number"
                type="text"
                name="invoice_number"
                value={@invoice_number}
                required
                class="w-full rounded-lg border border-grey-200 px-3 py-2 text-sm text-grey-700 placeholder:text-grey-400 focus:border-transparent focus:ring-2 focus:ring-turquoise-500"
              />
            </form>
            <.error :for={{message, _opts} <- @invoice_number_errors}>{message}</.error>

            <%= if @invoice_warnings != [] do %>
              <div class="space-y-3">
                <div
                  :for={warning <- @invoice_warnings}
                  class="bg-amber-50 rounded-lg bg-orangeBg p-3 text-sm"
                >
                  <div class="flex items-start gap-2 text-orangeText">
                    <Lucideicons.alert_triangle class="text-amber-500 mbs-0.5 size-4 shrink-0" />
                    <span>
                      <%= case warning do %>
                        <% {:invalid_format, _} -> %>
                          Format numeru może być nieprawidłowy.
                        <% {:duplicate, _} -> %>
                          Numer faktury już istnieje.
                        <% {:gap, _} -> %>
                          Numer tworzy lukę w numeracji.
                      <% end %>
                    </span>
                  </div>
                  <div class="ms-6 mbs-2 flex flex-wrap gap-2">
                    <.button
                      :for={suggestion <- warning_suggestions(warning)}
                      type="button"
                      phx-click="select_series"
                      phx-value-number={suggestion}
                      variant="secondary"
                      accent="turquoise"
                      size="small"
                      class="text-xs"
                    >
                      Użyj {suggestion}
                    </.button>
                  </div>
                </div>
              </div>
            <% else %>
              <div class="flex flex-wrap gap-2">
                <.button
                  :for={
                    {_series, next_number} <-
                      Enum.sort_by(@series_suggestions, fn {s, _} -> s || "" end)
                  }
                  type="button"
                  phx-click="select_series"
                  phx-value-number={next_number}
                  variant={if(@invoice_number == next_number, do: "secondary", else: "outline")}
                  accent="turquoise"
                  size="small"
                  class={[
                    if(@invoice_number == next_number,
                      do: "border-turquoise-500 text-turquoise-700",
                      else: "text-grey-600 hover:bg-grey-50"
                    )
                  ]}
                >
                  {next_number}
                </.button>
              </div>
            <% end %>

            <form id="invoice-notes-form" phx-change="update_notes">
              <label for="invoice-note" class="mbe-2 block text-sm text-grey-500">Notatka na fakturze</label>
              <textarea
                id="invoice-note"
                name="invoice_note"
                rows="3"
                class="w-full resize-none rounded-lg border border-grey-200 px-3 py-2 text-sm text-grey-700 placeholder:text-grey-400 focus:border-transparent focus:ring-2 focus:ring-turquoise-500"
                placeholder="Widoczna na fakturze i w KSeF (stopka faktury)"
              >{@invoice.invoice_note || ""}</textarea>

              <label for="internal-note" class="mbs-3 mbe-2 block text-sm text-grey-500">Komentarz</label>
              <textarea
                id="internal-note"
                name="internal_note"
                rows="3"
                class="w-full resize-none rounded-lg border border-grey-200 px-3 py-2 text-sm text-grey-700 placeholder:text-grey-400 focus:border-transparent focus:ring-2 focus:ring-turquoise-500"
                placeholder="Notatka wewnętrzna (niewidoczna na fakturze - tylko w Firmowidzie)"
              >{@invoice.internal_note || ""}</textarea>
            </form>

            <form id="invoice-email-form" phx-change="toggle_should_send_emails">
              <label
                class="flex items-center gap-3 text-sm font-medium text-grey-700"
                title={@counterparty_check.tooltip}
              >
                <input
                  type="checkbox"
                  name="should_send_emails"
                  value="true"
                  checked={@should_send_emails}
                  disabled={!@counterparty_check.valid}
                  class="size-4 rounded border-grey-300 text-turquoise-600 focus:ring-turquoise-500 disabled:cursor-not-allowed disabled:opacity-60"
                />
                <span>Wyślij fakturę e-mailem do kontrahenta po otrzymaniu numeru KSeF</span>
              </label>
            </form>

            <div class="flex flex-row gap-4 pbs-4">
              <.button
                type="button"
                phx-click="save_as_draft"
                phx-disable-with="Zapisywanie..."
                class="h-11 w-full"
                variant="secondary"
              >
                Zapisz wersję roboczą
              </.button>
              <%= if @ksef_connected? do %>
                <.button
                  id="confirm-invoice-button"
                  type="button"
                  phx-click="send_to_ksef"
                  phx-disable-with="Wysyłanie..."
                  class="h-11 w-full"
                  disabled={String.trim(@invoice_number) == ""}
                  variant="primary"
                  accent="turquoise"
                >
                  Zapisz i wyślij do KSeF
                </.button>
              <% else %>
                <.button
                  id="confirm-invoice-button"
                  type="button"
                  phx-click="confirm_invoice"
                  phx-disable-with="Zapisywanie..."
                  class="h-11 w-full"
                  disabled={String.trim(@invoice_number) == ""}
                  variant="primary"
                  accent="turquoise"
                >
                  Zatwierdź fakturę
                </.button>
              <% end %>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp warning_suggestions({:invalid_format, suggestions}), do: suggestions
  defp warning_suggestions({:duplicate, suggestions}), do: suggestions
  defp warning_suggestions({:gap, expected}), do: [expected]
end
