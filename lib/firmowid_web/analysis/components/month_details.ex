defmodule FirmowidWeb.Analysis.Components.MonthDetails do
  @moduledoc """
  One month of the analysis: its result, then costs and income by template
  category with their counterparties. Each category is compared with its usual
  monthly amount, so an unusual month explains itself. Unpaid invoices are
  mentioned beside the totals they are missing from.
  """
  use FirmowidWeb, :html

  alias Firmowid.Cldr.Number
  alias FirmowidWeb.Analysis.Components.CategoryReview

  @notable_change Decimal.new("0.1")
  @material_share Decimal.new("0.02")

  attr :month, :map, required: true, doc: "month of the `YearSummary.get/3` result"

  attr :groups, :list,
    required: true,
    doc: "`CategoryReview.month/3` groups, or nil when tag filters leave categories out"

  attr :entries_path, :string,
    default: nil,
    doc: "the month's entry list in invoicing, where entries are assigned to projects"

  @doc "Renders the month's result and its costs and income by category."
  @spec details(map()) :: Phoenix.LiveView.Rendered.t()
  def details(assigns) do
    %{month: month, groups: groups} = assigns
    unpaid = month.unpaid || %{income: Decimal.new(0), expenses: Decimal.new(0)}

    assigns =
      assign(assigns,
        title: month.month |> Firmowid.Cldr.Date.to_string!(format: "LLLL y") |> String.capitalize(),
        result: month.totals.net_profit,
        expenses: column(groups, :expenses, Decimal.abs(month.totals.total_expenses), unpaid.expenses),
        income: column(groups, :income, month.totals.total_income, unpaid.income)
      )

    ~H"""
    <section
      id="analysis-month"
      aria-labelledby="analysis-month-title"
      class="@container flex flex-col gap-10"
    >
      <header class="flex flex-wrap items-baseline justify-between gap-x-6 gap-y-2">
        <h2 id="analysis-month-title" class="text-2xl font-semibold text-grey-900">{@title}</h2>
        <div class="flex flex-wrap items-baseline gap-x-6 gap-y-2">
          <p id="analysis-month-result" class={result_styles(@result)}>
            {gettext("Result %{amount}", amount: whole_money(@result))}
          </p>
          <FirmowidUI.Components.Link.link
            :if={@entries_path}
            id="analysis-month-entries"
            kind="unstyled"
            navigate={@entries_path}
            class="text-sm text-grey-700 underline underline-offset-4 active:text-grey-900"
          >
            {gettext("Month's entries")}
          </FirmowidUI.Components.Link.link>
        </div>
      </header>
      <div class="grid grid-cols-[minmax(0,1fr)] gap-x-16 gap-y-12 @5xl:grid-cols-2">
        <.column id="analysis-month-expenses" title={gettext("Costs")} column={@expenses} />
        <.column id="analysis-month-income" title={gettext("Income")} column={@income} />
      </div>
    </section>
    """
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :column, :map, required: true

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
      <div
        :for={category <- @column.categories}
        id={"#{@id}-#{category.key || "unassigned"}"}
        class="flex flex-col gap-1"
      >
        <div class="flex items-baseline justify-between gap-3">
          <h4 class="min-w-0 truncate text-sm font-semibold text-grey-900">
            {if category.key,
              do: CategoryReview.category_label(category.key),
              else: gettext("Uncategorized")}
          </h4>
          <span class="shrink-0 text-sm text-grey-900 tabular-nums">{whole_money(category.amount)}</span>
        </div>
        <p :if={category.average} class="text-sm text-grey-700 tabular-nums">
          {usual_caption(category.amount, category.average, @column.total)}
        </p>
        <ul class="flex flex-col pt-1">
          <li
            :for={group <- category.groups}
            class="flex items-baseline gap-2 py-1 text-sm text-grey-700"
          >
            <span class="min-w-0 truncate">{group.name}</span>
            <span class="ms-auto shrink-0 tabular-nums">{whole_money(group.amount)}</span>
          </li>
        </ul>
      </div>
    </section>
    """
  end

  # Categories follow the confirmed category, else the suggestion, largest first.
  defp column(nil, _side, total, unpaid), do: %{total: total, unpaid: unpaid, categories: []}

  defp column(groups, side, total, unpaid) do
    categories =
      groups
      |> Enum.filter(&(&1.side == side))
      |> Enum.group_by(&(&1.category || &1.suggestion))
      |> Enum.map(fn {key, groups} ->
        %{
          key: key,
          amount: sum(groups, :amount),
          average: if(hd(groups).average, do: sum(groups, :average)),
          groups:
            groups
            |> Enum.filter(&Decimal.positive?(&1.amount))
            |> Enum.sort_by(& &1.amount, {:desc, Decimal})
        }
      end)
      |> Enum.filter(&Decimal.positive?(&1.amount))
      |> Enum.sort_by(& &1.amount, {:desc, Decimal})

    %{total: total, unpaid: unpaid, categories: categories}
  end

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

  defp result_styles(amount) do
    if Decimal.negative?(amount),
      do: "text-2xl font-semibold text-brick-700 tabular-nums",
      else: "text-2xl font-semibold text-grey-900 tabular-nums"
  end

  defp sum(groups, field), do: Enum.reduce(groups, Decimal.new(0), &Decimal.add(Map.fetch!(&1, field), &2))

  defp whole_money(amount), do: Number.to_string!(amount, currency: :PLN, fractional_digits: 0)
end
