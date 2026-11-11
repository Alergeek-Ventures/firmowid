defmodule FirmowidWeb.Analysis.Components.PeriodDetails do
  @moduledoc """
  The selected period of the analysis (a month, several months or the year):
  its result, then costs and income by template category with their
  counterparties and shares of income. A single month compares each category
  with its usual monthly amount. Unpaid invoices are mentioned beside the
  totals they are missing from. A category's counterparties expand from the
  category. With `can_edit`, a counterparty row opens the
  categories of the organization's industry to confirm or move it to.
  Sends `confirm-category` (with the group's `side`, `key`, `suggestion` and
  `source`, and the chosen `category`).
  """
  use FirmowidWeb, :html

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

    assigns =
      assign(assigns,
        result: sum(months, & &1.totals.net_profit),
        expenses:
          column(
            groups,
            :expenses,
            months |> sum(& &1.totals.total_expenses) |> Decimal.abs(),
            sum(months, &unpaid(&1, :expenses)),
            income
          ),
        income: column(groups, :income, income, sum(months, &unpaid(&1, :income)), nil)
      )

    ~H"""
    <section
      id="analysis-period"
      aria-labelledby="analysis-period-title"
      class="@container flex flex-col gap-10"
    >
      <header class="flex flex-wrap items-baseline justify-between gap-x-6 gap-y-2">
        <h2 id="analysis-period-title" class="text-2xl font-semibold text-grey-900">{@title}</h2>
        <p id="analysis-period-result" class={result_styles(@result)}>
          {gettext("Result %{amount}", amount: whole_money(@result))}
        </p>
      </header>
      <div class="grid grid-cols-[minmax(0,1fr)] gap-x-16 gap-y-12 @5xl:grid-cols-2">
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
              <span class="ms-auto shrink-0 ps-2 text-grey-700 tabular-nums">
                {share_caption(sum(@rest, & &1.amount), @column.total, @column.revenue)}
              </span>
            </FirmowidUI.Components.Button.button>
          </h4>
          <.share_bar amount={sum(@rest, & &1.amount)} column={@column} />
          <p class="truncate text-sm text-grey-700">
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
      <h4 class="text-sm">
        <FirmowidUI.Components.Button.button
          type="button"
          variant="unstyled"
          id={"#{@more_id}-toggle"}
          disabled={@more == []}
          class="group flex w-full cursor-pointer items-baseline gap-1 text-start min-block-6 disabled:cursor-default"
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
          <span class="ms-auto shrink-0 ps-2 text-grey-700 tabular-nums">
            {share_caption(@category.amount, @column.total, @column.revenue)}
          </span>
        </FirmowidUI.Components.Button.button>
      </h4>
      <.share_bar amount={@category.amount} column={@column} />
      <p :if={@category.average} class="text-sm text-grey-700 tabular-nums">
        {usual_caption(@category.amount, @category.average, @column.total)}
      </p>
      <ul class="-mx-2 flex flex-col">
        <.counterparty
          :for={group <- @examples}
          group={group}
          industry={@industry}
          can_edit={@can_edit}
        />
      </ul>
      <ul :if={@more != []} id={@more_id} class="-mx-2 flex flex-col" hidden>
        <.counterparty :for={group <- @more} group={group} industry={@industry} can_edit={@can_edit} />
      </ul>
    </div>
    """
  end

  attr :amount, :any, required: true
  attr :column, :map, required: true

  defp share_bar(assigns) do
    ~H"""
    <div class="mb-1 h-1 rounded-full bg-grey-200" aria-hidden="true">
      <div
        class={bar_styles(@column.side)}
        style={"inline-size: #{share_percent(@amount, @column.total)}%"}
      />
    </div>
    """
  end

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
  defp column(nil, side, total, unpaid, revenue),
    do: %{side: side, total: total, unpaid: unpaid, revenue: revenue, categories: []}

  defp column(groups, side, total, unpaid, revenue) do
    categories =
      groups
      |> Enum.filter(&(&1.side == side))
      |> Enum.group_by(&(&1.category || &1.suggestion))
      |> Enum.map(fn {key, groups} ->
        %{
          key: key,
          amount: sum(groups, & &1.amount),
          average: if(hd(groups).average, do: sum(groups, & &1.average)),
          groups:
            groups
            |> Enum.filter(&Decimal.positive?(&1.amount))
            |> Enum.sort_by(& &1.amount, {:desc, Decimal})
        }
      end)
      |> Enum.filter(&Decimal.positive?(&1.amount))
      |> Enum.sort_by(& &1.amount, {:desc, Decimal})

    %{side: side, total: total, unpaid: unpaid, revenue: revenue, categories: categories}
  end

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

  defp share_caption(amount, _total, revenue) when revenue != nil do
    if Decimal.positive?(revenue),
      do:
        gettext("%{amount} · %{share} of income",
          amount: whole_money(amount),
          share: ratio(amount, revenue)
        ),
      else: whole_money(amount)
  end

  defp share_caption(amount, total, nil),
    do: gettext("%{amount} · %{share}", amount: whole_money(amount), share: ratio(amount, total))

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

  defp bar_styles(:expenses), do: "h-full rounded-full bg-rust-500"
  defp bar_styles(:income), do: "h-full rounded-full bg-teal-500"

  defp result_styles(amount) do
    if Decimal.negative?(amount),
      do: "text-2xl font-semibold text-brick-700 tabular-nums",
      else: "text-2xl font-semibold text-grey-900 tabular-nums"
  end

  defp share_percent(amount, total) do
    if Decimal.positive?(total),
      do:
        amount
        |> Decimal.div(total)
        |> Decimal.mult(100)
        |> Decimal.round(1)
        |> Decimal.to_float(),
      else: 0.0
  end

  defp ratio(amount, total) do
    if Decimal.positive?(total),
      do: amount |> Decimal.div(total) |> Number.to_string!(format: :percent),
      else: ""
  end

  defp sum(rows, fun), do: Enum.reduce(rows, Decimal.new(0), &Decimal.add(fun.(&1), &2))

  defp whole_money(amount), do: Number.to_string!(amount, currency: :PLN, fractional_digits: 0)

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
