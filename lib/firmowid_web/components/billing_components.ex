defmodule FirmowidWeb.BillingComponents do
  @moduledoc """
  UI components for billing limits warnings and usage displays.
  """
  use Phoenix.Component

  import Tails

  @doc """
  Renders a warning banner when the organization is over their usage limit.

  The `check_result` should be the result of calling `Firmowid.Billing.check/2`
  in the LiveView's mount or handle_params.

  ## Examples

      # In LiveView mount/handle_params:
      check_result = Billing.check(org_id, :cost_invoices)
      socket = assign(socket, :cost_invoices_limit_check, check_result)

      # In template:
      <.limit_warning check_result={@cost_invoices_limit_check} type={:cost_invoices} />

  """
  attr :check_result, :any,
    required: true,
    doc: "Result of Billing.check/2 - :ok or {:warning, :over_limit, %{used: x, limit: y}}"

  attr :type, :atom, required: true, values: [:cost_invoices, :sales_invoices, :bank_connections]

  def limit_warning(assigns) do
    ~H"""
    <%= case @check_result do %>
      <% {:warning, :over_limit, %{used: used, limit: limit}} -> %>
        <div class="bg-orangeBg border border-orangeText/20 rounded-lg p-4 mb-4">
          <div class="flex items-start gap-3">
            <div class="flex-shrink-0">
              <svg
                class="h-5 w-5 text-orangeText"
                viewBox="0 0 20 20"
                fill="currentColor"
                aria-hidden="true"
              >
                <path
                  fill-rule="evenodd"
                  d="M8.485 2.495c.673-1.167 2.357-1.167 3.03 0l6.28 10.875c.673 1.167-.17 2.625-1.516 2.625H3.72c-1.347 0-2.189-1.458-1.515-2.625L8.485 2.495zM10 5a.75.75 0 01.75.75v3.5a.75.75 0 01-1.5 0v-3.5A.75.75 0 0110 5zm0 9a1 1 0 100-2 1 1 0 000 2z"
                  clip-rule="evenodd"
                />
              </svg>
            </div>
            <div class="flex-1">
              <h3 class="text-sm font-medium text-orangeText">
                {limit_title(@type)}
              </h3>
              <p class="mt-1 text-sm text-orangeText/80">
                {limit_message(@type, used, limit)}
              </p>
              <a
                href="/ustawienia/organizacja#limity"
                class="mt-2 inline-block text-sm font-medium text-orangeText underline hover:text-orangeText/70"
              >
                Zobacz szczegóły w ustawieniach
              </a>
            </div>
          </div>
        </div>
      <% :ok -> %>
    <% end %>
    """
  end

  @doc """
  Renders a usage limit progress bar with label and counts.

  ## Examples

      <.usage_limit_bar
        label="Faktury kosztowe"
        used={80}
        limit={100}
        over_limit={false}
        reset_text="Odnowienie za 8 dni"
      />

  """
  attr :label, :string, required: true
  attr :used, :integer, required: true
  attr :limit, :integer, required: true
  attr :over_limit, :boolean, required: true
  attr :reset_text, :string, required: true

  def usage_limit_bar(assigns) do
    percentage = min(100, floor(assigns.used / max(assigns.limit, 1) * 100))
    assigns = assign(assigns, :percentage, percentage)

    ~H"""
    <div class="text-xs">
      <div class="flex justify-between items-center mb-1">
        <span class="text-darkGrey">{@label}</span>
        <span class={classes(["font-medium", @over_limit && "text-orangeText"])}>
          {@used}/{@limit}
        </span>
      </div>
      <div class="w-full h-2 bg-greyButtonBg rounded-full overflow-hidden">
        <div
          class={
            classes([
              "h-full rounded-full transition-all duration-300",
              if(@over_limit, do: "bg-orangeText", else: "bg-greenText")
            ])
          }
          style={"width: #{@percentage}%"}
        >
        </div>
      </div>
      <div class={
        classes(["mt-1", if(@over_limit, do: "text-orangeText/70", else: "text-darkGrey/60")])
      }>
        {@reset_text}
      </div>
    </div>
    """
  end

  defp limit_title(:cost_invoices), do: "Przekroczono limit faktur kosztowych"
  defp limit_title(:sales_invoices), do: "Przekroczono limit faktur sprzedażowych"
  defp limit_title(:bank_connections), do: "Przekroczono limit połączeń bankowych"

  defp limit_message(:cost_invoices, used, limit) do
    "Wykorzystano #{used} z #{limit} faktur kosztowych w tym miesiącu. " <>
      "Rozważ upgrade planu, aby dodać więcej faktur."
  end

  defp limit_message(:sales_invoices, used, limit) do
    "Wykorzystano #{used} z #{limit} faktur sprzedażowych w tym miesiącu. " <>
      "Rozważ upgrade planu, aby dodać więcej faktur."
  end

  defp limit_message(:bank_connections, used, limit) do
    "Wykorzystano #{used} z #{limit} połączeń bankowych. " <>
      "Rozważ upgrade planu, aby dodać więcej połączeń."
  end
end
