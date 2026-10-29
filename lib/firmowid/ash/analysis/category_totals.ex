defmodule Firmowid.Ash.Analysis.CategoryTotals do
  @moduledoc """
  Pure aggregation of single-currency amounts into company, taxes, project and
  unassigned shares. Callers must normalize or separate currencies before aggregation.
  Allocation conserves each entity's rounded cent amount.
  """

  @type category_key ::
          {:project, String.t()} | {:function, String.t()} | :company | :taxes | :unassigned
  @type category :: %{
          key: category_key(),
          name: String.t() | nil,
          color: String.t(),
          amount: Decimal.t()
        }
  @type totals :: %{
          total_income: Decimal.t(),
          total_expenses: Decimal.t(),
          net_profit: Decimal.t(),
          income_categories: [category()],
          expense_categories: [category()]
        }

  @doc """
  Aggregates `{single_currency_amount, loaded_entity_tags}` pairs.

  Rounds each signed amount to cents and allocates project shares in
  proportion to each tag's `:weight` metadata (1 when absent), giving leftover
  cents to the largest remainders, then to sorted IDs. Shares of overhead tag
  definitions are keyed `{:function, id}`: they are shared costs, selected by
  the company filter. Built-in categories have nil names for caller-owned
  translation. Internal entities are excluded.

  Filters select shares with OR semantics (`{:project, id}`, `{:company}` or `{:taxes}`),
  after allocation. Category amounts are positive; expense totals stay negative.
  Zero shares are omitted. Rows are deterministically ordered by category key.
  """
  @spec aggregate([{Decimal.t(), [map()]}], [tuple()]) :: totals()
  def aggregate(entities, filters \\ []) do
    categories =
      Enum.reduce(entities, %{income: %{}, expenses: %{}}, fn {amount, tags}, acc ->
        cents =
          amount |> Decimal.abs() |> Decimal.round(2) |> Decimal.mult(100) |> Decimal.to_integer()

        direction = if Decimal.negative?(amount), do: :expenses, else: :income

        tags
        |> categories_for_tags()
        |> allocate(cents)
        |> Enum.filter(&(selected?(&1.key, filters) and Decimal.positive?(&1.amount)))
        |> Enum.reduce(acc, fn row, acc ->
          update_in(acc, [direction], fn rows ->
            Map.update(rows, row.key, row, &%{&1 | amount: Decimal.add(&1.amount, row.amount)})
          end)
        end)
      end)

    build_totals(category_list(categories.income), category_list(categories.expenses))
  end

  @doc "Combines already allocated totals in one currency without reallocating or rerounding shares."
  @spec combine([totals()]) :: totals()
  def combine(totals) do
    build_totals(
      combined_categories(totals, :income_categories),
      combined_categories(totals, :expense_categories)
    )
  end

  defp build_totals(income, expenses) do
    total_income = sum(income)
    total_expenses = expenses |> sum() |> Decimal.negate()

    %{
      total_income: total_income,
      total_expenses: total_expenses,
      net_profit: Decimal.add(total_income, total_expenses),
      income_categories: income,
      expense_categories: expenses
    }
  end

  defp combined_categories(totals, field) do
    totals
    |> Enum.flat_map(&Map.fetch!(&1, field))
    |> Enum.reduce(%{}, fn row, rows ->
      Map.update(rows, row.key, row, &%{&1 | amount: Decimal.add(&1.amount, row.amount)})
    end)
    |> category_list()
  end

  defp categories_for_tags(tags) do
    cond do
      Enum.any?(tags, &(&1.kind == :internal)) -> []
      Enum.any?(tags, &(&1.kind == :company)) -> [%{key: :company, name: nil, color: "#354E4E"}]
      Enum.any?(tags, &(&1.kind == :taxes)) -> [%{key: :taxes, name: nil, color: "#111827"}]
      true -> project_categories(tags)
    end
  end

  defp project_categories(tags) do
    projects =
      tags
      |> Enum.filter(&(&1.kind == :project))
      |> Enum.uniq_by(& &1.tag_definition_id)
      |> Enum.sort_by(& &1.tag_definition_id)
      |> Enum.map(&project_category/1)

    case projects do
      [] -> [%{key: :unassigned, name: nil, color: "#94A3B8"}]
      projects -> projects
    end
  end

  defp project_category(tag) do
    %{
      key: {if(tag.tag_definition.overhead, do: :function, else: :project), tag.tag_definition_id},
      name: tag.tag_definition.name,
      color: tag.tag_definition.color,
      weight: Map.get(tag.__metadata__, :weight, 1)
    }
  end

  defp allocate([], _cents), do: []

  defp allocate(categories, cents) do
    total_weight = categories |> Enum.map(&Map.get(&1, :weight, 1)) |> Enum.sum()

    shares =
      Enum.map(categories, fn category ->
        product = cents * Map.get(category, :weight, 1)
        {category, div(product, total_weight), rem(product, total_weight)}
      end)

    leftover = cents - (shares |> Enum.map(&elem(&1, 1)) |> Enum.sum())

    extra =
      shares
      |> Enum.with_index()
      |> Enum.sort_by(fn {{_category, _share, remainder}, index} -> {-remainder, index} end)
      |> Enum.take(leftover)
      |> MapSet.new(&elem(&1, 1))

    shares
    |> Enum.with_index()
    |> Enum.map(fn {{category, share, _remainder}, index} ->
      share = share + if(MapSet.member?(extra, index), do: 1, else: 0)

      category
      |> Map.delete(:weight)
      |> Map.put(:amount, share |> Decimal.new() |> Decimal.div(100))
    end)
  end

  defp selected?(_key, []), do: true
  defp selected?(:company, filters), do: {:company} in filters
  defp selected?(:taxes, filters), do: {:taxes} in filters
  defp selected?({:project, id}, filters), do: {:project, id} in filters
  defp selected?({:function, _id}, filters), do: {:company} in filters
  defp selected?(:unassigned, _filters), do: false

  defp category_list(rows), do: rows |> Map.values() |> Enum.sort_by(& &1.key)
  defp sum(rows), do: Enum.reduce(rows, Decimal.new(0), &Decimal.add(&1.amount, &2))
end
