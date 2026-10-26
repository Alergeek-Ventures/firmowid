defmodule FirmowidWeb.Analysis.Components.CategoryReview do
  @moduledoc """
  Owner session classifying a year's counterparties into industry template categories.

  A toolbar states how many counterparties are confirmed and accepts every
  suggestion at once. Costs and income are two ledger panels split into
  categories; each counterparty row can be confirmed or moved to another
  category from its menu. Sends `set-industry`, `confirm-suggestions`,
  `confirm-group` (with `side` and `category`) and `confirm-category` (with
  `side`, `key` and `category`).
  """
  use FirmowidWeb, :html

  alias Firmowid.Ash.Analysis.IndustryTemplate
  alias Firmowid.Cldr.Number

  attr :review, :map, required: true, doc: "`Firmowid.Ash.Analysis.get_category_review/3` result"
  attr :year, :integer, required: true

  @doc "Renders the session toolbar and the cost and income ledgers."
  @spec review(map()) :: Phoenix.LiveView.Rendered.t()
  def review(assigns) do
    groups = assigns.review.groups

    assigns =
      assigns
      |> assign(:confirmed, Enum.count(groups, &(&1.status == :confirmed)))
      |> assign(
        :suggested,
        Enum.count(groups, &(&1.status != :confirmed and &1.suggestion != nil))
      )
      |> assign(:total, length(groups))
      |> assign(:expenses, ledger(groups, :expenses))
      |> assign(:income, ledger(groups, :income))

    ~H"""
    <div id="analysis-category-review" class="@container flex flex-col gap-6">
      <div class="flex flex-wrap items-end justify-between gap-4">
        <div class="flex max-w-md flex-col gap-1 text-sm text-grey-700">
          <p id="analysis-category-status" class="font-medium text-grey-900">
            {gettext("%{confirmed} of %{total} counterparties confirmed",
              confirmed: @confirmed,
              total: @total
            )}
          </p>
          <p :if={@suggested > 0}>
            {gettext(
              "The rest have suggestions from invoice lines, transfer titles and known names. Confirm them all or correct single rows."
            )}
          </p>
          <p :if={@review.accuracy.total > 0} id="analysis-category-accuracy">
            {gettext("%{accepted} of %{total} suggestions accepted unchanged.",
              accepted: @review.accuracy.accepted,
              total: @review.accuracy.total
            )}
          </p>
        </div>
        <div class="flex flex-wrap items-end gap-3">
          <form id="analysis-industry" phx-change="set-industry" class="flex flex-col gap-1">
            <label for="analysis-industry-select" class="text-xs font-medium text-grey-700">
              {gettext("Industry")}
              <span
                :if={@review.inferred?}
                id="analysis-industry-inferred"
                class="font-normal text-grey-600"
              >
                · {gettext("recognized from counterparties")}
              </span>
            </label>
            <select
              id="analysis-industry-select"
              name="industry"
              class="h-11 rounded-lg border border-grey-200 bg-grey-50 ps-3 pe-9 text-sm text-grey-900"
            >
              <option
                :for={industry <- IndustryTemplate.industries()}
                value={industry}
                selected={industry == @review.industry}
              >
                {industry_label(industry)}
              </option>
            </select>
          </form>
          <FirmowidUI.Components.Button.button
            :if={@suggested > 0}
            id="analysis-confirm-suggestions"
            type="button"
            variant="special"
            phx-click="confirm-suggestions"
            phx-disable-with={gettext("Saving…")}
          >
            {gettext("Accept all suggestions (%{count})", count: @suggested)}
          </FirmowidUI.Components.Button.button>
        </div>
      </div>
      <div class="grid grid-cols-[minmax(0,1fr)] gap-6 @5xl:grid-cols-2">
        <.ledger
          id="analysis-expense-categories"
          title={gettext("Costs")}
          ledger={@expenses}
          revenue={@review.income.total}
          industry={@review.industry}
        />
        <.ledger
          id="analysis-income-categories"
          title={gettext("Income")}
          ledger={@income}
          revenue={nil}
          industry={@review.industry}
        />
      </div>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :ledger, :map, required: true

  attr :revenue, :any,
    required: true,
    doc: "year's income for cost shares of revenue; nil for income"

  attr :industry, :atom, required: true

  defp ledger(assigns) do
    ~H"""
    <section
      :if={@ledger.categories != []}
      id={@id}
      aria-labelledby={"#{@id}-title"}
      class="flex min-w-0 flex-col self-start rounded-md border border-grey-200 bg-white"
    >
      <header class="flex items-baseline justify-between gap-3 border-be border-grey-200 px-4 py-3">
        <h2 id={"#{@id}-title"} class="text-lg font-semibold text-grey-900">{@title}</h2>
        <span class="text-lg font-semibold text-grey-900 tabular-nums">{money(@ledger.total)}</span>
      </header>
      <div
        :for={category <- @ledger.categories}
        id={"#{@id}-#{category.key || "unassigned"}"}
        class="flex flex-col gap-2 border-be border-grey-200 py-3 last:border-be-0"
      >
        <div class="flex items-baseline justify-between gap-3 px-4">
          <h3 class="min-w-0 truncate text-sm font-semibold text-grey-900">
            {if category.key, do: category_label(category.key), else: gettext("Needs your choice")}
          </h3>
          <span class="shrink-0 text-sm font-semibold text-grey-900 tabular-nums">
            {money(category.amount)}
            <span class="ps-1 text-xs font-medium text-grey-600">
              {share_caption(category.amount, @ledger.total, @revenue)}
            </span>
          </span>
        </div>
        <div class="mx-4 h-1 rounded-full bg-grey-100" aria-hidden="true">
          <div
            class={bar_styles(@ledger.side)}
            style={"inline-size: #{share_percent(category.amount, @ledger.total)}%"}
          />
        </div>
        <ul class="flex flex-col px-2">
          <.counterparty
            :for={group <- category.groups}
            group={group}
            industry={@industry}
          />
        </ul>
        <div :if={category.key && category.to_confirm > 0} class="px-4">
          <FirmowidUI.Components.Button.button
            id={"analysis-confirm-group-#{@ledger.side}-#{category.key}"}
            type="button"
            variant="secondary"
            size="small"
            accent={accent(@ledger.side)}
            phx-click="confirm-group"
            phx-value-side={@ledger.side}
            phx-value-category={category.key}
          >
            {ngettext(
              "Confirm %{count} suggestion",
              "Confirm %{count} suggestions",
              category.to_confirm
            )}
          </FirmowidUI.Components.Button.button>
        </div>
      </div>
    </section>
    """
  end

  attr :group, :map, required: true
  attr :industry, :atom, required: true

  defp counterparty(assigns) do
    assigns =
      assign(
        assigns,
        :id,
        "analysis-counterparty-#{assigns.group.side}-#{:erlang.phash2(assigns.group.key)}"
      )

    ~H"""
    <li
      id={@id}
      class="flex items-center gap-2 rounded-md px-2 py-1 min-block-11 pointer-fine:hover:bg-grey-50"
    >
      <div class="flex min-w-0 flex-1 flex-col">
        <span class="truncate text-sm text-grey-900">{@group.name}</span>
        <span class="truncate text-xs text-grey-600">{reason(@group)}</span>
      </div>
      <span class="shrink-0 text-sm text-grey-700 tabular-nums">{whole_money(@group.amount)}</span>
      <span class="flex size-8 shrink-0 items-center justify-center">
        <Lucideicons.check
          :if={@group.status == :confirmed}
          class="size-4 text-moss-700"
          aria-label={gettext("Confirmed")}
        />
        <.icon_button
          :if={@group.status != :confirmed and @group.suggestion != nil}
          id={"#{@id}-confirm"}
          variant="outline"
          label={gettext("Confirm %{category}", category: category_label(@group.suggestion))}
          phx-click="confirm-category"
          phx-value-side={@group.side}
          phx-value-key={@group.key}
          phx-value-category={@group.suggestion}
        >
          <Lucideicons.check />
        </.icon_button>
      </span>
      <.menu id={"#{@id}-menu"} label={gettext("Move %{name} to another category", name: @group.name)}>
        <.menu_item
          :for={category <- category_options(@industry, @group)}
          phx-click="confirm-category"
          phx-value-side={@group.side}
          phx-value-key={@group.key}
          phx-value-category={category}
          aria-current={to_string(category == @group.category)}
        >
          <span class="flex-1">{category_label(category)}</span>
          <Lucideicons.check :if={category == @group.category} class="size-4" />
        </.menu_item>
      </.menu>
    </li>
    """
  end

  defp bar_styles(:expenses), do: "h-full rounded-full bg-rust-500"
  defp bar_styles(:income), do: "h-full rounded-full bg-teal-500"

  defp accent(:expenses), do: "rust"
  defp accent(:income), do: "teal"

  # Counterparties sit under their confirmed category, else under the suggestion.
  defp ledger(groups, side) do
    groups = Enum.filter(groups, &(&1.side == side))
    {placed, unplaced} = Enum.split_with(groups, &(&1.category || &1.suggestion))

    categories =
      placed
      |> Enum.group_by(&(&1.category || &1.suggestion))
      |> Enum.map(fn {key, groups} -> category(key, groups) end)
      |> Enum.sort_by(& &1.amount, {:desc, Decimal})

    %{
      side: side,
      total: sum(groups),
      categories: if(unplaced == [], do: categories, else: [category(nil, unplaced) | categories])
    }
  end

  defp category(key, groups) do
    %{
      key: key,
      groups: groups,
      amount: sum(groups),
      to_confirm: Enum.count(groups, &(&1.status != :confirmed))
    }
  end

  defp share_caption(amount, _total, revenue) when revenue != nil do
    if Decimal.positive?(revenue),
      do: gettext("%{share} of income", share: ratio(amount, revenue)),
      else: ""
  end

  defp share_caption(amount, total, nil), do: ratio(amount, total)

  defp reason(%{status: :confirmed}), do: gettext("Your choice")

  defp reason(%{status: :automatic}), do: gettext("Assigned automatically; suggestions like this are reliable")

  defp reason(%{source: :certain}), do: gettext("Salary or tax payment")

  defp reason(%{source: :invoice_lines, reason: [line | _]}), do: gettext("From the document: %{text}", text: line)

  defp reason(%{source: :name}), do: gettext("Known counterparty")
  defp reason(%{source: :learned}), do: gettext("Similar to your earlier choices")
  defp reason(%{source: :default}), do: gettext("Typical for your industry")
  defp reason(_group), do: gettext("No suggestion; choose a category")

  defp category_options(industry, group) do
    options = IndustryTemplate.categories(industry, group.side)
    selected = group.category || group.suggestion
    if selected == nil or selected in options, do: options, else: options ++ [selected]
  end

  defp sum(rows), do: Enum.reduce(rows, Decimal.new(0), &Decimal.add(&1.amount, &2))

  defp money(amount), do: Money.new(:PLN, Decimal.round(amount, 2))

  defp whole_money(amount), do: Number.to_string!(amount, currency: :PLN, fractional_digits: 0)

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

  defp industry_label(:services), do: gettext("Services (e.g. software house, agency)")
  defp industry_label(:gastronomy), do: gettext("Food service (e.g. café, restaurant)")
  defp industry_label(:retail), do: gettext("Retail (e.g. shop, florist)")

  defp category_label(:goods), do: gettext("Goods and supplies")
  defp category_label(:subcontractors), do: gettext("Subcontractors")
  defp category_label(:payroll), do: gettext("Salaries and social security")
  defp category_label(:premises), do: gettext("Premises and utilities")
  defp category_label(:software), do: gettext("Software and IT")
  defp category_label(:marketing), do: gettext("Marketing")
  defp category_label(:services), do: gettext("External services")
  defp category_label(:fees), do: gettext("Fees and commissions")
  defp category_label(:transport), do: gettext("Transport and fuel")
  defp category_label(:equipment), do: gettext("Equipment and office supplies")
  defp category_label(:taxes), do: gettext("Taxes")
  defp category_label(:other), do: gettext("Other costs")
  defp category_label(:sales), do: gettext("Sales")
  defp category_label(:on_site), do: gettext("On-site sales")
  defp category_label(:delivery), do: gettext("Delivery platforms")
  defp category_label(:catering), do: gettext("Catering and events")
  defp category_label(:store), do: gettext("In-store sales")
  defp category_label(:online), do: gettext("Online sales")
  defp category_label(:other_income), do: gettext("Other income")
end
