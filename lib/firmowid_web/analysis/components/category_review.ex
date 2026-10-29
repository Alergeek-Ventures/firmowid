defmodule FirmowidWeb.Analysis.Components.CategoryReview do
  @moduledoc """
  Owner session classifying a year's counterparties into industry template categories.

  Costs and income are two columns of categories, each listing its
  counterparties. A counterparty row opens the categories to confirm or move
  it to. The industry is inferred, never chosen here. Sends
  `confirm-category` (with the group's `side`, `key`, `suggestion` and `source`,
  and the chosen `category`).
  """
  use FirmowidWeb, :html

  alias Firmowid.Ash.Analysis.IndustryTemplate
  alias Firmowid.Cldr.Number

  attr :review, :map, required: true, doc: "`Firmowid.Ash.Analysis.get_category_review/3` result"
  attr :year, :integer, required: true

  @doc "Renders the cost and income columns."
  @spec review(map()) :: Phoenix.LiveView.Rendered.t()
  def review(assigns) do
    groups = assigns.review.groups

    assigns =
      assigns
      |> assign(:expenses, ledger(groups, :expenses))
      |> assign(:income, ledger(groups, :income))

    ~H"""
    <div id="analysis-category-review" class="@container flex flex-col gap-10">
      <div class="grid grid-cols-[minmax(0,1fr)] gap-x-16 gap-y-12 @5xl:grid-cols-2">
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
      class="flex min-w-0 flex-col gap-8"
    >
      <header class="flex items-baseline justify-between gap-3">
        <h2 id={"#{@id}-title"} class="text-2xl font-semibold text-grey-900">{@title}</h2>
        <span class="text-2xl font-semibold text-grey-900 tabular-nums">{whole_money(@ledger.total)}</span>
      </header>
      <div
        :for={category <- @ledger.categories}
        id={"#{@id}-#{category.key || "unassigned"}"}
        class="flex flex-col gap-1"
      >
        <div class="flex items-baseline justify-between gap-3">
          <h3 class="min-w-0 truncate text-sm font-semibold text-grey-900">
            {if category.key, do: category_label(category.key), else: gettext("Needs your choice")}
          </h3>
          <span class="shrink-0 text-sm text-grey-700 tabular-nums">
            {share_caption(category.amount, @ledger.total, @revenue)}
          </span>
        </div>
        <div class="mb-1 h-1 rounded-full bg-grey-200" aria-hidden="true">
          <div
            class={bar_styles(@ledger.side)}
            style={"inline-size: #{share_percent(category.amount, @ledger.total)}%"}
          />
        </div>
        <ul class="-mx-2 flex flex-col">
          <.counterparty :for={group <- category.groups} group={group} industry={@industry} />
        </ul>
      </div>
    </section>
    """
  end

  attr :group, :map, required: true
  attr :industry, :atom, required: true

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

  defp name_styles(:confirmed), do: "min-w-0 truncate text-grey-900"
  defp name_styles(_status), do: "min-w-0 truncate text-grey-700"

  defp bar_styles(:expenses), do: "h-full rounded-full bg-rust-500"
  defp bar_styles(:income), do: "h-full rounded-full bg-teal-500"

  # Counterparties sit under their confirmed category, else under the suggestion.
  defp ledger(groups, side) do
    groups = Enum.filter(groups, &(&1.side == side))
    {placed, unplaced} = Enum.split_with(groups, &(&1.category || &1.suggestion))

    categories =
      placed
      |> Enum.group_by(&(&1.category || &1.suggestion))
      |> Enum.map(fn {key, groups} -> %{key: key, groups: groups, amount: sum(groups)} end)
      |> Enum.sort_by(& &1.amount, {:desc, Decimal})

    unassigned =
      if unplaced == [], do: [], else: [%{key: nil, groups: unplaced, amount: sum(unplaced)}]

    %{side: side, total: sum(groups), categories: unassigned ++ categories}
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

  defp reason(%{source: :certain}), do: gettext("Salary or tax payment")

  defp reason(%{source: :jev, reason: [line | _]}), do: gettext("From the document: %{text}", text: line)

  defp reason(%{source: :jev}), do: gettext("Chosen from the counterparty's name")
  defp reason(_group), do: gettext("No suggestion yet; choose a category")

  defp category_options(industry, group) do
    options = IndustryTemplate.categories(industry, group.side)
    selected = group.category || group.suggestion
    if selected == nil or selected in options, do: options, else: options ++ [selected]
  end

  defp sum(rows), do: Enum.reduce(rows, Decimal.new(0), &Decimal.add(&1.amount, &2))

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
