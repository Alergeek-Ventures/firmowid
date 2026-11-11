defmodule FirmowidWeb.Analysis.Components.FinancialOverview do
  @moduledoc """
  A net result bar for each month of the analysed period, labelled with the
  rounded result on wider screens. Each bar has a
  tooltip with the month's income, expenses and unpaid invoices. A month not
  closed yet (still running, or with more than two unpaid invoices) has no bar
  and cannot be selected.

  Months are buttons sending `select-month` with the month's ISO date; a period
  over several years marks each first month of a year with the year.
  Decimal amounts remain authoritative; bar lengths are only a float projection.
  """
  use FirmowidWeb, :html

  alias Firmowid.Cldr.Number

  attr :summary, :map,
    required: true,
    doc: "the period's `months` of `YearSummary.get/3` results with their combined `totals` and `currency`"

  attr :tag_filters, :list, required: true, doc: "tag filters the summary was fetched with"

  attr :selected_month, Date, default: nil, doc: "first day of the highlighted month"

  @doc "Renders the monthly net results of the period."
  @spec overview(map()) :: Phoenix.LiveView.Rendered.t()
  def overview(assigns) do
    %{summary: summary} = assigns

    assigns =
      assigns
      |> assign(:currency, summary.currency)
      |> assign(:chart, chart(summary.months))

    ~H"""
    <section
      id="analysis-financial-overview"
      aria-label={gettext("Net result by month")}
      class="@container flex flex-col gap-6 rounded-xl border border-grey-200 bg-white p-4 @3xl:p-6"
    >
      <p :if={@chart == :empty} id="analysis-month-results-empty" class="text-sm text-grey-700">
        {if @tag_filters == [],
          do: gettext("No income or expenses in this period."),
          else: gettext("The selected categories have no entries in this period.")}
      </p>
      <ol
        :if={@chart != :empty}
        id="analysis-month-results"
        style={"--loss-share: #{@chart.loss_share}%; --profit-share: #{@chart.profit_share}%; grid-template-columns: repeat(#{length(@chart.bars)}, minmax(0, 1fr))"}
        class="grid h-52 gap-0.5 @2xl:gap-1"
      >
        <li :for={bar <- @chart.bars} class="min-w-0">
          <FirmowidUI.Components.Button.button
            id={"analysis-month-result-#{Date.to_iso8601(bar.month)}"}
            type="button"
            variant="unstyled"
            phx-click={!bar.open? && "select-month"}
            phx-value-month={Date.to_iso8601(bar.month)}
            aria-disabled={bar.open? && "true"}
            aria-pressed={to_string(bar.month == @selected_month)}
            aria-label={bar.name}
            aria-describedby={"analysis-month-tooltip-#{Date.to_iso8601(bar.month)}"}
            class={[
              "group relative grid size-full min-w-0 cursor-pointer grid-rows-[minmax(0,1fr)_auto] gap-2 rounded-md px-0.5 pt-6 pb-2 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-teal-700 active:not-aria-disabled:bg-grey-200 aria-disabled:cursor-default @2xl:px-1 pointer-fine:not-aria-disabled:hover:bg-grey-100",
              bar.month == @selected_month && "bg-teal-100"
            ]}
          >
            <span class="flex h-full flex-col-reverse pb-5" aria-hidden="true">
              <span class="relative shrink-0 grow-0 basis-(--loss-share)">
                <.bar_mark :if={bar.mark && bar.mark.side == :loss} mark={bar.mark} />
              </span>
              <span class="relative shrink-0 grow-0 basis-(--profit-share) border-be border-grey-300">
                <.bar_mark :if={bar.mark && bar.mark.side == :profit} mark={bar.mark} />
              </span>
            </span>
            <span class={["text-center text-xs @2xl:text-sm", bar_label_styles(bar, @selected_month)]}>
              {bar.label}
              <span :if={bar.year} class="block text-xs font-normal text-grey-600">
                {if bar.year != :none, do: bar.year, else: raw("&nbsp;")}
              </span>
            </span>
            <.month_tooltip bar={bar} currency={@currency} />
          </FirmowidUI.Components.Button.button>
        </li>
      </ol>
    </section>
    """
  end

  attr :mark, :map, required: true

  # The rounded result sits at the bar's free end, above a profit and below a loss.
  defp bar_mark(assigns) do
    ~H"""
    <span
      style={"--bar: #{@mark.length}%"}
      class={[
        "absolute inset-x-0 mx-auto block h-(--bar) min-h-0.5 w-full max-w-10",
        if(@mark.side == :loss,
          do: "top-0 rounded-b-sm bg-brick-700",
          else: "bottom-0 rounded-t-sm bg-teal-600"
        )
      ]}
    >
      <span class={[
        "absolute inset-x-0 hidden text-center text-xs whitespace-nowrap tabular-nums @xl:block",
        if(@mark.side == :loss, do: "-bottom-5 text-brick-700", else: "-top-5 text-grey-700")
      ]}>
        {@mark.label}
      </span>
    </span>
    """
  end

  attr :bar, :map, required: true
  attr :currency, :string, required: true

  # Shown on hover and keyboard focus; it also describes the month button for screen readers.
  defp month_tooltip(assigns) do
    ~H"""
    <span
      id={"analysis-month-tooltip-#{Date.to_iso8601(@bar.month)}"}
      role="tooltip"
      class={[
        "pointer-events-none absolute top-full z-10 mt-1 hidden w-72 flex-col gap-2 rounded-lg border border-grey-200 bg-white p-4 text-start shadow-lg group-focus-visible:flex pointer-fine:group-hover:flex",
        tooltip_alignment_styles(@bar.align)
      ]}
    >
      <span class="flex items-center justify-between gap-2">
        <span class="text-sm font-medium text-grey-900">{@bar.name}</span>
        <span
          :if={@bar.open?}
          class="rounded-full bg-grey-100 px-2 py-0.5 text-xs font-medium text-grey-800"
        >
          {pgettext("month", "Not closed")}
        </span>
      </span>
      <span :if={@bar.open?} class="text-sm text-grey-700">
        {gettext(
          "The result appears once the month ends and at most two of its invoices wait for payment."
        )}
      </span>
      <span :if={not @bar.open? and @bar.empty?} class="text-sm text-grey-700">
        {gettext("No entries")}
      </span>
      <span :if={not @bar.open? and not @bar.empty?} class="flex flex-col gap-1">
        <span class={["text-lg font-semibold tabular-nums", result_styles(@bar.result)]}>
          {money(@currency, @bar.result)}
        </span>
        <span class="grid grid-cols-[1fr_auto] gap-x-4 gap-y-0.5 text-xs">
          <%= for {label, value} <- @bar.rows do %>
            <span class="text-grey-700">{label}</span>
            <span class="text-end text-grey-900 tabular-nums">{value}</span>
          <% end %>
        </span>
      </span>
    </span>
    """
  end

  # Bars near the chart's edges anchor the tooltip to that edge so it stays inside the chart.
  defp tooltip_alignment_styles(:start), do: "start-0"
  defp tooltip_alignment_styles(:end), do: "end-0"
  defp tooltip_alignment_styles(:center), do: "start-1/2 -translate-x-1/2"

  defp alignment(index, count) when index * 4 < count, do: :start
  defp alignment(index, count) when index * 4 >= count * 3, do: :end
  defp alignment(_index, _count), do: :center

  # Losses grow below and profits above one shared zero line; the arms are sized by the
  # largest loss and the largest profit of the closed months.
  defp chart(months) do
    if Enum.all?(
         months,
         &(empty_month?(&1) and not unpaid?(&1, :income) and not unpaid?(&1, :expenses))
       ) do
      :empty
    else
      results = for %{closed?: true} = month <- months, do: month.totals.net_profit

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
      years? = months |> Enum.map(& &1.month.year) |> Enum.uniq() |> length() > 1

      bars =
        months
        |> Enum.with_index()
        |> Enum.map(fn {month, index} ->
          month
          |> bar(max_profit, max_loss)
          |> Map.merge(%{
            month: month.month,
            label: month_name(month.month),
            name: month_name(month.month, "LLLL y"),
            year: year_label(years?, index, month.month),
            align: alignment(index, length(months))
          })
        end)

      %{
        loss_share: percent(max_loss, range),
        profit_share: percent(max_profit, range),
        bars: bars
      }
    end
  end

  defp bar(%{closed?: false}, _max_profit, _max_loss), do: %{open?: true, empty?: true, mark: nil}

  defp bar(month, max_profit, max_loss) do
    result = month.totals.net_profit

    %{
      open?: false,
      empty?: empty_month?(month) and not unpaid?(month, :income) and not unpaid?(month, :expenses),
      result: result,
      mark: mark(result, max_profit, max_loss),
      rows:
        Enum.filter(
          [
            {gettext("Income"), money("PLN", month.totals.total_income)},
            {gettext("Expenses"), money("PLN", Decimal.abs(month.totals.total_expenses))},
            unpaid?(month, :income) &&
              {gettext("Unpaid income"), "+" <> money("PLN", month.unpaid.income)},
            unpaid?(month, :expenses) &&
              {gettext("Unpaid expenses"), money("PLN", Decimal.negate(month.unpaid.expenses))}
          ],
          & &1
        )
    }
  end

  defp mark(amount, max_profit, max_loss) do
    label = Number.to_string!(amount, format: :short)

    cond do
      Decimal.negative?(amount) ->
        %{side: :loss, length: percent(Decimal.abs(amount), max_loss), label: label}

      Decimal.positive?(amount) ->
        %{side: :profit, length: percent(amount, max_profit), label: label}

      true ->
        nil
    end
  end

  defp unpaid?(%{unpaid: %{} = unpaid}, side), do: Decimal.positive?(Map.fetch!(unpaid, side))
  defp unpaid?(_month, _side), do: false

  defp empty_month?(month), do: month.totals.income_categories == [] and month.totals.expense_categories == []

  defp percent(amount, total) do
    if Decimal.eq?(total, 0),
      do: 0,
      else: amount |> Decimal.div(total) |> Decimal.to_float() |> Kernel.*(100) |> Float.round(2)
  end

  # Over several years each first month of a year shows it; the others keep its line, so bars stay level.
  defp year_label(false, _index, _month), do: nil

  defp year_label(true, index, %Date{month: number, year: year}) when index == 0 or number == 1, do: year

  defp year_label(true, _index, _month), do: :none

  defp bar_label_styles(bar, selected_month) do
    cond do
      bar.month == selected_month -> "font-semibold text-grey-900"
      bar.open? -> "text-grey-500"
      bar.empty? -> "text-grey-600"
      true -> "text-grey-700"
    end
  end

  defp result_styles(amount), do: if(Decimal.negative?(amount), do: "text-brick-700", else: "text-grey-900")

  defp money(currency, amount), do: Money.to_string!(Money.new(currency, amount))

  defp month_name(month, format \\ "LLL") do
    month
    |> Firmowid.Cldr.Date.to_string!(format: format)
    |> String.capitalize()
  end
end
