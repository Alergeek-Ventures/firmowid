defmodule FirmowidWeb.Analysis.Components.FinancialOverview do
  @moduledoc """
  Annual totals of `Firmowid.Ash.Analysis.YearSummary` with a monthly net result
  bar chart. Each bar has a rich tooltip with the month's amounts and, without
  tag filters, an outline showing the result with the month's unpaid invoices.

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
      |> assign(:chart, chart(summary.months))

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
        <p :if={@chart == :empty} id="analysis-month-results-empty" class="text-sm text-grey-700">
          {if @tag_filters == [],
            do: gettext("No income or expenses in %{year}.", year: @summary.year),
            else: gettext("The selected categories have no entries in %{year}.", year: @summary.year)}
        </p>
        <ul
          :if={@chart != :empty and @chart.legend != []}
          id="analysis-month-results-legend"
          class="flex flex-wrap gap-x-4 gap-y-1 text-xs text-grey-700"
        >
          <li :for={item <- @chart.legend} class="inline-flex items-center gap-1.5">
            <span aria-hidden="true" class={legend_mark_styles(item)} />
            {legend_label(item)}
          </li>
        </ul>
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
              aria-label={bar.name}
              aria-describedby={"analysis-month-tooltip-#{bar.month.month}"}
              class={[
                "group relative grid size-full min-w-0 cursor-pointer grid-rows-[minmax(0,1fr)_auto] gap-1 rounded-md px-0.5 py-2 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-teal-700 active:bg-grey-200 @2xl:px-1 pointer-fine:hover:bg-grey-100",
                bar.month == @selected_month && "bg-teal-100"
              ]}
            >
              <span class="flex h-full flex-col-reverse" aria-hidden="true">
                <span class="relative shrink-0 grow-0 basis-(--loss-share)">
                  <.bar_mark :for={mark <- bar.marks} :if={mark.side == :loss} mark={mark} />
                </span>
                <span class="relative shrink-0 grow-0 basis-(--profit-share) border-be border-grey-500">
                  <.bar_mark :for={mark <- bar.marks} :if={mark.side == :profit} mark={mark} />
                </span>
              </span>
              <span class={[
                "text-center text-xs @2xl:text-sm",
                bar_label_styles(bar, @selected_month),
                bar.in_progress? &&
                  "underline decoration-teal-600 decoration-dotted decoration-2 underline-offset-4"
              ]}>
                {bar.label}
              </span>
              <.month_tooltip bar={bar} currency={@currency} />
            </FirmowidUI.Components.Button.button>
          </li>
        </ol>
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

  attr :mark, :map, required: true

  # Settled bars are filled; the result with unpaid invoices is a dashed outline drawn
  # over them. The part of a settled bar that unpaid invoices would cancel is lighter,
  # so a shorter outline inside it stays visible.
  defp bar_mark(assigns) do
    ~H"""
    <span
      style={"--bar: #{@mark.length}%"}
      class={[
        "absolute inset-x-0 mx-auto block h-(--bar) min-h-0.5 w-full max-w-14 rounded-xs",
        mark_styles(@mark),
        if(@mark.side == :loss, do: "top-0", else: "bottom-0")
      ]}
    />
    """
  end

  defp mark_styles(%{kind: :settled, side: :profit}), do: "bg-teal-600"
  defp mark_styles(%{kind: :settled, side: :loss}), do: "bg-brick-700"
  defp mark_styles(%{kind: :cancelled, side: :profit}), do: "bg-teal-600/30"
  defp mark_styles(%{kind: :cancelled, side: :loss}), do: "bg-brick-700/30"

  defp mark_styles(%{kind: :unpaid, side: :profit}), do: "border-[1.5px] border-dashed border-teal-800 bg-teal-600/15"

  defp mark_styles(%{kind: :unpaid, side: :loss}), do: "border-[1.5px] border-dashed border-brick-800 bg-brick-700/15"

  attr :bar, :map, required: true
  attr :currency, :string, required: true

  # Shown on hover and keyboard focus; it also describes the month button for screen readers.
  # Values lead: each result is the prominent figure under a keyed caption matching the
  # legend, with its income and expenses as quieter detail rows.
  defp month_tooltip(assigns) do
    ~H"""
    <span
      id={"analysis-month-tooltip-#{@bar.month.month}"}
      role="tooltip"
      class={[
        "pointer-events-none absolute bottom-full z-10 mb-1 hidden w-80 flex-col gap-3 rounded-lg border border-grey-200 bg-white p-4 text-start shadow-lg group-focus-visible:flex pointer-fine:group-hover:flex",
        tooltip_alignment_styles(@bar.month.month)
      ]}
    >
      <span class="flex items-center justify-between gap-2">
        <span class="text-sm font-medium text-grey-900">{@bar.name}</span>
        <span
          :if={@bar.in_progress?}
          class="rounded-full bg-teal-100 px-2 py-0.5 text-xs font-medium text-teal-800"
        >
          {pgettext("month", "In progress")}
        </span>
      </span>
      <span :if={@bar.empty?} class="text-sm text-grey-700">{gettext("No entries")}</span>
      <.tooltip_result
        :if={not @bar.empty?}
        key={legend_mark_styles(:settled, @bar.result)}
        label={legend_label(:settled)}
        result={money(@currency, @bar.result)}
        result_class={result_styles(@bar.result)}
        rows={[
          {gettext("Income"), money(@currency, @bar.income)},
          {gettext("Expenses"), money(@currency, @bar.expenses)}
        ]}
      />
      <.tooltip_result
        :if={@bar.unpaid}
        class="border-bs border-grey-200 pt-3"
        key={legend_mark_styles(:unpaid, @bar.accrual)}
        label={legend_label(:unpaid)}
        result={money(@currency, @bar.accrual)}
        result_class={result_styles(@bar.accrual)}
        rows={
          [
            Decimal.positive?(@bar.unpaid.income) &&
              {gettext("Unpaid income"), "+" <> money(@currency, @bar.unpaid.income)},
            Decimal.positive?(@bar.unpaid.expenses) &&
              {gettext("Unpaid expenses"), money(@currency, Decimal.negate(@bar.unpaid.expenses))}
          ]
          |> Enum.filter(& &1)
        }
      />
    </span>
    """
  end

  attr :key, :any, required: true
  attr :label, :string, required: true
  attr :result, :string, required: true
  attr :result_class, :string, required: true
  attr :rows, :list, required: true
  attr :class, :string, default: nil

  defp tooltip_result(assigns) do
    ~H"""
    <span class={["flex flex-col gap-1", @class]}>
      <span class="flex items-center gap-1.5 text-xs text-grey-700">
        <span aria-hidden="true" class={@key} />
        {@label}
      </span>
      <span class={["text-lg font-semibold tabular-nums", @result_class]}>{@result}</span>
      <span class="grid grid-cols-[1fr_auto] gap-x-4 gap-y-0.5 text-xs">
        <%= for {label, value} <- @rows do %>
          <span class="text-grey-700">{label}</span>
          <span class="text-end text-grey-900 tabular-nums">{value}</span>
        <% end %>
      </span>
    </span>
    """
  end

  # Edge months anchor the tooltip to their own edge so it stays inside the chart.
  defp tooltip_alignment_styles(month) when month <= 3, do: "start-0"
  defp tooltip_alignment_styles(month) when month >= 10, do: "end-0"
  defp tooltip_alignment_styles(_month), do: "start-1/2 -translate-x-1/2"

  defp legend_mark_styles(:settled),
    do: "h-2.5 w-3 rounded-xs bg-[linear-gradient(90deg,var(--color-teal-600)_50%,var(--color-brick-700)_50%)]"

  defp legend_mark_styles(:unpaid), do: legend_mark_styles(:unpaid, Decimal.new(1))

  defp legend_mark_styles(:cancelled),
    do:
      "h-2.5 w-3 rounded-xs bg-[linear-gradient(90deg,--alpha(var(--color-teal-600)/30%)_50%,--alpha(var(--color-brick-700)/30%)_50%)]"

  defp legend_mark_styles(:in_progress), do: "w-3 self-end border-be-2 border-dotted border-teal-600"

  # Tooltip keys take the color of the result they caption, like the bar they describe.
  defp legend_mark_styles(kind, amount) do
    [
      "h-2.5 w-3 shrink-0 rounded-xs",
      mark_styles(%{kind: kind, side: if(Decimal.negative?(amount), do: :loss, else: :profit)})
    ]
  end

  defp legend_label(:settled), do: gettext("Settled")
  defp legend_label(:unpaid), do: gettext("With unpaid invoices")
  defp legend_label(:cancelled), do: gettext("Offset by unpaid invoices")
  defp legend_label(:in_progress), do: gettext("Month in progress")

  # Losses grow below and profits above one shared zero line; the arms are sized
  # by the largest loss and the largest profit, of settled results and results
  # with unpaid invoices alike, so every mark uses the same scale.
  defp chart(months) do
    if Enum.all?(months, &(empty_month?(&1) and not unpaid?(&1))) do
      :empty
    else
      current_month = Date.beginning_of_month(Date.utc_today())
      results = Enum.flat_map(months, &[&1.totals.net_profit, accrual(&1)])

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
      bars = Enum.map(months, &bar(&1, current_month, max_profit, max_loss))

      %{
        loss_share: percent(max_loss, range),
        profit_share: percent(max_profit, range),
        bars: bars,
        legend:
          [:settled] ++
            if(Enum.any?(bars, & &1.unpaid), do: [:unpaid], else: []) ++
            if(Enum.any?(bars, fn bar -> Enum.any?(bar.marks, &(&1.kind == :cancelled)) end),
              do: [:cancelled],
              else: []
            ) ++
            if(Enum.any?(bars, & &1.in_progress?), do: [:in_progress], else: [])
      }
    end
  end

  defp bar(month, current_month, max_profit, max_loss) do
    result = month.totals.net_profit
    unpaid = if unpaid?(month), do: month.unpaid

    %{
      month: month.month,
      label: month_name(month.month),
      name: month_name(month.month, "LLLL y"),
      empty?: empty_month?(month) and unpaid == nil,
      in_progress?: month.month == current_month,
      result: result,
      income: month.totals.total_income,
      expenses: Decimal.abs(month.totals.total_expenses),
      unpaid: unpaid,
      accrual: accrual(month),
      marks:
        marks(
          mark(:settled, result, max_profit, max_loss),
          unpaid && mark(:unpaid, accrual(month), max_profit, max_loss)
        )
    }
  end

  # Unpaid invoices cancel the whole settled bar when the result changes sides,
  # otherwise only the part beyond the result with unpaid invoices.
  defp marks(nil, accrual), do: List.wrap(accrual)
  defp marks(settled, nil), do: [settled]

  defp marks(%{side: side} = settled, %{side: side} = accrual) when accrual.length < settled.length,
    do: [%{settled | kind: :cancelled}, %{settled | length: accrual.length}, accrual]

  defp marks(%{side: side} = settled, %{side: side} = accrual), do: [settled, accrual]
  defp marks(settled, accrual), do: [%{settled | kind: :cancelled}, accrual]

  defp mark(kind, amount, max_profit, max_loss) do
    cond do
      Decimal.negative?(amount) ->
        %{kind: kind, side: :loss, length: percent(Decimal.abs(amount), max_loss)}

      Decimal.positive?(amount) ->
        %{kind: kind, side: :profit, length: percent(amount, max_profit)}

      true ->
        nil
    end
  end

  defp accrual(%{unpaid: %{income: income, expenses: expenses}} = month),
    do: month.totals.net_profit |> Decimal.add(income) |> Decimal.sub(expenses)

  defp accrual(month), do: month.totals.net_profit

  defp unpaid?(%{unpaid: %{income: income, expenses: expenses}}),
    do: Decimal.positive?(income) or Decimal.positive?(expenses)

  defp unpaid?(_month), do: false

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
