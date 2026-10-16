defmodule FirmowidUI.Invoicing.Components.InvoiceNumber do
  @moduledoc "Invoice number input, numbering warnings and series suggestions shared by browser and MCP reviews."
  use FirmowidUI, :html

  import FirmowidUI.Components.Button

  attr :invoice_number, :string, required: true
  attr :next_numbers_by_series, :map, default: %{}
  attr :warnings, :list, default: [], doc: "Results of `SalesInvoice.validate_number/4`."
  attr :errors, :list, default: []
  attr :disabled, :boolean, default: false
  attr :submit_event, :string, default: "update_invoice_number"
  slot :actions

  @doc "Renders a standalone number-change form with numbering warnings or series suggestions."
  @spec invoice_number(map()) :: Phoenix.LiveView.Rendered.t()
  def invoice_number(assigns) do
    ~H"""
    <div class="flex flex-col gap-3">
      <form
        id="invoice-number-form"
        phx-change="update_invoice_number"
        phx-submit={@submit_event}
      >
        <label for="invoice-number" class="mbe-2 block text-sm text-grey-500">
          {gettext("Invoice number")}
        </label>
        <input
          id="invoice-number"
          type="text"
          name="invoice_number"
          value={@invoice_number}
          disabled={@disabled}
          required
          aria-invalid={@errors != []}
          class="rounded-lg border border-grey-200 px-3 py-2 text-sm text-grey-700 inline-full placeholder:text-grey-400 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-turquoise-500 disabled:opacity-60"
        />
      </form>
      <p :for={error <- @errors} class="text-sm text-red-600" role="alert">
        {error_message(error)}
      </p>
      <div :if={@warnings == [] and @next_numbers_by_series != %{}} class="flex flex-wrap gap-2">
        <.button
          :for={{_sequence, next_number} <- Enum.sort(@next_numbers_by_series)}
          type="button"
          phx-click="select_invoice_series"
          phx-value-number={next_number}
          disabled={@disabled}
          variant={if(@invoice_number == next_number, do: "secondary", else: "outline")}
          accent="turquoise"
          size="small"
          class={[
            if(@invoice_number == next_number,
              do: "border-turquoise-500 text-turquoise-700",
              else: "text-grey-600"
            )
          ]}
        >
          {next_number}
        </.button>
      </div>
      <div :if={@warnings != []} class="space-y-3">
        <div :for={warning <- @warnings} class="bg-amber-50 rounded-lg bg-orangeBg p-3 text-sm">
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
              phx-click="select_invoice_series"
              phx-value-number={suggestion}
              disabled={@disabled}
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
      {render_slot(@actions)}
    </div>
    """
  end

  defp warning_suggestions({:invalid_format, suggestions}), do: suggestions
  defp warning_suggestions({:duplicate, suggestions}), do: suggestions
  defp warning_suggestions({:gap, expected}), do: [expected]

  defp error_message({message, _options}), do: message
  defp error_message(message), do: message
end
