defmodule FirmowidWeb.Analysis.Components.SegmentRanking do
  @moduledoc """
  Ranks the year's segments: projects by their result after company overhead
  (allocated by project income), or without projects the income channels of
  the industry template, beside income sources by their share of income.
  A project opens the dashboard filtered to it.
  """
  use FirmowidWeb, :html

  alias Firmowid.Cldr.Number
  alias FirmowidWeb.Analysis.Components.CategoryReview
  alias FirmowidWeb.Analysis.Utilities.Navigation

  @sources 8

  attr :profitability, :map,
    required: true,
    doc: "`ProjectProfitability.from_year_summary/2` result"

  attr :review, :map, required: true, doc: "`Firmowid.Ash.Analysis.get_category_review/2` result"
  attr :year, :integer, required: true

  @doc "Renders the project ranking beside the income sources."
  @spec ranking(map()) :: Phoenix.LiveView.Rendered.t()
  def ranking(assigns) do
    %{profitability: profitability, review: review} = assigns
    projects = Enum.sort_by(profitability.annual.projects, & &1.net_profit, {:desc, Decimal})
    income = Enum.filter(review.groups, &(&1.side == :income))

    assigns =
      assign(assigns,
        projects: projects,
        residual: profitability.annual.residual,
        widest:
          projects
          |> Enum.map(&Decimal.abs(&1.net_profit))
          |> Enum.max(Decimal, fn -> Decimal.new(0) end),
        sources: sources(income),
        channels: channels(income),
        income_total: review.income.total
      )

    ~H"""
    <div id="analysis-segments" class="@container">
      <div class="grid grid-cols-[minmax(0,1fr)] gap-x-16 gap-y-12 @5xl:grid-cols-2">
        <section
          :if={@projects == [] and length(@channels) > 1}
          id="analysis-channel-ranking"
          aria-labelledby="analysis-channel-ranking-title"
          class="flex min-w-0 flex-col gap-6"
        >
          <h2 id="analysis-channel-ranking-title" class="text-2xl font-semibold text-grey-900">
            {gettext("Income channels")}
          </h2>
          <.shares id="analysis-channels" rows={@channels} total={@income_total} />
        </section>
        <section
          :if={@projects != [] or length(@channels) <= 1}
          id="analysis-project-ranking"
          aria-labelledby="analysis-project-ranking-title"
          class="flex min-w-0 flex-col gap-6"
        >
          <header class="flex flex-col gap-1">
            <h2 id="analysis-project-ranking-title" class="text-2xl font-semibold text-grey-900">
              {gettext("Projects")}
            </h2>
            <p class="text-sm text-grey-700">
              {if @projects == [],
                do: gettext("Tag entries with projects to compare their results."),
                else: gettext("Result after company costs, shared by project income.")}
            </p>
          </header>
          <ol :if={@projects != []} class="-mx-2 flex flex-col">
            <li :for={project <- @projects}>
              <FirmowidUI.Components.Link.link
                id={"analysis-project-#{elem(project.key, 1)}"}
                kind="unstyled"
                patch={
                  Navigation.view_path(%{view: :dashboard, year: @year, month: nil}, [project.key])
                }
                class="flex flex-col gap-1 rounded-md p-2 active:bg-grey-200 pointer-fine:hover:bg-white"
              >
                <span class="flex items-baseline justify-between gap-3">
                  <span class="min-w-0 truncate text-sm font-semibold text-grey-900">
                    {project.name}
                  </span>
                  <span class={amount_styles(project.net_profit)}>{whole_money(project.net_profit)}</span>
                </span>
                <span class="text-sm text-grey-700 tabular-nums">
                  {project_caption(project)}
                </span>
                <span class="h-1 rounded-full bg-grey-200" aria-hidden="true">
                  <span
                    class={bar_styles(project.net_profit)}
                    style={"inline-size: #{percent_width(Decimal.abs(project.net_profit), @widest)}%"}
                  />
                </span>
              </FirmowidUI.Components.Link.link>
            </li>
            <li
              :if={not Decimal.eq?(@residual.net_profit, 0)}
              id="analysis-project-residual"
              class="flex items-baseline justify-between gap-3 p-2 text-sm text-grey-700"
            >
              <span>{gettext("Outside projects")}</span>
              <span class="tabular-nums">{whole_money(@residual.net_profit)}</span>
            </li>
          </ol>
        </section>
        <section
          :if={@sources != []}
          id="analysis-income-sources"
          aria-labelledby="analysis-income-sources-title"
          class="flex min-w-0 flex-col gap-6"
        >
          <header class="flex items-baseline justify-between gap-3">
            <h2 id="analysis-income-sources-title" class="text-2xl font-semibold text-grey-900">
              {gettext("Income sources")}
            </h2>
            <span class="text-2xl font-semibold text-grey-900 tabular-nums">{whole_money(
              @income_total
            )}</span>
          </header>
          <.shares id="analysis-sources" rows={@sources} total={@income_total} />
        </section>
      </div>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :rows, :list, required: true, doc: "rows with `name`, `amount`, `caption` and `rest?`"
  attr :total, :any, required: true

  defp shares(assigns) do
    ~H"""
    <ol id={@id} class="flex flex-col gap-3">
      <li :for={row <- @rows} class="flex flex-col gap-1">
        <span class="flex items-baseline justify-between gap-3">
          <span class={name_styles(row)}>{row.name}</span>
          <span class="shrink-0 text-sm text-grey-900 tabular-nums">{whole_money(row.amount)}</span>
        </span>
        <span class="text-sm text-grey-700 tabular-nums">{share_caption(row, @total)}</span>
        <span class="h-1 rounded-full bg-grey-200" aria-hidden="true">
          <span
            class="block h-full rounded-full bg-teal-500"
            style={"inline-size: #{percent_width(row.amount, @total)}%"}
          />
        </span>
      </li>
    </ol>
    """
  end

  # Income by the confirmed or suggested template category.
  defp channels(income) do
    income
    |> Enum.group_by(&(&1.category || &1.suggestion))
    |> Enum.map(fn {category, groups} ->
      %{
        name:
          if(category,
            do: CategoryReview.category_label(category),
            else: gettext("Uncategorized")
          ),
        amount: Enum.reduce(groups, Decimal.new(0), &Decimal.add(&1.amount, &2)),
        category: nil,
        rest?: category == nil
      }
    end)
    |> Enum.sort_by(& &1.amount, {:desc, Decimal})
  end

  # The largest counterparties, then the rest together.
  defp sources(income) do
    {top, rest} = Enum.split(income, @sources)

    rest =
      if rest == [],
        do: [],
        else: [
          %{
            name: gettext("Others (%{count})", count: length(rest)),
            amount: Enum.reduce(rest, Decimal.new(0), &Decimal.add(&1.amount, &2)),
            category: nil,
            rest?: true
          }
        ]

    Enum.map(
      top,
      &%{name: &1.name, amount: &1.amount, category: &1.category || &1.suggestion, rest?: false}
    ) ++
      rest
  end

  defp project_caption(project) do
    if Decimal.positive?(project.income),
      do:
        gettext("Income %{income} · margin %{margin}",
          income: whole_money(project.income),
          margin: ratio(project.net_profit, project.income)
        ),
      else:
        gettext("No income; costs %{costs}",
          costs: whole_money(Decimal.abs(project.total_expenses))
        )
  end

  defp share_caption(row, total) do
    share = ratio(row.amount, total)

    case row.category do
      nil ->
        gettext("%{share} of income", share: share)

      category ->
        gettext("%{share} · %{category}",
          share: share,
          category: CategoryReview.category_label(category)
        )
    end
  end

  defp name_styles(%{rest?: true}), do: "min-w-0 truncate text-sm text-grey-700"
  defp name_styles(_row), do: "min-w-0 truncate text-sm font-semibold text-grey-900"

  defp amount_styles(amount) do
    if Decimal.negative?(amount),
      do: "shrink-0 text-sm font-semibold text-brick-700 tabular-nums",
      else: "shrink-0 text-sm font-semibold text-grey-900 tabular-nums"
  end

  defp bar_styles(amount) do
    if Decimal.negative?(amount),
      do: "block h-full rounded-full bg-brick-700",
      else: "block h-full rounded-full bg-teal-500"
  end

  defp percent_width(amount, total) do
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

  defp whole_money(amount), do: Number.to_string!(amount, currency: :PLN, fractional_digits: 0)
end
