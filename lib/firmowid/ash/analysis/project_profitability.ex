defmodule Firmowid.Ash.Analysis.ProjectProfitability do
  @moduledoc """
  Pure management scenarios, not bookkeeping or an approved allocation policy.

  Consumes unfiltered, single-currency YearSummary months. Costs of running the
  company (company, tax and unassigned expenses) are allocated by the time
  tracked on each project. Projects counted as shared costs (`{:function, id}`)
  are not allocated: they stay in the residual with all income outside projects,
  so what each of them adds stays visible. No tags, documents or source
  values are changed. Project selection belongs after this calculation, never
  in the source summary's tag filters.
  """

  alias Firmowid.Ash.Analysis.CategoryTotals

  @type project :: %{
          key: {:project, String.t()},
          name: String.t() | nil,
          color: String.t(),
          seconds: non_neg_integer(),
          income: Decimal.t(),
          direct_expenses: Decimal.t(),
          direct_profit: Decimal.t(),
          company_share: Decimal.t(),
          taxes_share: Decimal.t(),
          total_expenses: Decimal.t(),
          net_profit: Decimal.t()
        }
  @type period :: %{
          projects: [project()],
          residual: CategoryTotals.totals(),
          totals: CategoryTotals.totals()
        }
  @type result :: %{
          scenario: :management,
          allocation_basis: :hours,
          months: [month()],
          annual: period()
        }
  @type month :: %{
          month: Date.t(),
          projects: [project()],
          residual: CategoryTotals.totals(),
          totals: CategoryTotals.totals()
        }

  @doc """
  Allocates each month's actual overhead by the seconds tracked on each project
  that month, then sums the allocated months into `annual` without reallocating.

  `seconds_by_month` maps a month to `%{key, name, color, seconds}` rows, as
  returned by `Firmowid.Ash.Analysis.project_seconds_by_month/2`. A project
  with tracked time but no money that month still takes its overhead share.

  Category amounts must already be nonnegative whole-cent Decimals, as produced
  by CategoryTotals. All component expenses and shares are positive;
  `total_expenses` is negative and profits are signed. Residual uses the original
  CategoryTotals shape and signs. `totals` always includes projects AND residual.

  Largest integer remainders receive leftover cents; ties use ascending project
  IDs independently for company and taxes. Without tracked time, all overhead
  stays in residual; there is no equal-share fallback. Projects are sorted by ID.
  Annual project metadata comes from its first appearance in the supplied months.

  Fetch the source with `YearSummary.get(year, %{tag_filters: []}, scope: scope)`.
  To display one project, filter the returned `projects` lists, keeping residual
  and full-period totals separate from any selected-project subtotal. An already
  filtered source cannot be detected and would give incorrect allocation shares.
  """
  @spec from_year_summary(%{months: [map()]}, %{Date.t() => [map()]}) :: result()
  def from_year_summary(summary, seconds_by_month) do
    months =
      Enum.map(summary.months, fn month ->
        month.totals
        |> allocate_month(Map.get(seconds_by_month, month.month, []))
        |> Map.put(:month, month.month)
      end)

    %{
      scenario: :management,
      allocation_basis: :hours,
      months: months,
      annual: %{
        projects: combine_projects(months),
        residual: CategoryTotals.combine(Enum.map(months, & &1.residual)),
        totals: CategoryTotals.combine(Enum.map(months, & &1.totals))
      }
    }
  end

  defp allocate_month(totals, tracked) do
    projects = project_amounts(totals, tracked)
    weights = Enum.map(projects, &{&1.key, &1.seconds})

    # Expenses without a project run the company, like the company category; functions stay apart.
    company =
      totals.expense_categories
      |> Enum.filter(&shared_key?(&1.key))
      |> Enum.map(&cents(&1.amount))
      |> Enum.sum()

    taxes = category_cents(totals.expense_categories, :taxes)
    company_shares = allocate(company, weights)
    taxes_shares = allocate(taxes, weights)

    projects =
      Enum.map(projects, fn project ->
        project
        |> Map.put(:company_share, Map.get(company_shares, project.key, 0))
        |> Map.put(:taxes_share, Map.get(taxes_shares, project.key, 0))
        |> project_result()
      end)

    residual_expenses =
      Enum.reject(totals.expense_categories, fn category ->
        project_key?(category.key) or
          (shared_key?(category.key) and map_size(company_shares) > 0) or
          (category.key == :taxes and map_size(taxes_shares) > 0)
      end)

    residual =
      CategoryTotals.combine([
        %{
          totals
          | income_categories: Enum.reject(totals.income_categories, &project_key?(&1.key)),
            expense_categories: residual_expenses
        }
      ])

    %{projects: projects, residual: residual, totals: totals}
  end

  defp project_amounts(totals, tracked) do
    projects =
      Enum.reduce(tracked, %{}, fn row, projects ->
        projects
        |> Map.put_new(row.key, empty_project(row))
        |> update_in([row.key, :seconds], &(&1 + row.seconds))
      end)

    [{:income, totals.income_categories}, {:direct_expenses, totals.expense_categories}]
    |> Enum.reduce(projects, fn {field, categories}, projects ->
      categories
      |> Enum.filter(&project_key?(&1.key))
      |> Enum.reduce(projects, fn category, projects ->
        projects
        |> Map.put_new(category.key, empty_project(category))
        |> update_in([category.key, field], &(&1 + cents(category.amount)))
      end)
    end)
    |> Map.values()
    |> Enum.sort_by(& &1.key)
  end

  defp empty_project(row),
    do: %{key: row.key, name: row.name, color: row.color, seconds: 0, income: 0, direct_expenses: 0}

  defp allocate(amount, weights) do
    total = weights |> Enum.map(&elem(&1, 1)) |> Enum.sum()

    if total == 0 do
      %{}
    else
      shares =
        Enum.map(weights, fn {key, weight} ->
          {key, div(amount * weight, total), rem(amount * weight, total)}
        end)

      leftover = amount - Enum.sum(Enum.map(shares, &elem(&1, 1)))

      extra =
        shares
        |> Enum.sort_by(fn {key, _share, remainder} -> {-remainder, key} end)
        |> Enum.take(leftover)
        |> MapSet.new(&elem(&1, 0))

      Map.new(shares, fn {key, share, _remainder} ->
        {key, share + if(MapSet.member?(extra, key), do: 1, else: 0)}
      end)
    end
  end

  defp project_result(project) do
    expenses = project.direct_expenses + project.company_share + project.taxes_share

    project
    |> Map.put(:direct_profit, project.income - project.direct_expenses)
    |> Map.put(:total_expenses, -expenses)
    |> Map.put(:net_profit, project.income - expenses)
    |> Map.new(fn
      {field, value} when field in [:key, :name, :color, :seconds] -> {field, value}
      {field, value} -> {field, money(value)}
    end)
  end

  defp combine_projects(months) do
    months
    |> Enum.flat_map(& &1.projects)
    |> Enum.reduce(%{}, fn project, projects ->
      Map.update(projects, project.key, project, fn existing ->
        Map.new(existing, fn
          {field, value} when field in [:key, :name, :color] -> {field, value}
          {:seconds, value} -> {:seconds, value + project.seconds}
          {field, value} -> {field, money(cents(value) + cents(Map.fetch!(project, field)))}
        end)
      end)
    end)
    |> Map.values()
    |> Enum.sort_by(& &1.key)
  end

  defp category_cents(categories, key) do
    categories
    |> Enum.filter(&(&1.key == key))
    |> Enum.map(&cents(&1.amount))
    |> Enum.sum()
  end

  defp shared_key?(key), do: key in [:company, :unassigned]

  defp project_key?({:project, _id}), do: true
  defp project_key?(_key), do: false

  # Shift the exponent exactly: allocation arithmetic must not depend on the
  # caller's Decimal precision context or introduce a second rounding step.
  defp cents(%Decimal{} = amount), do: Decimal.to_integer(%{amount | exp: amount.exp + 2})
  defp money(cents), do: Decimal.new(if(cents < 0, do: -1, else: 1), abs(cents), -2)
end
