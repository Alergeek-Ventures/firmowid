defmodule FirmowidWeb.Analysis.Components.SegmentRanking do
  @moduledoc """
  The year's result as one list of what earns and what costs: projects first,
  then shared costs (projects counted as shared costs and everything without a
  project), down to the company result. Bars share one scale, red for what
  lowers the result. A switch splits shared costs across projects by tracked
  hours. A row's menu moves a project between projects and shared costs. A
  project opens the dashboard filtered to it. Without projects, the industry
  template's income channels are ranked instead. Sends `show-overhead` and
  `toggle-function`.
  """
  use FirmowidWeb, :html

  alias Firmowid.Cldr.Number
  alias FirmowidWeb.Analysis.Components.CategoryReview
  alias FirmowidWeb.Analysis.Utilities.Navigation

  attr :profitability, :map,
    required: true,
    doc: "`ProjectProfitability.from_year_summary/2` result"

  attr :review, :map, required: true, doc: "`Firmowid.Ash.Analysis.get_category_review/2` result"
  attr :year, :integer, required: true

  attr :with_overhead, :boolean,
    required: true,
    doc: "whether shared costs are split across projects"

  attr :functions, :list, required: true, doc: "tag definitions counted as shared costs"

  attr :can_edit, :boolean,
    required: true,
    doc: "whether the member may move projects to shared costs"

  @doc "Renders projects and shared costs down to the company result."
  @spec ranking(map()) :: Phoenix.LiveView.Rendered.t()
  def ranking(assigns) do
    %{profitability: %{annual: annual}, review: review, with_overhead: with_overhead} = assigns
    projects = project_rows(annual.projects, with_overhead, assigns.year)
    # Split shared costs leave the residual; what stays there was not split.
    shared =
      shared_rows(if(with_overhead, do: annual.residual, else: annual.totals), assigns.functions)

    company = annual.totals.net_profit
    rest = Enum.reduce(projects ++ shared, company, &Decimal.sub(&2, &1.amount))
    {projects, shared, rest} = whole_rows(projects, shared, rest, Decimal.round(company, 0))
    company = Decimal.round(company, 0)
    rows = projects ++ shared

    assigns =
      assign(assigns,
        projects: projects,
        shared: shared,
        # Costs without a project alone need no breakdown: they are the shared costs.
        only_without_project: match?([%{kind: :without_project}], shared),
        # Summary amounts line up with shared cost rows, which have menus only for projects.
        shared_menus: assigns.can_edit and Enum.any?(shared, & &1.definition_id),
        shared_all: annual.totals |> shared_rows(assigns.functions) |> sum() |> Decimal.negate(),
        income: annual.totals.total_income,
        split: if(with_overhead, do: split_total(annual.projects), else: Decimal.new(0)),
        rest: rest,
        company: company,
        widest: rows |> Enum.map(&Decimal.abs(&1.amount)) |> Enum.max(Decimal, fn -> Decimal.new(0) end),
        channels: review.groups |> Enum.filter(&(&1.side == :income)) |> channels(),
        income_total: review.income.total
      )

    ~H"""
    <div id="analysis-segments" class="@container">
      <section
        :if={@projects == [] and @shared == [] and length(@channels) > 1}
        id="analysis-channel-ranking"
        aria-labelledby="analysis-channel-ranking-title"
        class="flex max-w-3xl flex-col gap-6"
      >
        <h2 id="analysis-channel-ranking-title" class="text-2xl font-semibold text-grey-900">
          {gettext("Income channels")}
        </h2>
        <.shares id="analysis-channels" rows={@channels} total={@income_total} />
      </section>
      <div
        :if={@projects != [] or @shared != [] or length(@channels) <= 1}
        class="grid grid-cols-[minmax(0,1fr)] gap-x-16 gap-y-12 @5xl:grid-cols-2"
      >
        <section
          id="analysis-project-ranking"
          aria-labelledby="analysis-project-ranking-title"
          class="flex min-w-0 flex-col gap-4"
        >
          <header class="flex flex-wrap items-center justify-between gap-x-6 gap-y-2">
            <h2 id="analysis-project-ranking-title" class="text-2xl font-semibold text-grey-900">
              {gettext("Projects")}
            </h2>
            <form :if={@projects != []} id="analysis-overhead-switch" phx-change="show-overhead">
              <.switch
                field={to_form(%{"with" => @with_overhead}, as: :overhead)[:with]}
                label={gettext("Split shared costs across projects")}
                class="text-sm"
              />
            </form>
          </header>
          <p :if={@projects == []} class="text-sm text-grey-700">
            {gettext("Tag entries with projects to compare their results.")}
          </p>
          <ol :if={@projects != []} id="analysis-projects" class="-mx-2 flex flex-col">
            <.row :for={row <- @projects} row={row} widest={@widest} can_edit={@can_edit} />
          </ol>
        </section>
        <section
          id="analysis-shared-costs"
          aria-labelledby="analysis-shared-costs-title"
          class="flex min-w-0 flex-col gap-4"
        >
          <header class="flex items-center min-block-8">
            <h2 id="analysis-shared-costs-title" class="text-2xl font-semibold text-grey-900">
              {gettext("Shared costs")}
            </h2>
          </header>
          <ol class="-mx-2 flex flex-col">
            <.row
              row={
                %{
                  id: "analysis-shared-total",
                  definition_id: nil,
                  name: gettext("Total"),
                  amount: Decimal.negate(@shared_all),
                  caption: gettext("%{share} of income", share: ratio(@shared_all, @income)),
                  patch: nil,
                  bar: min(percent_width(@shared_all, @income), 100.0),
                  neutral: true
                }
              }
              widest={@widest}
              can_edit={@shared_menus}
            />
            <%= if not @only_without_project do %>
              <.row :for={row <- @shared} row={row} widest={@widest} can_edit={@can_edit} />
            <% end %>
          </ol>
          <p :if={@only_without_project and Decimal.eq?(@split, 0)} class="text-sm text-grey-700">
            {gettext("Tools, office, accounting and other costs of running the company.")}
          </p>
          <p :if={not Decimal.eq?(@split, 0)} class="text-sm text-grey-700">
            {gettext("%{amount} without a project split across projects by tracked hours.",
              amount: whole_money(@split)
            )}
          </p>
          <dl id="analysis-company-bridge" class="flex flex-col gap-2 border-t border-grey-200 pt-4">
            <.line :if={@projects != []} can_edit={@shared_menus}>
              <dt class="text-grey-700">{gettext("Projects together")}</dt>
              <dd class="text-grey-900 tabular-nums">{whole_money(sum(@projects))}</dd>
            </.line>
            <.line :if={@shared != []} can_edit={@shared_menus}>
              <dt class="text-grey-700">
                {if Decimal.eq?(@split, 0),
                  do: gettext("Shared costs"),
                  else: gettext("Shared costs not split")}
              </dt>
              <dd class="text-grey-900 tabular-nums">{whole_money(sum(@shared))}</dd>
            </.line>
            <.line :if={not Decimal.eq?(@rest, 0)} can_edit={@shared_menus}>
              <dt class="text-grey-700">{gettext("Income outside projects")}</dt>
              <dd class="text-grey-900 tabular-nums">{whole_money(@rest)}</dd>
            </.line>
            <.line can_edit={@shared_menus} class="font-semibold text-grey-900">
              <dt>{gettext("Company result")}</dt>
              <dd class="tabular-nums">{whole_money(@company)}</dd>
            </.line>
          </dl>
        </section>
      </div>
    </div>
    """
  end

  attr :row, :map, required: true
  attr :widest, :any, required: true
  attr :can_edit, :boolean, required: true

  defp row(assigns) do
    ~H"""
    <li id={@row.id} class="flex items-start gap-1">
      <FirmowidUI.Components.Link.link
        :if={@row.patch}
        kind="unstyled"
        patch={@row.patch}
        class="flex min-w-0 flex-1 flex-col gap-1 rounded-md p-2 active:bg-grey-200 pointer-fine:hover:bg-white"
      >
        <.row_body row={@row} widest={@widest} />
      </FirmowidUI.Components.Link.link>
      <div :if={!@row.patch} class="flex min-w-0 flex-1 flex-col gap-1 p-2">
        <.row_body row={@row} widest={@widest} />
      </div>
      <%= if @can_edit do %>
        <.menu
          :if={@row.definition_id}
          id={"#{@row.id}-actions"}
          label={gettext("Actions for %{name}", name: @row.name)}
          class="pt-1"
        >
          <.menu_item phx-click="toggle-function" phx-value-id={@row.definition_id}>
            {if @row.kind == :project,
              do: gettext("Count as a shared cost"),
              else: gettext("Count as a project")}
          </.menu_item>
        </.menu>
        <span :if={!@row.definition_id} class="size-8 shrink-0" aria-hidden="true"></span>
      <% end %>
    </li>
    """
  end

  attr :can_edit, :boolean, required: true
  attr :class, :any, default: nil
  slot :inner_block, required: true

  # A text line whose amount lines up with the row amounts, left of their menus.
  defp line(assigns) do
    ~H"""
    <div class="-mx-2 flex gap-1">
      <div class={["flex min-w-0 flex-1 items-baseline justify-between gap-3 px-2 text-sm", @class]}>
        {render_slot(@inner_block)}
      </div>
      <span :if={@can_edit} class="w-8 shrink-0" aria-hidden="true"></span>
    </div>
    """
  end

  attr :row, :map, required: true
  attr :widest, :any, required: true

  defp row_body(assigns) do
    ~H"""
    <span class="flex items-baseline justify-between gap-3">
      <span class="min-w-0 truncate text-sm font-semibold text-grey-900">{@row.name}</span>
      <span class={amount_styles(@row)}>{whole_money(@row.amount)}</span>
    </span>
    <span :if={@row.caption} class="text-sm text-grey-700 tabular-nums">{@row.caption}</span>
    <span class="h-1 rounded-full bg-grey-200" aria-hidden="true">
      <span
        class={bar_styles(@row.amount)}
        style={"inline-size: #{@row[:bar] || percent_width(Decimal.abs(@row.amount), @widest)}%"}
      />
    </span>
    """
  end

  attr :id, :string, required: true
  attr :rows, :list, required: true, doc: "rows with `name`, `amount` and `rest?`"
  attr :total, :any, required: true

  defp shares(assigns) do
    ~H"""
    <ol id={@id} class="flex flex-col gap-3">
      <li :for={row <- @rows} class="flex flex-col gap-1">
        <span class="flex items-baseline justify-between gap-3">
          <span class={name_styles(row)}>{row.name}</span>
          <span class="shrink-0 text-sm text-grey-900 tabular-nums">{whole_money(row.amount)}</span>
        </span>
        <span class="text-sm text-grey-700 tabular-nums">
          {gettext("%{share} of income", share: ratio(row.amount, @total))}
        </span>
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

  defp project_rows(projects, with_overhead, year) do
    result = if with_overhead, do: :net_profit, else: :direct_profit

    projects
    |> Enum.map(fn project ->
      {:project, id} = project.key

      %{
        id: "analysis-project-#{id}",
        kind: :project,
        definition_id: id,
        name: project.name,
        amount: Map.fetch!(project, result),
        caption: project_caption(project, with_overhead),
        patch: Navigation.view_path(%{view: :dashboard, year: year, month: nil}, [project.key])
      }
    end)
    |> Enum.sort_by(& &1.amount, {:desc, Decimal})
  end

  # Projects counted as shared costs keep their own row, even without costs, so they can be
  # moved back; the rest has no project.
  defp shared_rows(totals, definitions) do
    {functions, others} =
      totals.expense_categories
      |> Enum.filter(&(match?({:function, _id}, &1.key) or &1.key in [:company, :taxes, :unassigned]))
      |> Enum.split_with(&match?({:function, _id}, &1.key))

    costs = Map.new(functions, fn %{key: {:function, id}} = category -> {id, category.amount} end)

    functions =
      Enum.map(definitions, fn %{id: id} = definition ->
        %{
          id: "analysis-function-#{id}",
          kind: :function,
          definition_id: id,
          name: definition.name,
          amount: costs |> Map.get(id, Decimal.new(0)) |> Decimal.negate(),
          caption: nil,
          patch: nil
        }
      end)

    without_project = Enum.reduce(others, Decimal.new(0), &Decimal.add(&1.amount, &2))

    without_project =
      if Decimal.positive?(without_project),
        do: [
          %{
            id: "analysis-without-project",
            kind: :without_project,
            definition_id: nil,
            name: gettext("Without a project"),
            amount: Decimal.negate(without_project),
            caption: gettext("Tools, office, accounting and other costs of running the company."),
            patch: nil
          }
        ],
        else: []

    Enum.sort_by(functions ++ without_project, & &1.amount, Decimal)
  end

  # Rows are shown in whole złoty; the largest one takes the rounding, so the visible rows add up.
  defp whole_rows(projects, shared, rest, company) do
    rows =
      Enum.map(
        projects ++ shared ++ [%{id: :rest, amount: rest}],
        &%{&1 | amount: Decimal.round(&1.amount, 0)}
      )

    difference = Enum.reduce(rows, company, &Decimal.sub(&2, &1.amount))
    largest = rows |> Enum.max_by(&Decimal.abs(&1.amount), Decimal) |> Map.fetch!(:id)

    rows =
      Enum.map(
        rows,
        &if(&1.id == largest, do: %{&1 | amount: Decimal.add(&1.amount, difference)}, else: &1)
      )

    {projects, rows} = Enum.split(rows, length(projects))
    {shared, [%{amount: rest}]} = Enum.split(rows, length(shared))
    {projects, shared, rest}
  end

  defp sum(rows), do: Enum.reduce(rows, Decimal.new(0), &Decimal.add(&1.amount, &2))

  defp split_total(projects) do
    Enum.reduce(
      projects,
      Decimal.new(0),
      &(&1.company_share |> Decimal.add(&1.taxes_share) |> Decimal.add(&2))
    )
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
        rest?: category == nil
      }
    end)
    |> Enum.sort_by(& &1.amount, {:desc, Decimal})
  end

  defp project_caption(project, with_overhead) do
    cond do
      not Decimal.positive?(project.income) ->
        gettext("No income; costs %{costs}",
          costs:
            whole_money(
              if with_overhead,
                do: Decimal.abs(project.total_expenses),
                else: project.direct_expenses
            )
        )

      with_overhead ->
        gettext("Income %{income} · shared costs %{overhead} · margin %{margin}",
          income: whole_money(project.income),
          overhead: whole_money(Decimal.add(project.company_share, project.taxes_share)),
          margin: ratio(project.net_profit, project.income)
        )

      true ->
        gettext("Income %{income} · margin %{margin}",
          income: whole_money(project.income),
          margin: ratio(project.direct_profit, project.income)
        )
    end
  end

  defp name_styles(%{rest?: true}), do: "min-w-0 truncate text-sm text-grey-700"
  defp name_styles(_row), do: "min-w-0 truncate text-sm font-semibold text-grey-900"

  defp amount_styles(row) do
    if Decimal.negative?(row.amount) and !row[:neutral],
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
