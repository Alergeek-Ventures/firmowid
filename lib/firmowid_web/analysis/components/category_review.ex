defmodule FirmowidWeb.Analysis.Components.CategoryReview do
  @moduledoc """
  Owner session classifying a year's counterparties into industry template categories.

  A summary shows how much of the year's money is confirmed or suggested and
  accepts every suggestion at once. Below, costs and income are split into
  category cards whose counterparties are chips; a chip opens the categories
  to move it to. Sends `set-industry`, `confirm-suggestions`, `confirm-group`
  (with `side` and `category`) and `confirm-category` (with `side`, `key` and
  `category`).
  """
  use FirmowidWeb, :html

  alias Firmowid.Ash.Analysis.IndustryTemplate
  alias Firmowid.Cldr.Number

  # Okabe-Ito based palette, distinguishable with common color vision deficiencies.
  @palette ~w(#0072B2 #E69F00 #009E73 #CC79A7 #D55E00 #56B4E9 #6F4C9B #B6A800 #00A6A6 #845B32 #F285B5 #64748B)

  attr :review, :map, required: true, doc: "`Firmowid.Ash.Analysis.get_category_review/3` result"
  attr :year, :integer, required: true

  @doc "Renders the session summary and the cost and income category cards."
  @spec review(map()) :: Phoenix.LiveView.Rendered.t()
  def review(assigns) do
    %{review: review} = assigns
    groups = review.groups

    assigns =
      assigns
      |> assign(:progress, progress(groups))
      |> assign(
        :suggested,
        Enum.count(groups, &(&1.status != :confirmed and &1.suggestion != nil))
      )
      |> assign(:expenses, cards(groups, :expenses))
      |> assign(:income, cards(groups, :income))

    ~H"""
    <div id="analysis-category-review" class="@container flex flex-col gap-8">
      <section
        id="analysis-category-summary"
        aria-labelledby="analysis-category-summary-title"
        class="flex flex-col gap-5 rounded-2xl bg-teal-900 p-5 text-white @3xl:p-8"
      >
        <div class="flex flex-wrap items-start justify-between gap-4">
          <div class="flex max-w-2xl flex-col gap-2">
            <p class="text-sm font-medium text-teal-200">
              {gettext("Your %{year} in categories", year: @year)}
            </p>
            <h2 id="analysis-category-summary-title" class="text-xl font-semibold @3xl:text-2xl">
              {headline(@suggested, @progress)}
            </h2>
            <p class="text-teal-100">{subline(@suggested, @progress)}</p>
          </div>
          <form id="analysis-industry" phx-change="set-industry" class="flex flex-col gap-1">
            <label for="analysis-industry-select" class="text-xs font-medium text-teal-200">
              {gettext("Industry")}
            </label>
            <select
              id="analysis-industry-select"
              name="industry"
              class="rounded-lg border border-white/30 bg-white/10 px-3 text-sm text-white min-block-11 focus-visible:outline-2 focus-visible:outline-white"
            >
              <option
                :for={industry <- IndustryTemplate.industries()}
                value={industry}
                selected={industry == @review.industry}
                class="text-grey-900"
              >
                {industry_label(industry)}
              </option>
            </select>
            <p :if={@review.inferred?} id="analysis-industry-inferred" class="text-xs text-teal-200">
              {gettext("Recognized from your counterparties")}
            </p>
          </form>
        </div>
        <div class="flex flex-col gap-2">
          <div
            class="flex h-3 overflow-hidden rounded-full bg-white/10"
            role="img"
            aria-label={progress_label(@progress)}
          >
            <span class="bg-white" style={"inline-size: #{@progress.confirmed_percent}%"} />
            <span
              class="bg-[repeating-linear-gradient(135deg,rgb(255_255_255/0.55)_0_4px,rgb(255_255_255/0.25)_4px_8px)]"
              style={"inline-size: #{@progress.suggested_percent}%"}
            />
          </div>
          <ul class="flex flex-wrap gap-x-5 gap-y-1 text-xs text-teal-100">
            <li class="inline-flex items-center gap-1.5">
              <span aria-hidden="true" class="size-2.5 rounded-full bg-white" />
              {gettext("Confirmed %{share}", share: percent(@progress.confirmed_percent))}
            </li>
            <li class="inline-flex items-center gap-1.5">
              <span aria-hidden="true" class="size-2.5 rounded-full bg-white/40" />
              {gettext("Suggested %{share}", share: percent(@progress.suggested_percent))}
            </li>
            <li :if={@review.accuracy.total > 0} id="analysis-category-accuracy">
              {gettext("%{accepted} of %{total} suggestions accepted unchanged.",
                accepted: @review.accuracy.accepted,
                total: @review.accuracy.total
              )}
            </li>
          </ul>
        </div>
        <div :if={@suggested > 0}>
          <FirmowidUI.Components.Button.button
            id="analysis-confirm-suggestions"
            type="button"
            variant="unstyled"
            phx-click="confirm-suggestions"
            phx-disable-with={gettext("Saving…")}
            class="inline-flex cursor-pointer items-center rounded-lg bg-white px-5 text-sm font-semibold text-teal-900 min-block-11 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-white active:bg-teal-100"
          >
            {gettext("Accept all suggestions (%{count})", count: @suggested)}
          </FirmowidUI.Components.Button.button>
        </div>
      </section>
      <.side
        id="analysis-expense-categories"
        title={gettext("Where the money goes")}
        cards={@expenses}
        revenue={@review.income.total}
        industry={@review.industry}
      />
      <.side
        id="analysis-income-categories"
        title={gettext("Where the money comes from")}
        cards={@income}
        revenue={nil}
        industry={@review.industry}
      />
    </div>
    """
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :cards, :map, required: true

  attr :revenue, :any,
    required: true,
    doc: "year's income for cost shares of revenue; nil for income"

  attr :industry, :atom, required: true

  defp side(assigns) do
    ~H"""
    <section :if={@cards.total_groups > 0} id={@id} class="flex flex-col gap-4">
      <div class="flex flex-wrap items-baseline justify-between gap-2">
        <h2 class="text-xl font-semibold text-grey-900">{@title}</h2>
        <span class="text-lg font-semibold text-grey-900 tabular-nums">{money(@cards.total)}</span>
      </div>
      <div class="flex h-4 gap-0.5 overflow-hidden rounded-full" aria-hidden="true">
        <span
          :for={card <- @cards.categorized}
          class="first:rounded-s-full last:rounded-e-full"
          style={"inline-size: #{share_percent(card.amount, @cards.total)}%; background-color: #{card.color}"}
        />
        <span
          :if={@cards.unassigned}
          class="bg-grey-300 last:rounded-e-full"
          style={"inline-size: #{share_percent(@cards.unassigned.amount, @cards.total)}%"}
        />
      </div>
      <div class="grid grid-cols-[minmax(0,1fr)] gap-4 @3xl:grid-cols-2">
        <.category_card
          :if={@cards.unassigned}
          card={@cards.unassigned}
          total={@cards.total}
          revenue={@revenue}
          industry={@industry}
        />
        <.category_card
          :for={card <- @cards.categorized}
          card={card}
          total={@cards.total}
          revenue={@revenue}
          industry={@industry}
        />
      </div>
    </section>
    """
  end

  attr :card, :map, required: true
  attr :total, :any, required: true
  attr :revenue, :any, required: true
  attr :industry, :atom, required: true

  defp category_card(assigns) do
    assigns =
      assign(assigns, :to_confirm, Enum.count(assigns.card.groups, &(&1.status != :confirmed)))

    ~H"""
    <article
      id={"analysis-category-card-#{@card.side}-#{@card.key || "unassigned"}"}
      class={card_styles(@card.key)}
    >
      <header class="flex items-start justify-between gap-3">
        <div class="flex min-w-0 items-center gap-2">
          <span
            aria-hidden="true"
            class="size-3 shrink-0 rounded-full"
            style={"background-color: #{@card.color}"}
          />
          <h3 class="truncate font-semibold text-grey-900">
            {if @card.key, do: category_label(@card.key), else: gettext("Needs your choice")}
          </h3>
        </div>
        <div class="flex shrink-0 flex-col items-end">
          <span class="font-semibold text-grey-900 tabular-nums">{money(@card.amount)}</span>
          <span class="text-xs text-grey-700">{share_caption(@card.amount, @total, @revenue)}</span>
        </div>
      </header>
      <ul class="flex flex-wrap gap-2">
        <li :for={group <- @card.groups}>
          <.chip group={group} industry={@industry} />
        </li>
      </ul>
      <div :if={@card.key && @to_confirm > 0} class="flex flex-wrap items-center gap-3">
        <FirmowidUI.Components.Button.button
          id={"analysis-confirm-group-#{@card.side}-#{@card.key}"}
          type="button"
          variant="unstyled"
          phx-click="confirm-group"
          phx-value-side={@card.side}
          phx-value-category={@card.key}
          class="inline-flex cursor-pointer items-center gap-1.5 rounded-full border border-teal-700 px-4 text-sm font-medium text-teal-800 min-block-11 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-teal-700 active:bg-teal-100 pointer-fine:hover:bg-teal-50"
        >
          <.icon name="hero-check-mini" class="size-4" />
          {gettext("Looks right")}
        </FirmowidUI.Components.Button.button>
        <span class="text-xs text-grey-700">
          {ngettext("%{count} suggestion to confirm", "%{count} suggestions to confirm", @to_confirm)}
        </span>
      </div>
    </article>
    """
  end

  attr :group, :map, required: true
  attr :industry, :atom, required: true

  # A chip is a disclosure listing the categories to move the counterparty to.
  defp chip(assigns) do
    assigns =
      assign(
        assigns,
        :id,
        "analysis-chip-#{assigns.group.side}-#{:erlang.phash2(assigns.group.key)}"
      )

    ~H"""
    <details id={@id} class="group/chip relative">
      <summary class={chip_styles(@group.status)} title={reason(@group)}>
        <.icon :if={@group.status == :confirmed} name="hero-check-mini" class="size-4 shrink-0" />
        <span class="max-w-48 truncate">{@group.name}</span>
        <span class="text-grey-700 tabular-nums">{whole_money(@group.amount)}</span>
      </summary>
      <div class="absolute inset-s-0 top-full z-20 mt-1 flex w-72 flex-col gap-2 rounded-lg border border-grey-200 bg-white p-3 shadow-lg">
        <p class="text-xs text-grey-700">
          {ngettext("%{count} entry", "%{count} entries", @group.count)} · {reason(@group)}
        </p>
        <ul class="flex flex-col">
          <li :for={category <- category_options(@industry, @group)}>
            <FirmowidUI.Components.Button.button
              type="button"
              variant="unstyled"
              phx-click="confirm-category"
              phx-value-side={@group.side}
              phx-value-key={@group.key}
              phx-value-category={category}
              class={option_styles(category == (@group.category || @group.suggestion))}
            >
              {category_label(category)}
            </FirmowidUI.Components.Button.button>
          </li>
        </ul>
      </div>
    </details>
    """
  end

  defp card_styles(nil),
    do: "flex min-w-0 flex-col gap-4 rounded-xl border-2 border-dashed border-brick-700/40 bg-white p-4 @3xl:p-5"

  defp card_styles(_key), do: "flex min-w-0 flex-col gap-4 rounded-xl border border-grey-200 bg-white p-4 @3xl:p-5"

  defp chip_styles(:confirmed),
    do:
      "flex min-block-11 cursor-pointer list-none items-center gap-1.5 rounded-full border border-teal-700 bg-teal-50 px-3 text-sm text-teal-900 focus-visible:outline-2 focus-visible:outline-teal-700 group-open/chip:bg-teal-100 [&::-webkit-details-marker]:hidden"

  defp chip_styles(_status),
    do:
      "flex min-block-11 cursor-pointer list-none items-center gap-1.5 rounded-full border border-dashed border-grey-500 bg-white px-3 text-sm text-grey-900 focus-visible:outline-2 focus-visible:outline-teal-700 group-open/chip:bg-grey-100 pointer-fine:hover:bg-grey-100 [&::-webkit-details-marker]:hidden"

  defp option_styles(true),
    do:
      "flex w-full cursor-pointer items-center rounded-md bg-teal-100 px-2 text-start text-sm font-medium text-teal-900 min-block-11"

  defp option_styles(false),
    do:
      "flex w-full cursor-pointer items-center rounded-md px-2 text-start text-sm text-grey-900 min-block-11 active:bg-grey-200 pointer-fine:hover:bg-grey-100"

  # Cards show where each counterparty stands now: its confirmed category, else the suggestion.
  defp cards(groups, side) do
    groups = Enum.filter(groups, &(&1.side == side))
    {placed, unplaced} = Enum.split_with(groups, &(&1.category || &1.suggestion))
    colors = colors(side)

    categorized =
      placed
      |> Enum.group_by(&(&1.category || &1.suggestion))
      |> Enum.map(fn {key, groups} ->
        %{
          side: side,
          key: key,
          color: Map.get(colors, key, "#64748B"),
          groups: groups,
          amount: sum(groups)
        }
      end)
      |> Enum.sort_by(& &1.amount, {:desc, Decimal})

    %{
      total: sum(groups),
      total_groups: length(groups),
      categorized: categorized,
      unassigned:
        if(unplaced != [],
          do: %{side: side, key: nil, color: "#94A3B8", groups: unplaced, amount: sum(unplaced)}
        )
    }
  end

  defp colors(side) do
    side |> IndustryTemplate.all_categories() |> Enum.zip(Stream.cycle(@palette)) |> Map.new()
  end

  defp progress(groups) do
    total = sum(groups)
    confirmed = groups |> Enum.filter(&(&1.status == :confirmed)) |> sum()
    suggested = groups |> Enum.filter(&(&1.status != :confirmed and &1.suggestion)) |> sum()

    %{
      confirmed_percent: share_percent(confirmed, total),
      suggested_percent: share_percent(suggested, total),
      empty?: groups == []
    }
  end

  defp headline(_suggested, %{empty?: true}), do: gettext("No entries")

  defp headline(0, _progress), do: gettext("Everything is in its place")

  defp headline(suggested, _progress),
    do:
      ngettext(
        "We have a suggestion for %{count} counterparty",
        "We have suggestions for %{count} counterparties",
        suggested
      )

  defp subline(_suggested, %{empty?: true}), do: gettext("Categories appear once the year has income or expenses.")

  defp subline(0, _progress), do: gettext("New counterparties will show up here with a suggestion.")

  defp subline(_suggested, progress) do
    gettext(
      "They cover %{share} of your money this year. Check them below or accept all at once.",
      share: percent(progress.suggested_percent)
    )
  end

  defp progress_label(progress) do
    gettext("Confirmed %{confirmed}, suggested %{suggested}",
      confirmed: percent(progress.confirmed_percent),
      suggested: percent(progress.suggested_percent)
    )
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

  defp percent(value), do: Number.to_string!(value / 100, format: :percent)

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
