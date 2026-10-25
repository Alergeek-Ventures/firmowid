defmodule FirmowidWeb.Analysis.Components.ProjectMatrix do
  @moduledoc """
  Project-by-month results of a `Firmowid.Ash.Analysis.ProjectProfitability`
  scenario, with the breakdown of the selected cell beside the matrix.

  Rows are projects, then the residual outside projects and the whole company;
  columns are months and the year. Narrow containers render the same cells
  transposed, with the annual summary first and months as rows reached by scrolling
  down; their IDs end in `-transposed`. Cells are buttons sending `select-cell` with
  `month` (ISO date or `rok`) and `project` (tag definition ID, `firma` or
  `poza_projektami`). Amounts come from the scenario unchanged; shading is only a
  float projection of the project cells' Decimal results.
  """
  use FirmowidWeb, :html

  import FirmowidUI.Components.Link
  import Phoenix.Component, except: [link: 1]

  alias FirmowidWeb.Analysis.Utilities.Navigation

  @shades %{
    loss: ~w(bg-brick-100 bg-brick-200 bg-brick-300 bg-brick-400),
    profit: ~w(bg-teal-100 bg-teal-200 bg-teal-300 bg-teal-400)
  }

  attr :profitability, :map,
    required: true,
    doc: "`ProjectProfitability.from_year_summary/2` result for the unfiltered year summary"

  attr :params, :map,
    required: true,
    doc: """
    `year`, `allocation` (`:income` or `:direct_expenses`), `metric` (`:net` or `:direct`),
    selected `month` (`Date` or `nil` for the year) and `project` (`nil`, `:company`,
    `:residual` or a project tag definition ID; `nil` selects the company)
    """

  attr :tag_filters, :list, required: true, doc: "project filters narrow the project rows"

  @doc "Renders the project-by-month matrix and the selected cell's breakdown."
  @spec matrix(map()) :: Phoenix.LiveView.Rendered.t()
  def matrix(assigns) do
    %{profitability: profitability, params: params} = assigns
    # Tag filters only narrow the listed projects; the allocation always uses all
    # projects, and company or taxes filters do not select a project.
    project_filters = Enum.filter(assigns.tag_filters, &match?({:project, _id}, &1))
    rows = rows(profitability, project_filters, params.metric)
    periods = Enum.map(profitability.months, & &1.month) ++ [nil]
    {annual, months} = List.pop_at(Enum.with_index(periods), -1)

    assigns =
      assigns
      |> assign(:empty?, no_entries?(profitability.annual.totals))
      |> assign(:periods, periods)
      |> assign(:mobile_periods, [annual | months])
      |> assign(:rows, rows)
      |> assign(:project_filter?, project_filters != [])
      |> assign(:selection, selection(profitability, params))

    ~H"""
    <section
      id="analysis-project-matrix"
      aria-labelledby="analysis-project-matrix-title"
      class="@container"
    >
      <div class="grid grid-cols-1 items-start gap-4 @5xl:grid-cols-[minmax(0,1fr)_20rem]">
        <div class="flex min-w-0 flex-col gap-3 rounded-xl border border-grey-200 bg-white p-3 @sm:p-4 @3xl:p-6">
          <div class="flex flex-col gap-1">
            <h2 id="analysis-project-matrix-title" class="text-h5 font-medium text-grey-900">
              {gettext("Project results by month")}
            </h2>
            <p :if={not @empty?} id="analysis-project-matrix-unit" class="text-sm text-grey-700">
              {metric_caption(@params.metric)}
            </p>
          </div>
          <.empty_state
            :if={@empty?}
            id="analysis-project-matrix-empty"
            title={gettext("No income or expenses in %{year}.", year: @params.year)}
          />
          <p
            :if={not @empty? and not Enum.any?(@rows, &(&1.kind == :project))}
            id="analysis-project-matrix-no-projects"
            class="text-sm text-grey-700"
          >
            {if @project_filter?,
              do: gettext("The selected projects have no entries in %{year}.", year: @params.year),
              else: gettext("No project has entries in %{year}.", year: @params.year)}
          </p>
          <p :if={not @empty? and @project_filter?} class="text-sm text-grey-700">
            {gettext(
              "Only the selected projects are listed; Outside projects and Whole company cover all entries."
            )}
          </p>
          <div :if={not @empty?} class="hidden overflow-x-auto @4xl:block">
            <table
              aria-labelledby="analysis-project-matrix-title"
              aria-describedby="analysis-project-matrix-unit"
              class="border-separate border-spacing-0 text-sm"
            >
              <thead>
                <tr>
                  <th
                    scope="col"
                    class="sticky inset-s-0 z-10 bg-white pe-3 pbe-1 text-start text-xs font-normal text-grey-700"
                  >
                    {gettext("Project")}
                  </th>
                  <th
                    :for={month <- @periods}
                    scope="col"
                    class={[
                      "px-0.5 pbe-1 text-center text-xs font-normal",
                      column_styles(month == @selection.month, month == nil)
                    ]}
                  >
                    {period_label(month)}
                  </th>
                </tr>
              </thead>
              <tbody>
                <tr :for={row <- @rows} id={row.id}>
                  <th
                    scope="row"
                    class={[
                      "sticky inset-s-0 z-10 bg-white py-0.5 pe-3 text-start align-middle font-normal",
                      row.kind == :residual && "border-bs border-grey-200 pbs-2"
                    ]}
                  >
                    <.row_name
                      row={row}
                      selection={@selection}
                      class="w-28 text-sm/tight wrap-break-word @3xl:w-auto @3xl:max-w-56"
                    />
                  </th>
                  <td
                    :for={cell <- row.cells}
                    class={["p-0.5", row.kind == :residual && "border-bs border-grey-200 pbs-2"]}
                  >
                    <.cell
                      id={"#{row.id}-#{period_value(cell.month)}"}
                      row={row}
                      cell={cell}
                      selection={@selection}
                    />
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
          <div :if={not @empty?} class="overflow-x-auto @4xl:hidden">
            <table
              aria-labelledby="analysis-project-matrix-title"
              aria-describedby="analysis-project-matrix-unit"
              class="w-full border-separate border-spacing-0 text-xs"
            >
              <thead>
                <tr>
                  <th
                    scope="col"
                    class="sticky inset-s-0 z-10 bg-white pe-2 pbe-1"
                  >
                    <span class="sr-only">{gettext("Month")}</span>
                  </th>
                  <th
                    :for={row <- @rows}
                    scope="col"
                    class={[
                      "px-px pbe-1 text-center align-bottom font-normal",
                      row.kind == :residual && "border-s border-grey-200 ps-1"
                    ]}
                  >
                    <.row_name
                      row={row}
                      selection={@selection}
                      class="text-xs/tight wrap-break-word inline-24"
                    />
                  </th>
                </tr>
              </thead>
              <tbody>
                <tr
                  :for={{month, index} <- @mobile_periods}
                  id={"analysis-matrix-month-#{period_value(month)}"}
                >
                  <th
                    scope="row"
                    class={[
                      "sticky inset-s-0 z-10 bg-white py-0.5 pe-2 text-start text-xs font-normal",
                      column_styles(month == @selection.month, month == nil),
                      month == nil && "border-bs border-grey-200 pbs-2"
                    ]}
                  >
                    {period_label(month)}
                  </th>
                  <td
                    :for={row <- @rows}
                    class={[
                      "p-px",
                      row.kind == :residual && "border-s border-grey-200 ps-1",
                      month == nil && "border-bs border-grey-200 pbs-2"
                    ]}
                  >
                    <.cell
                      id={"#{row.id}-#{period_value(month)}-transposed"}
                      row={row}
                      cell={Enum.at(row.cells, index)}
                      selection={@selection}
                      compact
                    />
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
          <ul
            :if={not @empty?}
            id="analysis-project-matrix-legend"
            class="flex flex-wrap gap-x-5 gap-y-2 text-xs text-grey-700"
          >
            <li class="inline-flex items-center gap-2">
              <span class="relative h-3 w-5 rounded-xs bg-brick-200 before:absolute before:inset-s-0 before:inset-bs-0 before:size-1.5 before:bg-brick-700 before:[clip-path:polygon(0_0,100%_0,0_100%)]" />
              {pgettext("analysis result", "Loss")}
            </li>
            <li class="inline-flex items-center gap-2">
              <span class="h-3 w-5 rounded-xs bg-teal-300" />
              {pgettext("analysis result", "Profit")}
            </li>
            <li class="inline-flex items-center gap-2">
              <span class="h-3 w-5 rounded-xs bg-white inset-ring inset-ring-grey-300" />
              {gettext("Totals, not shaded")}
            </li>
            <li>{gettext("A darker shade means a larger amount.")}</li>
          </ul>
        </div>
        <.detail
          :if={not @empty?}
          selection={@selection}
          allocation={@params.allocation}
          metric={@params.metric}
        />
      </div>
    </section>
    """
  end

  attr :row, :map, required: true
  attr :selection, :map, required: true
  attr :class, :string, required: true

  defp row_name(assigns) do
    ~H"""
    <span class={["block", @class]}>
      <span class={["block", row_name_styles(@row.key == @selection.key)]}>{@row.name}</span>
      <span :if={@row.loss_months > 0} class="block text-xs text-brick-700">
        {ngettext("%{count} month at a loss", "%{count} months at a loss", @row.loss_months)}
      </span>
    </span>
    """
  end

  attr :id, :string, required: true
  attr :row, :map, required: true
  attr :cell, :map, required: true
  attr :selection, :map, required: true
  attr :compact, :boolean, default: false, doc: "narrower cells of the phone orientation"

  defp cell(assigns) do
    assigns =
      assign(
        assigns,
        :selected?,
        assigns.row.key == assigns.selection.key and assigns.cell.month == assigns.selection.month
      )

    ~H"""
    <FirmowidUI.Components.Button.button
      id={@id}
      type="button"
      variant="unstyled"
      phx-click="select-cell"
      phx-value-month={period_value(@cell.month)}
      phx-value-project={@row.value}
      aria-pressed={to_string(@selected?)}
      aria-label={cell_description(@row.name, @cell)}
      title={cell_description(@row.name, @cell)}
      class={cell_styles(@cell, @selected?, @compact)}
    >
      {if @cell.value, do: thousands(@cell.value), else: "—"}
    </FirmowidUI.Components.Button.button>
    """
  end

  attr :selection, :map, required: true
  attr :allocation, :atom, required: true
  attr :metric, :atom, required: true

  defp detail(assigns) do
    assigns = assign(assigns, :breakdown, assigns.selection.breakdown)

    ~H"""
    <aside
      id="analysis-matrix-detail"
      aria-labelledby="analysis-matrix-detail-title"
      class="flex flex-col gap-4 rounded-xl border border-grey-200 bg-white p-4 @3xl:p-6 @5xl:sticky @5xl:inset-bs-4"
    >
      <div class="flex flex-col gap-0.5">
        <h3
          id="analysis-matrix-detail-title"
          class="text-h5 font-medium wrap-break-word text-grey-900"
        >
          {@selection.name}
        </h3>
        <p class="text-sm text-grey-700">{period_name(@selection)}</p>
      </div>
      <%= if @breakdown do %>
        <div class="flex flex-col gap-1">
          <p class="text-sm text-grey-700">{metric_name(@metric)}</p>
          <p class="flex flex-wrap items-center gap-x-3 gap-y-1">
            <span class={[
              "text-2xl font-semibold whitespace-nowrap tabular-nums",
              result_styles(metric_value(@breakdown, @metric))
            ]}>
              {money(metric_value(@breakdown, @metric))}
            </span>
            <span
              :if={Decimal.negative?(metric_value(@breakdown, @metric))}
              class="rounded-sm bg-brick-200 px-2 py-0.5 text-xs font-medium text-brick-700"
            >
              {pgettext("analysis result", "Loss")}
            </span>
          </p>
        </div>
      <% else %>
        <p id="analysis-matrix-detail-empty" class="text-sm text-grey-700">
          {gettext("No entries in this period.")}
        </p>
      <% end %>
      <dl class="grid grid-cols-[minmax(0,1fr)_auto] text-sm">
        <div :for={line <- breakdown_lines(@breakdown)} class="contents">
          <dt class={["py-1.5 pe-3", line_styles(line.kind)]}>{line.label}</dt>
          <dd class={["py-1.5 text-end whitespace-nowrap tabular-nums", line_styles(line.kind)]}>
            {line.value}
          </dd>
        </div>
      </dl>
      <p :if={@breakdown && @selection.kind == :project} class="text-xs text-grey-700">
        {allocation_note(@allocation)}
      </p>
      <.link
        :if={@selection.tagging_path}
        id="analysis-matrix-detail-tagging"
        kind="text"
        size="small"
        patch={@selection.tagging_path}
      >
        {gettext("Open in tagging")}
      </.link>
    </aside>
    """
  end

  defp rows(profitability, project_filters, metric) do
    project_rows =
      profitability.annual.projects
      |> selected_projects(project_filters)
      |> Enum.map(fn %{key: {:project, id} = key} = project ->
        row(profitability, metric, %{
          id: "analysis-matrix-project-#{id}",
          key: key,
          kind: :project,
          value: id,
          name: project.name
        })
      end)

    shade_max =
      project_rows
      |> Enum.flat_map(& &1.cells)
      |> Enum.filter(&(&1.month && &1.value))
      |> Enum.map(&Decimal.abs(&1.value))
      |> Enum.reduce(Decimal.new(0), &Decimal.max/2)

    project_rows = Enum.map(project_rows, &shade_row(&1, shade_max))

    project_rows ++
      [
        row(profitability, metric, %{
          id: "analysis-matrix-residual",
          key: :residual,
          kind: :residual,
          value: "poza_projektami",
          name: gettext("Outside projects")
        }),
        row(profitability, metric, %{
          id: "analysis-matrix-company",
          key: :company,
          kind: :company,
          value: "firma",
          name: gettext("Whole company")
        })
      ]
  end

  defp selected_projects(projects, []), do: projects

  defp selected_projects(projects, project_filters), do: Enum.filter(projects, &(&1.key in project_filters))

  defp row(profitability, metric, row) do
    periods = Enum.map(profitability.months, &{&1.month, &1}) ++ [{nil, profitability.annual}]

    cells =
      Enum.map(periods, fn {month, period} ->
        value =
          case breakdown(row.key, period) do
            nil -> nil
            breakdown -> metric_value(breakdown, metric)
          end

        %{month: month, value: value, kind: row.kind, shade: nil}
      end)

    loss_months =
      if row.kind == :project,
        do: Enum.count(cells, &(&1.month && &1.value && Decimal.negative?(&1.value))),
        else: 0

    Map.merge(row, %{cells: cells, loss_months: loss_months})
  end

  # Shading compares project months on one scale; year totals stay unshaded.
  defp shade_row(row, max) do
    cells =
      Enum.map(row.cells, fn
        %{month: %Date{}, value: %Decimal{} = value} = cell -> %{cell | shade: shade(value, max)}
        cell -> cell
      end)

    %{row | cells: cells}
  end

  defp shade(value, max) do
    if Decimal.eq?(value, 0) do
      "bg-grey-100"
    else
      level =
        value |> Decimal.abs() |> Decimal.div(max) |> Decimal.to_float() |> Kernel.*(4) |> ceil()

      Enum.at(@shades[if(Decimal.negative?(value), do: :loss, else: :profit)], level - 1)
    end
  end

  # Without a project, or with a project absent from the year, the company is selected.
  defp selection(profitability, params) do
    project =
      case params.project do
        id when is_binary(id) ->
          Enum.find(profitability.annual.projects, &(&1.key == {:project, id}))

        _other ->
          nil
      end

    {key, kind, name} =
      cond do
        project -> {project.key, :project, project.name}
        params.project == :residual -> {:residual, :residual, gettext("Outside projects")}
        true -> {:company, :company, gettext("Whole company")}
      end

    period =
      case params.month do
        nil -> profitability.annual
        month -> Enum.find(profitability.months, &(&1.month == month))
      end

    %{
      key: key,
      kind: kind,
      name: name,
      month: params.month,
      year: params.year,
      breakdown: breakdown(key, period),
      tagging_path: tagging_path(params.month, key)
    }
  end

  defp tagging_path(nil, _key), do: nil

  defp tagging_path(month, {:project, _id} = key), do: Navigation.view_path(%{view: :tagging, month: month}, [key])

  defp tagging_path(month, _key), do: Navigation.view_path(%{view: :tagging, month: month}, [])

  defp breakdown({:project, _id} = key, period), do: Enum.find(period.projects, &(&1.key == key))
  defp breakdown(:residual, period), do: totals_breakdown(period.residual)
  defp breakdown(:company, period), do: totals_breakdown(period.totals)

  # Unallocated company and tax costs stay outside projects; every other expense
  # (project or unassigned) is a direct expense of the row.
  defp totals_breakdown(totals) do
    if no_entries?(totals) do
      nil
    else
      company = category_amount(totals.expense_categories, :company)
      taxes = category_amount(totals.expense_categories, :taxes)

      direct =
        totals.total_expenses |> Decimal.abs() |> Decimal.sub(company) |> Decimal.sub(taxes)

      %{
        income: totals.total_income,
        direct_expenses: direct,
        company_share: company,
        taxes_share: taxes,
        direct_profit: Decimal.sub(totals.total_income, direct),
        net_profit: totals.net_profit
      }
    end
  end

  defp no_entries?(totals), do: totals.income_categories == [] and totals.expense_categories == []

  defp category_amount(categories, key) do
    Enum.find_value(categories, Decimal.new(0), &(&1.key == key && &1.amount))
  end

  defp breakdown_lines(breakdown) do
    Enum.map(
      [
        {:item, gettext("Income"), :income, & &1},
        {:item, gettext("Direct expenses"), :direct_expenses, &cost/1},
        {:subtotal, gettext("Direct result"), :direct_profit, & &1},
        {:item, gettext("Company costs"), :company_share, &cost/1},
        {:item, gettext("Taxes"), :taxes_share, &cost/1},
        {:total, gettext("Net result"), :net_profit, & &1}
      ],
      fn {kind, label, field, sign} ->
        value = if breakdown, do: breakdown |> Map.fetch!(field) |> sign.() |> money(), else: "—"
        %{kind: kind, label: label, value: value}
      end
    )
  end

  defp cost(amount), do: if(Decimal.eq?(amount, 0), do: amount, else: Decimal.negate(amount))

  defp line_styles(:item), do: "text-grey-700"
  defp line_styles(:subtotal), do: "border-bs border-grey-200 font-medium text-grey-900"
  defp line_styles(:total), do: "border-bs border-grey-900 font-semibold text-grey-900"

  defp metric_value(breakdown, :net), do: breakdown.net_profit
  defp metric_value(breakdown, :direct), do: breakdown.direct_profit

  defp metric_name(:net), do: gettext("Net result")
  defp metric_name(:direct), do: gettext("Direct result")

  defp metric_caption(:net), do: gettext("Result after company costs and taxes, in thousands of PLN")

  defp metric_caption(:direct), do: gettext("Direct result before company costs and taxes, in thousands of PLN")

  defp allocation_note(:income), do: gettext("Company costs and taxes are split by project income.")

  defp allocation_note(:direct_expenses), do: gettext("Company costs and taxes are split by project direct expenses.")

  defp cell_description(name, cell) do
    period = if cell.month, do: month_name(cell.month, "LLLL y"), else: gettext("Year")

    if cell.value,
      do:
        gettext("%{name}, %{period}: %{amount}",
          name: name,
          period: period,
          amount: money(cell.value)
        ),
      else: gettext("%{name}, %{period}: no entries", name: name, period: period)
  end

  defp cell_styles(cell, selected?, compact?) do
    [
      if(compact?, do: "min-w-11 px-1", else: "min-w-12 px-1.5"),
      "relative block min-h-11 w-full cursor-pointer rounded-md text-center whitespace-nowrap tabular-nums focus-visible:outline-3 focus-visible:outline-offset-1 focus-visible:outline-teal-700 active:brightness-95 pointer-fine:hover:brightness-95",
      cell_fill(cell),
      cell_text(cell),
      if(selected?,
        do: "inset-ring-2 inset-ring-grey-900",
        else: cell.shade == nil && "inset-ring inset-ring-grey-200"
      ),
      cell.value && Decimal.negative?(cell.value) &&
        "before:absolute before:inset-bs-0 before:inset-s-0 before:size-2.5 before:rounded-ss-md before:bg-brick-700 before:[clip-path:polygon(0_0,100%_0,0_100%)]"
    ]
  end

  defp cell_fill(%{shade: nil}), do: "bg-white"
  defp cell_fill(%{shade: shade}), do: shade

  defp cell_text(%{value: nil}), do: "text-grey-600"

  defp cell_text(cell) do
    cond do
      Decimal.negative?(cell.value) and cell.shade == nil -> "font-semibold text-brick-700"
      Decimal.negative?(cell.value) -> "font-semibold text-grey-900"
      cell.kind == :company or cell.month == nil -> "font-semibold text-grey-900"
      true -> "text-grey-900"
    end
  end

  defp column_styles(true, _year?), do: "font-semibold text-grey-900 underline decoration-2 underline-offset-4"

  defp column_styles(false, true), do: "font-medium text-grey-900"
  defp column_styles(false, false), do: "text-grey-700"

  defp row_name_styles(true), do: "font-semibold text-grey-900 underline decoration-2 underline-offset-4"

  defp row_name_styles(false), do: "font-medium text-grey-900"

  defp result_styles(amount), do: if(Decimal.negative?(amount), do: "text-brick-700", else: "text-grey-900")

  defp period_label(nil), do: gettext("Year")
  defp period_label(month), do: month_name(month, "LLL")

  defp period_value(nil), do: "rok"
  defp period_value(month), do: Date.to_iso8601(month)

  defp period_name(%{month: nil, year: year}), do: gettext("Year %{year}", year: year)
  defp period_name(%{month: month}), do: month_name(month, "LLLL y")

  defp money(amount), do: Money.to_string!(Money.new(:PLN, amount))

  defp thousands(amount) do
    value = Decimal.div(amount, 1000)

    digits =
      if Decimal.eq?(value, 0),
        do: 1,
        else: Enum.find(1..5, &(not Decimal.eq?(Decimal.round(value, &1), 0)))

    Firmowid.Cldr.Number.to_string!(value, fractional_digits: digits)
  end

  defp month_name(month, format) do
    month
    |> Firmowid.Cldr.Date.to_string!(format: format, locale: Gettext.get_locale(Firmowid.Gettext))
    |> String.capitalize()
  end
end
