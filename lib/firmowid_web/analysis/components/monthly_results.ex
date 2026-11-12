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
      class="@container flex flex-col gap-4"
    >
      <h2 id="analysis-monthly-results-title" class="text-lg font-semibold text-grey-900">
        {gettext("Month by month")}
      </h2>
      <table class="w-full text-sm tabular-nums">
        <thead>
          <tr class="border-be border-grey-200 text-xs text-grey-700">
            <th scope="col" class="py-2 pe-3 text-start font-normal">{gettext("Month")}</th>
            <th scope="col" class="hidden py-2 pe-3 text-end font-normal @lg:table-cell">
              {gettext("Income")}
            </th>
            <th scope="col" class="hidden py-2 pe-3 text-end font-normal @lg:table-cell">
              {gettext("Costs")}
            </th>
            <th scope="col" class="py-2 pe-3 text-end font-normal">{gettext("Result")}</th>
            <th scope="col" class="w-2/5 py-2 text-start font-normal">
              {gettext("Of every 100 zł of income")}
            </th>
          </tr>
        </thead>
        <tbody>
          <tr
            :for={month <- @months}
            id={"analysis-monthly-result-#{Date.to_iso8601(month.month)}"}
            class="border-be border-grey-200"
          >
            <th scope="row" class="py-3 pe-3 text-start font-medium text-grey-900">
              <FirmowidUI.Components.Link.link
                :if={@month_path && month.closed?}
                kind="unstyled"
                patch={@month_path.(month.month)}
                class="underline decoration-transparent underline-offset-[.2em] hover:decoration-current"
              >
                {Periods.month_name(month.month, "LLLL y")}
              </FirmowidUI.Components.Link.link>
              <span :if={!(@month_path && month.closed?)} class={[!month.closed? && "text-grey-600"]}>
                {Periods.month_name(month.month, "LLLL y")}
              </span>
            </th>
            <%= if month.closed? do %>
              <td class="hidden py-3 pe-3 text-end text-grey-800 @lg:table-cell">
                {whole_money(month.totals.total_income)}
              </td>
              <td class="hidden py-3 pe-3 text-end text-grey-800 @lg:table-cell">
                {whole_money(Decimal.abs(month.totals.total_expenses))}
              </td>
              <td class={["py-3 pe-3 text-end font-medium", result_styles(month.totals.net_profit)]}>
                {whole_money(month.totals.net_profit)}
              </td>
              <td class="py-3">
                <.kept totals={month.totals} />
              </td>
            <% else %>
              <td class="hidden py-3 pe-3 text-end text-grey-500 @lg:table-cell">{no_money()}</td>
              <td class="hidden py-3 pe-3 text-end text-grey-500 @lg:table-cell">{no_money()}</td>
              <td class="py-3 pe-3 text-end text-grey-500">{no_money()}</td>
              <td class="py-3">
                <span class="flex items-center gap-3">
                  <span class="h-2 w-full rounded-xs bg-grey-200" aria-hidden="true" />
                  <span class="w-28 shrink-0 text-end whitespace-nowrap text-grey-600">
                    {String.downcase(pgettext("month", "Not closed"))}
                  </span>
                </span>
              </td>
            <% end %>
          </tr>
        </tbody>
        <tfoot>
          <tr class="font-semibold text-grey-900">
            <th scope="row" class="py-3 pe-3 text-start">{gettext("Total")}</th>
            <td class="hidden py-3 pe-3 text-end @lg:table-cell">
              {whole_money(@totals.total_income)}
            </td>
            <td class="hidden py-3 pe-3 text-end @lg:table-cell">
              {whole_money(Decimal.abs(@totals.total_expenses))}
            </td>
            <td class={["py-3 pe-3 text-end", result_styles(@totals.net_profit)]}>
              {whole_money(@totals.net_profit)}
            </td>
            <td class="py-3"><.kept totals={@totals} /></td>
          </tr>
        </tfoot>
      </table>
    </section>
    """
  end

  attr :totals, :map, required: true

  # What stayed of every 100 zł as a bar out of 100, or the loss on the same scale.
  defp kept(assigns) do
    income = assigns.totals.total_income

    assigns =
      assign(assigns,
        per_100:
          if(Decimal.positive?(income),
            do:
              assigns.totals.net_profit
              |> Decimal.mult(100)
              |> Decimal.div(income)
              |> Decimal.round(0)
              |> Decimal.to_integer()
          )
      )

    ~H"""
    <span :if={@per_100 == nil} class="text-grey-600">{gettext("No income")}</span>
    <span :if={@per_100 != nil} class="flex items-center gap-3">
      <span class="h-2 w-full overflow-hidden rounded-xs bg-grey-200" aria-hidden="true">
        <span
          class={["block h-full", if(@per_100 < 0, do: "bg-brick-700", else: "bg-teal-600")]}
          style={"width: #{min(abs(@per_100), 100)}%"}
        />
      </span>
      <span class={[
        "w-28 shrink-0 text-end whitespace-nowrap",
        if(@per_100 < 0, do: "text-brick-700", else: "text-grey-900")
      ]}>
        {if @per_100 < 0,
          do: gettext("loss %{amount}", amount: whole_money(-@per_100)),
          else: gettext("%{amount} stayed", amount: whole_money(@per_100))}
      </span>
    </span>
    """
  end

  # A month that is not closed has no amounts yet: a dash in their place, with the currency.
  defp no_money, do: 0 |> whole_money() |> String.replace("0", "–")

  defp result_styles(amount), do: if(Decimal.negative?(amount), do: "text-brick-700", else: "text-grey-900")
end
