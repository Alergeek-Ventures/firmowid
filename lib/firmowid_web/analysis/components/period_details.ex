defmodule FirmowidWeb.Analysis.Components.PeriodDetails do
  @moduledoc """
  The selected period of the analysis (a month, several months or the year):
  its result, what is left of every 100 zł of income as a strip of the largest
  costs (and the same for the last three months of a longer period), then
  costs and income by template category with their counterparties, monthly
  trend and amount out of every 100 zł of income. A single month compares each category
  with its usual monthly amount. Unpaid invoices are mentioned beside the
  totals they are missing from. A category's counterparties expand from the
  category. With `can_edit`, a counterparty row opens the
  categories of the organization's industry to confirm or move it to.
  Sends `confirm-category` (with the group's `side`, `key`, `suggestion` and
  `source`, and the chosen `category`).
  """
  use FirmowidWeb, :html

  import FirmowidWeb.Analysis.Utilities.Amounts, only: [whole_money: 1]

  alias Firmowid.Analysis.IndustryTemplate
  alias Firmowid.Cldr.Number

  @categories_at_once 4
  @examples 3
  @notable_change Decimal.new("0.1")
  @material_share Decimal.new("0.02")

  attr :title, :string, required: true

  attr :months, :list,
    required: true,
    doc: "the period's months of the `YearSummary.get/3` result"

  attr :groups, :list,
    required: true,
    doc: "`CategoryReview.period/3` groups, or nil when tag filters leave categories out"

  attr :industry, :atom,
    default: nil,
    doc: "organization's industry, for the categories a counterparty can move to"

  attr :can_edit, :boolean,
    default: false,
    doc: "whether the member may confirm counterparty categories"

  @doc "Renders the period's result and its costs and income by category."
  @spec details(map()) :: Phoenix.LiveView.Rendered.t()
  def details(assigns) do
    %{months: months, groups: groups} = assigns
    income = sum(months, & &1.totals.total_income)
    result = sum(months, & &1.totals.net_profit)
    dates = Enum.map(months, & &1.month)

    assigns =
      assign(assigns,
        result: result,
        margin:
          if(Decimal.positive?(income),
            do:
              result
              |> Decimal.div(income)
              |> Number.to_string!(format: :percent, fractional_digits: 1)
          ),
        expenses:
          column(
            groups,
            :expenses,
            months |> sum(& &1.totals.total_expenses) |> Decimal.abs(),
            sum(months, &unpaid(&1, :expenses)),
            income,
            dates
          ),
        income: column(groups, :income, income, sum(months, &unpaid(&1, :income)), income, dates)
      )

    # Every amount out of 100 zł is rounded once, so the strip and the rows agree.
    {costs, kept} = per_100_of(assigns.expenses.categories, income, result)
    {incomes, _kept} = per_100_of(assigns.income.categories, income, Decimal.new(0))

    assigns =
      assign(assigns,
        expenses: %{assigns.expenses | categories: costs},
        income: %{assigns.income | categories: incomes},
        story: story(costs, kept, income),
        recent: recent(assigns.expenses.categories, months)
      )

    ~H"""
    <section
      id="analysis-period"
      aria-labelledby="analysis-period-title"
      class="@container flex flex-col gap-10"
    >
      <header class="flex flex-wrap items-baseline justify-between gap-x-6 gap-y-2">
        <h2 id="analysis-period-title" class="text-2xl font-semibold text-grey-900">{@title}</h2>
        <div :if={@months != []} class="flex flex-col gap-0.5">
          <p id="analysis-period-result" class={result_styles(@result)}>
            {gettext("Result %{amount}", amount: whole_money(@result))}
          </p>
          <p :if={@margin} class="text-sm text-grey-700 tabular-nums">
            {gettext("Margin %{margin}", margin: @margin)}
          </p>
        </div>
      </header>
      <p :if={@months == []} id="analysis-period-open" class="text-sm text-grey-700">
        {gettext("No month of this period is closed yet.")}
      </p>
      <.story :if={@story} story={@story} recent={@recent} />
      <div
        :if={@months != []}
        class="grid grid-cols-[minmax(0,1fr)] gap-x-16 gap-y-12 @5xl:grid-cols-2"
      >
        <.column
          id="analysis-period-expenses"
          title={gettext("Costs")}
          column={@expenses}
          industry={@industry}
          can_edit={@can_edit}
        />
        <.column
          id="analysis-period-income"
          title={gettext("Income")}
          column={@income}
          industry={@industry}
          can_edit={@can_edit}
        />
      </div>
    </section>
    """
  end

  attr :story, :map, required: true
  attr :recent, :map, default: nil

  # One sentence and one strip: where every 100 zł of income went and what stayed.
  defp story(assigns) do
    ~H"""
    <div id="analysis-period-story" class="flex flex-col gap-6">
      <p class="max-w-[22ch] text-2xl/tight font-semibold text-balance text-grey-900 @xl:text-3xl/tight">
        {if @story.kept,
          do:
            gettext("Of every %{hundred} of income, %{amount} stayed.",
              hundred: whole_money(100),
              amount: whole_money(@story.kept)
            ),
          else:
            gettext("For every %{hundred} of income, %{amount} went out.",
              hundred: whole_money(100),
              amount: whole_money(@story.spent)
            )}
      </p>
      <div class="flex flex-col gap-3">
        <.strip segments={@story.segments} class="h-12 rounded-lg @2xl:h-14" />
        <ul class="flex flex-col @2xl:flex-row @2xl:gap-0.5">
          <li
            :for={segment <- @story.segments}
            style={"flex: #{segment.share} 1 0"}
            class="grid min-w-0 grid-cols-[0.75rem_minmax(0,1fr)_auto] items-baseline gap-x-2 border-be border-grey-200 py-2 last:border-be-0 @2xl:flex @2xl:min-w-16 @2xl:flex-col @2xl:gap-0.5 @2xl:border-be-0 @2xl:py-0"
          >
            <span
              class={["size-2.5 self-center rounded-xs @2xl:hidden", tone_styles(segment.tone)]}
              aria-hidden="true"
            />
            <span class={[
              "order-last text-xl font-semibold whitespace-nowrap tabular-nums @2xl:order-first",
              segment.key == :kept && "text-teal-700"
            ]}>
              {whole_money(segment.per_100)}
            </span>
            <span class="min-w-0 text-sm text-grey-700 @2xl:truncate">{segment.label}</span>
          </li>
        </ul>
      </div>
      <div :if={@recent} class="flex items-center gap-3 text-xs text-grey-700">
        <span class="shrink-0 font-medium">{@recent.label}</span>
        <.strip segments={@recent.segments} class="h-2 grow rounded-xs" />
        <span :if={@recent.kept} class="shrink-0 font-medium text-teal-700 tabular-nums">
          {gettext("%{amount} stayed", amount: whole_money(@recent.kept))}
        </span>
        <span
          :if={!@recent.kept and @recent.spent > 100}
          class="shrink-0 font-medium text-brick-700 tabular-nums"
        >
          {gettext("loss %{amount}", amount: whole_money(@recent.spent - 100))}
        </span>
      </div>
    </div>
    """
  end

  attr :segments, :list, required: true
  attr :class, :string, required: true

  defp strip(assigns) do
    ~H"""
    <div class={["flex gap-0.5 overflow-hidden", @class]} aria-hidden="true">
      <span
        :for={segment <- @segments}
        :if={segment.share > 0}
        class={["min-w-1", tone_styles(segment.tone)]}
        style={"flex: #{segment.share} 1 0"}
      />
    </div>
    """
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :column, :map, required: true
  attr :industry, :atom, required: true
  attr :can_edit, :boolean, required: true

  defp column(assigns) do
    ~H"""
    <section id={@id} aria-labelledby={"#{@id}-title"} class="flex min-w-0 flex-col gap-8">
      <header class="flex flex-col gap-1">
        <div class="flex items-baseline justify-between gap-3">
          <h3 id={"#{@id}-title"} class="text-lg font-semibold text-grey-900">{@title}</h3>
          <span class="text-lg font-semibold text-grey-900 tabular-nums">{whole_money(@column.total)}</span>
        </div>
        <p :if={Decimal.positive?(@column.unpaid)} class="text-sm text-grey-700">
          {gettext("Not included: unpaid invoices %{amount}", amount: whole_money(@column.unpaid))}
        </p>
      </header>
      <.level
        id={"#{@id}-categories"}
        categories={@column.categories}
        section={@id}
        column={@column}
        industry={@industry}
        can_edit={@can_edit}
      />
    </section>
    """
  end

  attr :id, :string, required: true
  attr :categories, :list, required: true
  attr :column, :map, required: true
  attr :industry, :atom, required: true
  attr :can_edit, :boolean, required: true
  attr :section, :string, required: true, doc: "the column's id, prefixing its categories' ids"
  attr :nested, :boolean, default: false
  attr :parent, :string, default: nil, doc: "the id of the contents a nested level leads back to"

  # At most four categories at once: the largest and the rest, which zooms in on its
  # categories in their place; a nested level leads back.
  defp level(assigns) do
    {shown, rest} =
      if length(assigns.categories) <= @categories_at_once,
        do: {assigns.categories, []},
        else: Enum.split(assigns.categories, @categories_at_once - 1)

    # The browser keeps a toggled zoom across server renders by id; new rest categories reset it.
    zoom = :erlang.phash2(Enum.map(rest, & &1.key))

    assigns =
      assign(assigns,
        shown: shown,
        rest: rest,
        here: "#{assigns.id}-here-#{zoom}",
        next: "#{assigns.id}-next-#{zoom}"
      )

    ~H"""
    <div id={@id} class="flex flex-col gap-8" hidden={@nested}>
      <div id={@here} class="contents">
        <FirmowidUI.Components.Button.button
          :if={@nested}
          type="button"
          variant="unstyled"
          class="group -mb-4 flex cursor-pointer items-center gap-1 self-start text-sm text-grey-700 min-block-6"
          phx-click={
            JS.toggle_attribute({"hidden", ""}, to: "##{@parent}")
            |> JS.toggle_attribute({"hidden", ""}, to: "##{@id}")
            |> JS.focus(to: "##{@parent}-rest button")
          }
        >
          <Lucideicons.chevron_left class="size-3.5" aria-hidden="true" />
          <span class="underline-offset-[.2em] pointer-fine:group-hover:underline">{gettext("Back")}</span>
        </FirmowidUI.Components.Button.button>
        <.category
          :for={category <- @shown}
          id={"#{@section}-#{category.key || "unassigned"}"}
          category={category}
          column={@column}
          industry={@industry}
          can_edit={@can_edit}
        />
        <div :if={@rest != []} id={"#{@here}-rest"} class="flex flex-col gap-1">
          <h4 class="text-sm">
            <FirmowidUI.Components.Button.button
              type="button"
              variant="unstyled"
              class="group flex w-full cursor-pointer items-baseline gap-1 text-start min-block-6"
              aria-controls={@next}
              phx-click={
                JS.toggle_attribute({"hidden", ""}, to: "##{@here}")
                |> JS.toggle_attribute({"hidden", ""}, to: "##{@next}")
                |> JS.focus_first(to: "##{@next}")
              }
            >
              <span class="font-semibold text-grey-900 underline-offset-[.2em] pointer-fine:group-hover:underline">
                {ngettext(
                  "The rest · %{count} category",
                  "The rest · %{count} categories",
                  length(@rest)
                )}
                <Lucideicons.chevron_right
                  class="ms-0.5 inline size-3.5 align-[-0.15em] text-grey-700"
                  aria-hidden="true"
                />
              </span>
              <span class="ms-auto shrink-0 ps-2 font-semibold text-grey-900 tabular-nums">
                {whole_money(sum(@rest, & &1.amount))}
              </span>
            </FirmowidUI.Components.Button.button>
          </h4>
          <p class="text-sm text-grey-700 tabular-nums">
            {per_100_caption(sum_per_100(@rest))}
          </p>
          <p class="truncate text-sm text-grey-600">
            {Enum.map_join(@rest, ", ", &label(&1.key, @can_edit))}
          </p>
        </div>
      </div>
      <.level
        :if={@rest != []}
        id={@next}
        categories={@rest}
        parent={@here}
        section={@section}
        column={@column}
        industry={@industry}
        can_edit={@can_edit}
        nested
      />
    </div>
    """
  end

  attr :id, :string, required: true
  attr :category, :map, required: true
  attr :column, :map, required: true
  attr :industry, :atom, required: true
  attr :can_edit, :boolean, required: true

  # A few examples show what the category holds; the header lists all its counterparties.
  defp category(assigns) do
    {examples, more} = Enum.split(assigns.category.groups, @examples)
    # As with zooming, other counterparties to expand get a fresh, collapsed list.
    more_id = "#{assigns.id}-more-#{:erlang.phash2(Enum.map(more, & &1.key))}"
    assigns = assign(assigns, examples: examples, more: more, more_id: more_id)

    ~H"""
    <div id={@id} class="flex flex-col gap-1">
      <h4 class="flex items-center gap-3 text-sm">
        <span
          class={["size-2.5 shrink-0 rounded-xs", tone_styles(@category.tone)]}
          aria-hidden="true"
        />
        <FirmowidUI.Components.Button.button
          type="button"
          variant="unstyled"
          id={"#{@more_id}-toggle"}
          disabled={@more == []}
          class="group flex w-full cursor-pointer items-center gap-1 text-start min-block-6 disabled:cursor-default"
          aria-expanded={@more != [] && "false"}
          aria-controls={@more != [] && @more_id}
          phx-click={
            JS.toggle_attribute({"hidden", ""}, to: "##{@more_id}")
            |> JS.toggle_attribute({"aria-expanded", "true", "false"})
          }
        >
          <span class="min-w-0 font-semibold text-grey-900 underline-offset-[.2em] pointer-fine:group-enabled:group-hover:underline">
            {label(@category.key, @can_edit)}
            <Lucideicons.chevron_down
              :if={@more != []}
              class="ms-0.5 inline size-3.5 align-[-0.15em] text-grey-700 group-aria-expanded:rotate-180 motion-safe:transition-transform motion-safe:duration-200 motion-safe:ease-out"
              aria-hidden="true"
            />
          </span>
          <.sparkline
            :if={length(@category.monthly) >= 3}
            values={@category.monthly}
            side={@column.side}
          />
          <span class="shrink-0 ps-2 font-semibold text-grey-900 tabular-nums">
            {whole_money(@category.amount)}
          </span>
        </FirmowidUI.Components.Button.button>
      </h4>
      <p class="ps-5.5 text-sm text-grey-700 tabular-nums">
        {per_100_caption(@category.per_100)}
        <span :if={@category.average}>· {usual_caption(
          @category.amount,
          @category.average,
          @column.total
        )}</span>
      </p>
      <ul class="-mx-2 flex flex-col ps-5.5">
        <.counterparty
          :for={group <- @examples}
          group={group}
          industry={@industry}
          can_edit={@can_edit}
        />
      </ul>
      <ul :if={@more != []} id={@more_id} class="-mx-2 flex flex-col ps-5.5" hidden>
        <.counterparty :for={group <- @more} group={group} industry={@industry} can_edit={@can_edit} />
      </ul>
    </div>
    """
  end

  attr :values, :list, required: true
  attr :side, :atom, required: true

  # The category's amount in each month of the period, scaled to its own largest month.
  defp sparkline(assigns) do
    max = assigns.values |> Enum.max(Decimal) |> Decimal.max(Decimal.new(1))
    step = 96 / (length(assigns.values) - 1)

    points =
      assigns.values
      |> Enum.with_index()
      |> Enum.map_join(" ", fn {value, index} ->
        y = 30 - Decimal.to_float(Decimal.div(value, max)) * 28
        "#{Float.round(index * step, 1)},#{Float.round(y, 1)}"
      end)

    assigns = assign(assigns, points: points)

    ~H"""
    <svg
      viewBox="0 0 96 32"
      preserveAspectRatio="none"
      class="ms-auto hidden h-7 w-20 shrink-0 overflow-visible @md:block"
      aria-hidden="true"
    >
      <polygon points={"0,32 #{@points} 96,32"} class={sparkline_fill_styles(@side)} />
      <polyline
        points={@points}
        fill="none"
        stroke-width="1.5"
        stroke-linejoin="round"
        vector-effect="non-scaling-stroke"
        class={sparkline_stroke_styles(@side)}
      />
    </svg>
    """
  end

  defp sparkline_fill_styles(:expenses), do: "fill-rust-100"
  defp sparkline_fill_styles(:income), do: "fill-teal-100"
  defp sparkline_stroke_styles(:expenses), do: "stroke-rust-700"
  defp sparkline_stroke_styles(:income), do: "stroke-teal-700"

  defp label(nil, true), do: gettext("Needs your choice")
  defp label(nil, false), do: gettext("Uncategorized")
  defp label(key, _can_edit), do: category_label(key)

  attr :group, :map, required: true
  attr :industry, :atom, required: true
  attr :can_edit, :boolean, required: true

  # Salaries paid through payroll are certain, so their row only names how many people.
  defp counterparty(%{group: %{people: people}} = assigns) when people != nil do
    ~H"""
    <li class="flex items-center gap-2 px-2 text-sm min-block-9">
      <span class="min-w-0 truncate text-grey-900">
        {ngettext("Payroll · %{count} person", "Payroll · %{count} people", @group.people)}
      </span>
      <span class="ms-auto shrink-0 text-grey-700 tabular-nums">{whole_money(@group.amount)}</span>
    </li>
    """
  end

  defp counterparty(%{can_edit: false} = assigns) do
    ~H"""
    <li class="flex items-center gap-2 px-2 text-sm min-block-9">
      <span class="min-w-0 truncate text-grey-700">{@group.name}</span>
      <span class="ms-auto shrink-0 text-grey-700 tabular-nums">{whole_money(@group.amount)}</span>
    </li>
    """
  end

  # The whole row opens the categories; the chosen one is confirmed right away.
  defp counterparty(assigns) do
    assigns =
      assign(
        assigns,
        :id,
        "analysis-counterparty-#{assigns.group.side}-#{:erlang.phash2({assigns.group.key, assigns.group.suggestion, assigns.group.source})}"
      )

    ~H"""
    <li>
      <FirmowidUI.Components.Button.button
        id={"#{@id}-trigger"}
        type="button"
        variant="unstyled"
        aria-haspopup="dialog"
        phx-click={show_popover("#{@id}-menu")}
        class="flex w-full cursor-pointer items-center gap-2 rounded-md px-2 text-start text-sm min-block-9 active:bg-grey-200 pointer-fine:hover:bg-white"
      >
        <span class={name_styles(@group.status)}>{@group.name}</span>
        <Lucideicons.check
          :if={@group.status == :confirmed}
          class="size-4 shrink-0 text-moss-700"
          aria-label={gettext("Confirmed")}
        />
        <span class="ms-auto shrink-0 text-grey-700 tabular-nums">{whole_money(@group.amount)}</span>
      </FirmowidUI.Components.Button.button>
      <.popover id={"#{@id}-menu"} reference_id={"#{@id}-trigger"} placement="bottom-end">
        <div class="flex max-h-(--popover-available-height) w-72 flex-col gap-1 overflow-y-auto overscroll-contain rounded-lg bg-white p-1 shadow-lg ring-1 ring-grey-700/10">
          <p class="px-3 pt-2 pb-1 text-xs text-grey-600">{reason(@group)}</p>
          <FirmowidUI.Components.Button.button
            :for={category <- category_options(@industry, @group)}
            type="button"
            variant="unstyled"
            phx-click={
              JS.push("confirm-category",
                value: %{
                  side: @group.side,
                  key: @group.key,
                  suggestion: to_string(@group.suggestion),
                  source: to_string(@group.source),
                  category: category
                }
              )
              |> hide_popover("#{@id}-menu")
            }
            class="flex cursor-pointer items-center justify-between gap-2 rounded-md px-3 text-start text-sm text-grey-900 min-block-9 active:bg-grey-200 pointer-fine:hover:bg-grey-100"
          >
            {category_label(category)}
            <Lucideicons.check
              :if={category == (@group.category || @group.suggestion)}
              class="size-4"
            />
          </FirmowidUI.Components.Button.button>
        </div>
      </.popover>
    </li>
    """
  end

  # Counterparties sit under their confirmed category, else under the suggestion, largest first.
  defp column(nil, side, total, unpaid, revenue, _dates),
    do: %{side: side, total: total, unpaid: unpaid, revenue: revenue, categories: []}

  defp column(groups, side, total, unpaid, revenue, dates) do
    categories =
      groups
      |> Enum.filter(&(&1.side == side))
      |> Enum.group_by(&(&1.category || &1.suggestion))
      |> Enum.map(fn {key, groups} ->
        %{
          key: key,
          amount: sum(groups, & &1.amount),
          average: if(hd(groups).average, do: sum(groups, & &1.average)),
          monthly: Enum.map(dates, fn date -> sum(groups, &Map.get(&1.months, date, Decimal.new(0))) end),
          groups:
            groups
            |> Enum.filter(&Decimal.positive?(&1.amount))
            |> Enum.sort_by(& &1.amount, {:desc, Decimal})
        }
      end)
      |> Enum.filter(&Decimal.positive?(&1.amount))
      |> Enum.sort_by(& &1.amount, {:desc, Decimal})
      |> Enum.with_index(&Map.put(&1, :tone, {side, &2}))

    %{side: side, total: total, unpaid: unpaid, revenue: revenue, categories: categories}
  end

  # The strip shows the largest costs (all of them when they fit), the rest, and what stayed.
  defp story([], _kept, _income), do: nil

  defp story(categories, kept, income) do
    if Decimal.positive?(income) do
      {top, rest} =
        if length(categories) <= @categories_at_once,
          do: {categories, []},
          else: Enum.split(categories, @categories_at_once - 1)

      segments =
        Enum.map(top, &segment(&1.key, label(&1.key, false), &1.amount, &1.per_100, &1.tone)) ++
          if(rest == [],
            do: [],
            else: [
              segment(
                :rest,
                ngettext(
                  "The rest · %{count} category",
                  "The rest · %{count} categories",
                  length(rest)
                ),
                sum(rest, & &1.amount),
                sum_per_100(rest),
                {:expenses, @categories_at_once}
              )
            ]
          ) ++
          if(kept,
            do: [
              segment(
                :kept,
                gettext("stays in the company"),
                kept.amount,
                kept.per_100,
                :kept
              )
            ],
            else: []
          )

      spent =
        categories
        |> sum(& &1.amount)
        |> Decimal.mult(100)
        |> Decimal.div(income)
        |> Decimal.round(0)
        |> Decimal.to_integer()

      %{segments: segments, kept: kept && kept.per_100, spent: spent}
    end
  end

  defp segment(key, label, amount, per_100, tone),
    do: %{key: key, label: label, per_100: per_100, share: Decimal.to_float(amount), tone: tone}

  # A longer period also shows its last three months, the company's latest shape, in the
  # period's order and colours so each part matches its row.
  defp recent(categories, [_, _, _, _ | _] = months) do
    recent = Enum.take(months, -3)
    dates = Enum.map(recent, & &1.month)
    income = sum(recent, & &1.totals.total_income)
    result = sum(recent, & &1.totals.net_profit)

    costs =
      Enum.map(categories, fn category ->
        %{
          category
          | amount: category.monthly |> Enum.take(-3) |> Enum.reduce(Decimal.new(0), &Decimal.add/2)
        }
      end)

    with true <- Decimal.positive?(income),
         {costs, kept} = per_100_of(costs, income, result),
         %{} = story <- story(costs, kept, income) do
      %{
        label:
          gettext("%{from} – %{to}",
            from: month_name(List.first(dates)),
            to: month_name(List.last(dates))
          ),
        segments: story.segments,
        kept: story.kept,
        spent: story.spent
      }
    else
      _nothing -> nil
    end
  end

  defp recent(_categories, _months), do: nil

  # Gives each category its whole złoty out of every 100 of income, and returns what stayed
  # the same way. While something stays, costs and result add up to exactly 100, so the
  # rounding remainders go to the largest fractions; otherwise each is rounded alone.
  defp per_100_of(categories, income, result) do
    if Decimal.positive?(income) do
      kept? = Decimal.positive?(result)
      amounts = Enum.map(categories, & &1.amount) ++ if(kept?, do: [result], else: [])
      numbers = per_100(amounts, income, kept?)

      categories =
        categories
        |> Enum.zip(numbers)
        |> Enum.map(fn {category, n} -> Map.put(category, :per_100, n) end)

      {categories, if(kept?, do: %{amount: result, per_100: List.last(numbers)})}
    else
      {Enum.map(categories, &Map.put(&1, :per_100, nil)), nil}
    end
  end

  defp per_100(amounts, income, exact?) do
    raw = Enum.map(amounts, &Decimal.to_float(Decimal.div(Decimal.mult(&1, 100), income)))

    if exact? do
      floors = Enum.map(raw, &floor/1)

      bumped =
        raw
        |> Enum.with_index()
        |> Enum.sort_by(fn {value, _index} -> floor(value) - value end)
        |> Enum.take(max(100 - Enum.sum(floors), 0))
        |> MapSet.new(&elem(&1, 1))

      floors |> Enum.with_index() |> Enum.map(fn {n, i} -> if i in bumped, do: n + 1, else: n end)
    else
      Enum.map(raw, &round/1)
    end
  end

  # Without income nothing has a share of it.
  defp sum_per_100(categories) do
    if Enum.all?(categories, & &1.per_100), do: categories |> Enum.map(& &1.per_100) |> Enum.sum()
  end

  defp per_100_caption(nil), do: nil

  defp per_100_caption(per_100), do: gettext("%{amount} of every 100", amount: whole_money(per_100))

  # The three largest of a side are shades of its colour; the rest share the palest.
  defp tone_styles({:expenses, index}), do: Enum.at(~w(bg-rust-800 bg-rust-600 bg-rust-400), index, "bg-rust-200")

  defp tone_styles({:income, index}), do: Enum.at(~w(bg-teal-800 bg-teal-600 bg-teal-400), index, "bg-teal-200")

  defp tone_styles(:kept), do: "bg-teal-600"

  defp month_name(date), do: date |> Firmowid.Cldr.Date.to_string!(format: "LLL") |> String.capitalize()

  defp unpaid(%{unpaid: nil}, _side), do: Decimal.new(0)
  defp unpaid(%{unpaid: unpaid}, side), do: Map.fetch!(unpaid, side)

  # Deviations small relative to the category or to the whole column are noise.
  defp usual_caption(amount, average, total) do
    difference = amount |> Decimal.sub(average) |> Decimal.abs()
    change = if Decimal.positive?(average), do: amount |> Decimal.div(average) |> Decimal.sub(1)

    cond do
      change == nil ->
        gettext("not seen in other months")

      Decimal.lt?(Decimal.abs(change), @notable_change) or
          Decimal.lt?(difference, Decimal.mult(total, @material_share)) ->
        gettext("usually %{amount}", amount: whole_money(average))

      true ->
        gettext("usually %{amount} (%{change})",
          amount: whole_money(average),
          change: Number.to_string!(change, format: "+#,##0%;-#,##0%")
        )
    end
  end

  defp reason(%{status: :confirmed}), do: gettext("Your choice")
  defp reason(%{source: :certain}), do: gettext("Salary, ZUS or tax payment")

  defp reason(%{source: :jev, reason: [line | _]}), do: gettext("From the document: %{text}", text: line)

  defp reason(%{source: :jev}), do: gettext("Chosen from the counterparty's name")
  defp reason(_group), do: gettext("No suggestion yet; choose a category")

  defp category_options(industry, group) do
    options = IndustryTemplate.categories(industry, group.side)
    selected = group.category || group.suggestion
    if selected == nil or selected in options, do: options, else: options ++ [selected]
  end

  defp name_styles(:confirmed), do: "min-w-0 truncate text-grey-900"
  defp name_styles(_status), do: "min-w-0 truncate text-grey-700"

  defp result_styles(amount) do
    if Decimal.negative?(amount),
      do: "text-2xl font-semibold text-brick-700 tabular-nums",
      else: "text-2xl font-semibold text-grey-900 tabular-nums"
  end

  defp sum(rows, fun), do: Enum.reduce(rows, Decimal.new(0), &Decimal.add(fun.(&1), &2))

  @doc "Names a template category."
  @spec category_label(IndustryTemplate.category()) :: String.t()
  def category_label(:goods), do: gettext("Goods and supplies")
  def category_label(:subcontractors), do: gettext("Subcontractors")
  def category_label(:payroll), do: gettext("Salaries and social security")
  def category_label(:premises), do: gettext("Premises and utilities")
  def category_label(:software), do: gettext("Software and IT")
  def category_label(:marketing), do: gettext("Marketing")
  def category_label(:services), do: gettext("External services")
  def category_label(:fees), do: gettext("Fees and commissions")
  def category_label(:transport), do: gettext("Transport and fuel")
  def category_label(:equipment), do: gettext("Equipment and office supplies")
  def category_label(:taxes), do: gettext("Taxes")
  def category_label(:other), do: gettext("Other costs")
  def category_label(:sales), do: gettext("Sales")
  def category_label(:on_site), do: gettext("On-site sales")
  def category_label(:delivery), do: gettext("Delivery platforms")
  def category_label(:catering), do: gettext("Catering and events")
  def category_label(:store), do: gettext("In-store sales")
  def category_label(:online), do: gettext("Online sales")
  def category_label(:other_income), do: gettext("Other income")
end
