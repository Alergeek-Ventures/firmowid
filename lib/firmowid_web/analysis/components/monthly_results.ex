defmodule FirmowidWeb.Analysis.Components.MonthlyResults do
  @moduledoc """
  The period month by month: each month's income, costs, result and what stayed of every
  100 zł of income, with the closed months' total. A month that is not closed has no
  amounts yet, so its row shows dashes and an empty bar. With `month_path`, a closed
  month links to its summary.
  """
  use FirmowidWeb, :html

  import FirmowidWeb.Analysis.Utilities.Amounts, only: [whole_money: 1]

  alias FirmowidWeb.Analysis.Utilities.Periods

  attr :months, :list,
    required: true,
    doc: "the period's months of the `YearSummary.get/3` result"

  attr :totals, :map, required: true, doc: "the closed months' combined totals"

  attr :month_path, :any,
    default: nil,
    doc: "function of a month giving its summary's path, or nil"

  @doc "Renders the table of monthly results."
  @spec table(map()) :: Phoenix.LiveView.Rendered.t()
  def table(assigns) do
    ~H"""
    <section
      id="analysis-monthly-results"
      aria-labelledby="analysis-monthly-results-title"
      class="@container flex flex-col gap-3 pt-4"
    >
      <h2 id="analysis-monthly-results-title" class="text-lg/[1.3] font-medium text-grey-900">
        {gettext("Month by month")}
      </h2>
      <%!-- Separate rows: each month is a white card 8px from the next. --%>
      <table class="-my-2 w-full border-separate border-spacing-x-0 border-spacing-y-2 text-sm/[1.35] tabular-nums">
        <thead>
          <tr class="text-grey-500 [&>th]:py-1 [&>th]:font-normal">
            <th scope="col" class="ps-4 text-start">{gettext("Month")}</th>
            <th scope="col" class={[amount_cell(), "hidden @lg:table-cell"]}>{gettext("Income")}</th>
            <th scope="col" class={[amount_cell(), "hidden @lg:table-cell"]}>{gettext("Costs")}</th>
            <th scope="col" class={amount_cell()}>{gettext("Result")}</th>
            <th scope="col" class={[share_cell(), "text-start"]}>
              {gettext("Of every 100 zł of income")}
            </th>
          </tr>
        </thead>
        <tbody>
          <tr
            :for={month <- @months}
            id={"analysis-monthly-result-#{Date.to_iso8601(month.month)}"}
            class={[
              "*:h-12 *:bg-white *:first:rounded-s-sm *:last:rounded-e-sm",
              if(month.closed?, do: "text-grey-900", else: "text-grey-400")
            ]}
          >
            <th scope="row" class={["ps-4 text-start", month.closed? && "font-medium"]}>
              <FirmowidUI.Components.Link.link
                :if={@month_path && month.closed?}
                kind="unstyled"
                patch={@month_path.(month.month)}
                class="underline decoration-transparent underline-offset-[.2em] hover:decoration-current"
              >
                {Periods.month_name(month.month, "LLLL y")}
              </FirmowidUI.Components.Link.link>
              <span :if={!(@month_path && month.closed?)} class="font-normal">
                {Periods.month_name(month.month, "LLLL y")}
              </span>
            </th>
            <%= if month.closed? do %>
              <td class={[amount_cell(), "hidden @lg:table-cell"]}>
                {whole_money(month.totals.total_income)}
              </td>
              <td class={[amount_cell(), "hidden @lg:table-cell"]}>
                {whole_money(Decimal.abs(month.totals.total_expenses))}
              </td>
              <td class={[amount_cell(), "font-medium", result_styles(month.totals.net_profit)]}>
                {whole_money(month.totals.net_profit)}
              </td>
              <td class={share_cell()}><.kept totals={month.totals} /></td>
            <% else %>
              <td class={[amount_cell(), "hidden @lg:table-cell"]}>{no_money()}</td>
              <td class={[amount_cell(), "hidden @lg:table-cell"]}>{no_money()}</td>
              <td class={amount_cell()}>{no_money()}</td>
              <td class={share_cell()}>
                <.share_bar label={String.downcase(pgettext("month", "Not closed"))} />
              </td>
            <% end %>
          </tr>
        </tbody>
        <tfoot>
          <tr class="font-semibold text-grey-900 *:h-12">
            <th scope="row" class="ps-4 text-start">{gettext("Total")}</th>
            <td class={[amount_cell(), "hidden @lg:table-cell"]}>
              {whole_money(@totals.total_income)}
            </td>
            <td class={[amount_cell(), "hidden @lg:table-cell"]}>
              {whole_money(Decimal.abs(@totals.total_expenses))}
            </td>
            <td class={[amount_cell(), result_styles(@totals.net_profit)]}>
              {whole_money(@totals.net_profit)}
            </td>
            <td class={share_cell()}><.kept totals={@totals} total /></td>
          </tr>
        </tfoot>
      </table>
    </section>
    """
  end

  # Columns 24px apart; the amounts are 112px wide and the share 336px, as in Figma.
  defp amount_cell, do: "w-34 ps-6 text-end"
  defp share_cell, do: "w-2/5 ps-6 pe-4 @3xl:w-94"

  attr :totals, :map, required: true
  attr :total, :boolean, default: false

  # What stayed of every 100 zł as a bar out of 100, or the loss on the same scale.
  defp kept(assigns) do
    income = assigns.totals.total_income

    per_100 =
      if Decimal.positive?(income),
        do:
          assigns.totals.net_profit
          |> Decimal.mult(100)
          |> Decimal.div(income)
          |> Decimal.round(0)
          |> Decimal.to_integer()

    assigns = assign(assigns, per_100: per_100)

    ~H"""
    <.share_bar
      :if={@per_100 == nil}
      label={String.downcase(gettext("No income"))}
      tone="text-grey-500"
    />
    <.share_bar
      :if={@per_100 != nil}
      per_100={@per_100}
      label={
        if @per_100 < 0,
          do: gettext("loss %{amount}", amount: whole_money(-@per_100)),
          else: gettext("%{amount} stayed", amount: whole_money(@per_100))
      }
      tone={
        cond do
          @per_100 < 0 -> "text-brick-700"
          @total -> "text-grey-900"
          true -> "text-grey-700"
        end
      }
    />
    """
  end

  attr :per_100, :integer, default: nil
  attr :label, :string, required: true

  attr :tone, :string,
    default: nil,
    doc: "text colour of the label; a not closed month's row sets it"

  defp share_bar(assigns) do
    ~H"""
    <span class="flex items-center gap-4">
      <span class="h-2 min-w-0 flex-1 overflow-hidden rounded-xs bg-grey-200" aria-hidden="true">
        <span
          :if={@per_100}
          class={["block h-full", if(@per_100 < 0, do: "bg-brick-700", else: "bg-teal-600")]}
          style={"width: #{min(abs(@per_100), 100)}%"}
        />
      </span>
      <span class={["w-28 shrink-0 text-end whitespace-nowrap", @tone]}>{@label}</span>
    </span>
    """
  end

  # A month that is not closed has no amounts yet: a dash in their place, with the currency.
  defp no_money, do: 0 |> whole_money() |> String.replace("0", "–")

  defp result_styles(amount), do: if(Decimal.negative?(amount), do: "text-brick-700", else: "text-grey-900")
end
