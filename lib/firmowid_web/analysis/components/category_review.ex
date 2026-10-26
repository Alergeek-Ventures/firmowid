defmodule FirmowidWeb.Analysis.Components.CategoryReview do
  @moduledoc """
  Owner session classifying a year's counterparties into industry template categories.

  Shows the industry, the cost and income structure, and every counterparty
  awaiting review with a pre-filled suggestion. Sends `set-industry`,
  `confirm-suggestions` and `confirm-category` (with `side`, `key` and `category`).
  """
  use FirmowidWeb, :html

  alias Firmowid.Ash.Analysis.IndustryTemplate

  attr :review, :map, required: true, doc: "`Firmowid.Ash.Analysis.get_category_review/3` result"
  attr :year, :integer, required: true

  @doc "Renders the industry choice, category structure and counterparty review."
  @spec review(map()) :: Phoenix.LiveView.Rendered.t()
  def review(assigns) do
    {confirmed, open} = Enum.split_with(assigns.review.groups, &(&1.status == :confirmed))

    assigns =
      assigns
      |> assign(:open, open)
      |> assign(:confirmed, confirmed)
      |> assign(:suggested, Enum.count(open, &(&1.status == :pending and &1.suggestion != nil)))

    ~H"""
    <div id="analysis-category-review" class="@container flex flex-col gap-6">
      <section class="flex flex-col gap-4 rounded-xl border border-grey-200 bg-white p-4 @3xl:p-6">
        <form id="analysis-industry" phx-change="set-industry" class="flex flex-col gap-1">
          <label for="analysis-industry-select" class="text-sm font-medium text-grey-900">
            {gettext("Industry")}
          </label>
          <select
            id="analysis-industry-select"
            name="industry"
            class="rounded-md border border-grey-400 bg-white px-3 text-sm max-inline-full min-block-11 focus-visible:outline-2 focus-visible:outline-teal-700 @lg:max-inline-sm"
          >
            <option
              :for={industry <- IndustryTemplate.industries()}
              value={industry}
              selected={industry == @review.industry}
            >
              {industry_label(industry)}
            </option>
          </select>
          <p :if={@review.inferred?} id="analysis-industry-inferred" class="text-sm text-grey-700">
            {gettext("Recognized from your counterparties. Change it if it does not fit.")}
          </p>
        </form>
        <div class="grid gap-6 @3xl:grid-cols-2">
          <.structure
            id="analysis-expense-structure"
            title={gettext("Costs in %{year}", year: @year)}
            totals={@review.expenses}
          />
          <.structure
            id="analysis-income-structure"
            title={gettext("Income in %{year}", year: @year)}
            totals={@review.income}
          />
        </div>
      </section>
      <section
        id="analysis-category-suggestions"
        aria-labelledby="analysis-category-suggestions-title"
        class="flex flex-col gap-4"
      >
        <div class="flex flex-wrap items-center justify-between gap-3">
          <div class="flex flex-col gap-1">
            <h2 id="analysis-category-suggestions-title" class="text-lg font-semibold text-grey-900">
              {gettext("To review")}
            </h2>
            <p class="text-sm text-grey-700">
              {gettext("You choose once per counterparty; its future entries follow your choice.")}
            </p>
            <p
              :if={@review.accuracy.total > 0}
              id="analysis-category-accuracy"
              class="text-sm text-grey-700"
            >
              {gettext("%{accepted} of %{total} suggestions accepted unchanged.",
                accepted: @review.accuracy.accepted,
                total: @review.accuracy.total
              )}
            </p>
          </div>
          <FirmowidUI.Components.Button.button
            :if={@suggested > 0}
            id="analysis-confirm-suggestions"
            type="button"
            phx-click="confirm-suggestions"
            phx-disable-with={gettext("Saving…")}
          >
            {gettext("Accept all suggestions (%{count})", count: @suggested)}
          </FirmowidUI.Components.Button.button>
        </div>
        <p :if={@open == []} id="analysis-category-suggestions-empty" class="text-sm text-grey-700">
          {gettext("Every counterparty has a category.")}
        </p>
        <ul
          :if={@open != []}
          class="flex flex-col divide-y divide-grey-200 rounded-xl border border-grey-200 bg-white"
        >
          <.group_row :for={group <- @open} group={group} industry={@review.industry} />
        </ul>
        <details
          :if={@confirmed != []}
          id="analysis-category-confirmed"
          phx-mounted={JS.ignore_attributes(["open"])}
        >
          <summary class="cursor-pointer content-center text-sm font-medium text-grey-900 min-block-11">
            {gettext("Confirmed (%{count})", count: length(@confirmed))}
          </summary>
          <ul class="flex flex-col divide-y divide-grey-200 rounded-xl border border-grey-200 bg-white">
            <.group_row :for={group <- @confirmed} group={group} industry={@review.industry} />
          </ul>
        </details>
      </section>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :totals, :map, required: true

  defp structure(assigns) do
    assigns =
      assign(
        assigns,
        :rows,
        assigns.totals.categories
        |> Enum.filter(&Decimal.positive?(&1.amount))
        |> Enum.sort_by(& &1.amount, {:desc, Decimal})
      )

    ~H"""
    <div id={@id} class="flex flex-col gap-3">
      <div class="flex items-baseline justify-between gap-3">
        <h2 class="text-h5 font-medium text-grey-900">{@title}</h2>
        <span class="text-sm font-semibold text-grey-900 tabular-nums">{money(@totals.total)}</span>
      </div>
      <p :if={@rows == [] and not Decimal.positive?(@totals.pending)} class="text-sm text-grey-700">
        {gettext("No entries")}
      </p>
      <ul class="flex flex-col gap-2">
        <li
          :for={row <- @rows}
          class="grid grid-cols-[minmax(0,1fr)_auto] items-center gap-x-3 gap-y-1 text-sm"
        >
          <span class="truncate text-grey-900">{category_label(row.key)}</span>
          <span class="text-grey-900 tabular-nums">
            {money(row.amount)}
            <span class="ps-1 text-xs text-grey-700">{share(row.amount, @totals.total)}</span>
          </span>
          <span class="col-span-2 h-1.5 rounded-full bg-grey-100" aria-hidden="true">
            <span
              class="block h-full rounded-full bg-teal-600"
              style={"inline-size: #{bar_percent(row.amount, @totals.total)}%"}
            />
          </span>
        </li>
        <li
          :if={Decimal.positive?(@totals.pending)}
          class="grid grid-cols-[minmax(0,1fr)_auto] items-center gap-x-3 gap-y-1 text-sm"
        >
          <span class="truncate text-grey-700">{gettext("To review")}</span>
          <span class="text-grey-700 tabular-nums">
            {money(@totals.pending)}
            <span class="ps-1 text-xs">{share(@totals.pending, @totals.total)}</span>
          </span>
          <span class="col-span-2 h-1.5 rounded-full bg-grey-100" aria-hidden="true">
            <span
              class="block h-full rounded-full border border-dashed border-grey-500"
              style={"inline-size: #{bar_percent(@totals.pending, @totals.total)}%"}
            />
          </span>
        </li>
      </ul>
    </div>
    """
  end

  attr :group, :map, required: true
  attr :industry, :atom, required: true

  defp group_row(assigns) do
    assigns =
      assign(
        assigns,
        :form_id,
        "analysis-category-#{assigns.group.side}-#{:erlang.phash2(assigns.group.key)}"
      )

    ~H"""
    <li class="flex flex-col gap-3 p-4 @2xl:flex-row @2xl:items-center @2xl:justify-between">
      <div class="flex min-w-0 flex-col gap-1">
        <div class="flex flex-wrap items-baseline gap-x-2">
          <span class="font-medium text-grey-900">{@group.name}</span>
          <span class="text-sm text-grey-900 tabular-nums">
            {if @group.side == :income, do: "+", else: "−"}{money(@group.amount)}
          </span>
          <span class="text-xs text-grey-700">
            {ngettext("%{count} entry", "%{count} entries", @group.count)}
          </span>
        </div>
        <p class="truncate text-xs text-grey-700">{reason(@group)}</p>
      </div>
      <form
        id={@form_id}
        phx-submit="confirm-category"
        phx-change={if @group.status == :confirmed, do: "confirm-category"}
        class="flex items-center gap-2 @2xl:shrink-0"
      >
        <input type="hidden" name="side" value={@group.side} />
        <input type="hidden" name="key" value={@group.key} />
        <label for={"#{@form_id}-select"} class="sr-only">
          {gettext("Category of %{name}", name: @group.name)}
        </label>
        <select
          id={"#{@form_id}-select"}
          name="category"
          required
          class="min-w-0 flex-1 rounded-md border border-grey-400 bg-white px-3 text-sm min-block-11 focus-visible:outline-2 focus-visible:outline-teal-700 @2xl:w-64 @2xl:flex-none"
        >
          <option :if={selected_category(@group) == nil} value="" selected>
            {gettext("Choose a category")}
          </option>
          <option
            :for={category <- category_options(@industry, @group)}
            value={category}
            selected={category == selected_category(@group)}
          >
            {category_label(category)}
          </option>
        </select>
        <FirmowidUI.Components.Button.button
          :if={@group.status != :confirmed}
          id={"#{@form_id}-confirm"}
          type="submit"
          variant="secondary"
        >
          {gettext("Confirm")}
        </FirmowidUI.Components.Button.button>
      </form>
    </li>
    """
  end

  defp selected_category(group), do: group.category || group.suggestion

  defp category_options(industry, group) do
    options = IndustryTemplate.categories(industry, group.side)
    selected = selected_category(group)
    if selected == nil or selected in options, do: options, else: options ++ [selected]
  end

  defp reason(%{status: :confirmed}), do: gettext("Your choice")

  defp reason(%{status: :automatic}), do: gettext("Assigned automatically; suggestions like this are reliable")

  defp reason(%{source: :certain}), do: gettext("Salary or tax payment")

  defp reason(%{source: :invoice_lines, reason: [line | _]}), do: gettext("From the document: %{text}", text: line)

  defp reason(%{source: :name}), do: gettext("Known counterparty")
  defp reason(%{source: :learned}), do: gettext("Similar to your earlier choices")
  defp reason(%{source: :default}), do: gettext("Typical for your industry")
  defp reason(_group), do: gettext("No suggestion; choose a category")

  defp money(amount), do: Money.new(:PLN, Decimal.round(amount, 2))

  defp share(amount, total) do
    if Decimal.positive?(total),
      do: amount |> Decimal.div(total) |> Firmowid.Cldr.Number.to_string!(format: :percent),
      else: ""
  end

  defp bar_percent(amount, total) do
    if Decimal.positive?(total),
      do:
        amount
        |> Decimal.div(total)
        |> Decimal.mult(100)
        |> Decimal.round(1)
        |> Decimal.to_string(:normal),
      else: "0"
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
