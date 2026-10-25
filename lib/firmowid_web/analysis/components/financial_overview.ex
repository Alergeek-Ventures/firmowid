defmodule FirmowidWeb.Analysis.Components.FinancialOverview do
  @moduledoc """
  Annual totals of `Firmowid.Ash.Analysis.YearSummary` with a monthly net result
  bar chart and a disclosure with the exact monthly amounts.

  Months are buttons sending `select-month` with the ISO date of the month.
  Decimal amounts remain authoritative; bar lengths are only a float projection.
  """
  use FirmowidWeb, :html

  attr :summary, :map, required: true, doc: "`YearSummary.get/3` result"
  attr :tag_filters, :list, required: true, doc: "tag filters the summary was fetched with"
  attr :selected_month, Date, default: nil, doc: "first day of the highlighted month"

  @doc "Renders the year's income, expenses, net result and margin, then the monthly net results."
  @spec overview(map()) :: Phoenix.LiveView.Rendered.t()
  def overview(assigns) do
    %{summary: summary} = assigns

    assigns =
      assigns
      |> assign(:currency, summary.currency)
      |> assign(:kpis, kpis(summary.totals, summary.currency))
      |> assign(:chart, chart(summary.months, summary.currency))

    ~H"""
    <section
      id="analysis-financial-overview"
      aria-labelledby="analysis-month-results-title"
      class="@container flex flex-col rounded-xl border border-grey-200 bg-white"
    >
      <dl class="grid grid-cols-[repeat(auto-fit,minmax(min(100%,9rem),1fr))] gap-x-4 gap-y-3 border-be border-grey-200 p-4 @xl:grid-cols-[repeat(auto-fit,minmax(10rem,1fr))] @xl:gap-x-6 @xl:gap-y-4 @3xl:p-6">
        <div :for={kpi <- @kpis} id={kpi.id} class="flex min-w-0 flex-col gap-0.5 @xl:gap-1">
          <dt class="text-sm text-grey-700">{kpi.label}</dt>
          <dd class={[
            "text-base font-semibold whitespace-nowrap tabular-nums @xs:text-lg @xl:text-xl",
            result_styles(kpi.amount)
          ]}>
            {kpi.value}
          </dd>
        </div>
      </dl>
      <div class="flex flex-col gap-4 p-4 @3xl:p-6">
        <h2 id="analysis-month-results-title" class="text-h5 font-medium text-grey-900">
          {gettext("Net result by month")}
        </h2>
        <.empty_state
          :if={@chart == :empty}
          id="analysis-month-results-empty"
          title={
            if @tag_filters == [],
              do: gettext("No income or expenses in %{year}.", year: @summary.year),
              else:
                gettext("The selected categories have no entries in %{year}.", year: @summary.year)
          }
        />
        <ol
          :if={@chart != :empty}
          id="analysis-month-results"
          style={"--loss-share: #{@chart.loss_share}%; --profit-share: #{@chart.profit_share}%"}
          class="grid h-44 grid-cols-12 gap-0.5 @2xl:h-56 @2xl:gap-1"
        >
          <li :for={bar <- @chart.bars} class="min-w-0">
            <FirmowidUI.Components.Button.button
              id={"analysis-month-result-#{bar.month.month}"}
              type="button"
              variant="unstyled"
              phx-click="select-month"
              phx-value-month={Date.to_iso8601(bar.month)}
              aria-pressed={to_string(bar.month == @selected_month)}
              aria-label={bar.description}
              title={bar.description}
              class={[
                "grid size-full min-w-0 cursor-pointer grid-rows-[minmax(0,1fr)_auto] gap-1 rounded-md px-0.5 py-2 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-teal-700 active:bg-grey-200 @2xl:px-1 pointer-fine:hover:bg-grey-100",
                bar.month == @selected_month && "bg-teal-100"
              ]}
            >
              <span class="flex h-full flex-col-reverse" aria-hidden="true">
                <span class="flex shrink-0 grow-0 basis-(--loss-share) flex-col">
                  <span
                    :if={bar.side == :loss}
                    style={"--bar: #{bar.length}%"}
                    class="block h-(--bar) min-h-0.5 w-full max-w-14 self-center rounded-xs bg-brick-700"
                  />
                </span>
                <span class="flex shrink-0 grow-0 basis-(--profit-share) flex-col justify-end border-be border-grey-500">
                  <span
                    :if={bar.side == :profit}
                    style={"--bar: #{bar.length}%"}
                    class="block h-(--bar) min-h-0.5 w-full max-w-14 self-center rounded-xs bg-teal-600"
                  />
                </span>
              </span>
              <span class={[
                "text-center text-xs @2xl:text-sm",
                bar_label_styles(bar, @selected_month)
              ]}>
                {bar.label}
              </span>
            </FirmowidUI.Components.Button.button>
          </li>
        </ol>
        <details :if={@chart != :empty} id="analysis-month-amounts" class="group">
          <summary class="inline-flex min-h-11 cursor-pointer items-center gap-2 text-sm font-medium text-grey-900 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-teal-700">
            <.icon name="hero-chevron-right-mini" class="size-4 group-open:rotate-90" />
            {gettext("Monthly amounts")}
          </summary>
          <div class="overflow-x-auto">
            <table class="w-full text-sm">
              <thead>
                <tr class="border-be border-grey-200 text-grey-700">
                  <th scope="col" class="py-2 pe-4 text-start font-normal">{gettext("Month")}</th>
                  <th scope="col" class="py-2 ps-4 text-end font-normal">{gettext("Income")}</th>
                  <th scope="col" class="py-2 ps-4 text-end font-normal">{gettext("Expenses")}</th>
                  <th scope="col" class="py-2 ps-4 text-end font-normal">{gettext("Net result")}</th>
                </tr>
              </thead>
              <tbody>
                <tr
                  :for={month <- @summary.months}
                  id={"analysis-month-amounts-#{month.month.month}"}
                  class={[
                    "border-be border-grey-100",
                    month.month == @selected_month && "bg-teal-100 font-medium"
                  ]}
                >
                  <th scope="row" class="py-2 pe-4 text-start font-normal">
                    {month_name(month.month)}
                  </th>
                  <td class="py-2 ps-4 text-end whitespace-nowrap tabular-nums">
                    {money(@currency, month.totals.total_income)}
                  </td>
                  <td class="py-2 ps-4 text-end whitespace-nowrap tabular-nums">
                    {money(@currency, Decimal.abs(month.totals.total_expenses))}
                  </td>
                  <td class={[
                    "py-2 ps-4 text-end whitespace-nowrap tabular-nums",
                    result_styles(month.totals.net_profit)
                  ]}>
                    {money(@currency, month.totals.net_profit)}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </details>
      </div>
    </section>
    """
  end

  defp kpis(totals, currency) do
    margin =
      if Decimal.positive?(totals.total_income) do
        [
          %{
            id: "analysis-year-margin",
            label: gettext("Margin"),
            amount: totals.net_profit,
            value:
              totals.net_profit
              |> Decimal.div(totals.total_income)
              |> Firmowid.Cldr.Number.to_string!(format: :percent, fractional_digits: 1)
          }
        ]
      else
        []
      end

    [
      %{id: "analysis-year-income", label: gettext("Income"), amount: totals.total_income},
      %{
        id: "analysis-year-expenses",
        label: gettext("Expenses"),
        amount: Decimal.abs(totals.total_expenses)
      },
      %{id: "analysis-year-net-result", label: gettext("Net result"), amount: totals.net_profit}
    ]
    |> Enum.map(&Map.put(&1, :value, money(currency, &1.amount)))
    |> Kernel.++(margin)
  end

  # Losses grow below and profits above one shared zero line; the arms are sized
  # by the largest loss and the largest profit so every bar uses the same scale.
  defp chart(months, currency) do
    if Enum.all?(months, &empty_month?/1) do
      :empty
    else
      results = Enum.map(months, & &1.totals.net_profit)

      max_profit =
        results
        |> Enum.filter(&Decimal.positive?/1)
        |> Enum.reduce(Decimal.new(0), &Decimal.max/2)

      max_loss =
        results
        |> Enum.filter(&Decimal.negative?/1)
        |> Enum.map(&Decimal.abs/1)
        |> Enum.reduce(Decimal.new(0), &Decimal.max/2)

      range = Decimal.add(max_profit, max_loss)

      %{
        loss_share: percent(max_loss, range),
        profit_share: percent(max_profit, range),
        bars: Enum.map(months, &bar(&1, currency, max_profit, max_loss))
      }
    end
  end

  defp bar(month, currency, max_profit, max_loss) do
    result = month.totals.net_profit
    empty? = empty_month?(month)
    name = month_name(month.month, "LLLL y")

    {side, length} =
      cond do
        Decimal.negative?(result) -> {:loss, percent(Decimal.abs(result), max_loss)}
        Decimal.positive?(result) -> {:profit, percent(result, max_profit)}
        true -> {nil, 0}
      end

    %{
      month: month.month,
      label: month_name(month.month),
      empty?: empty?,
      side: side,
      length: length,
      description:
        if empty? do
          gettext("%{month}: no entries", month: name)
        else
          gettext("%{month}: net result %{amount}", month: name, amount: money(currency, result))
        end
    }
  end

  defp empty_month?(month), do: month.totals.income_categories == [] and month.totals.expense_categories == []

  defp percent(amount, total) do
    if Decimal.eq?(total, 0),
      do: 0,
      else: amount |> Decimal.div(total) |> Decimal.to_float() |> Kernel.*(100) |> Float.round(2)
  end

  defp bar_label_styles(bar, selected_month) do
    cond do
      bar.month == selected_month -> "font-semibold text-grey-900"
      bar.empty? -> "text-grey-600"
      true -> "text-grey-700"
    end
  end

  defp result_styles(amount), do: if(Decimal.negative?(amount), do: "text-brick-700", else: "text-grey-900")

  defp money(currency, amount), do: Money.to_string!(Money.new(currency, amount))

  defp month_name(month, format \\ "LLL") do
    month
    |> Firmowid.Cldr.Date.to_string!(format: format, locale: Gettext.get_locale(Firmowid.Gettext))
    |> String.capitalize()
  end
end
