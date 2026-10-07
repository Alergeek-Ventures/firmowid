defmodule Firmowid.Ash.Analysis.CategoryTotals do
  @moduledoc """
  Pure aggregation of normalized PLN amounts into company, project and
  unassigned shares. Allocation conserves each entity's rounded cent amount.
  """

  @type category_key :: {:project, String.t()} | :company | :unassigned
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
  Aggregates `{normalized_amount, loaded_entity_tags}` pairs.

   Rounds each signed PLN amount to cents and allocates equal project shares
   with sorted IDs receiving leftover cents. Built-in categories
  have nil names for caller-owned translation. Internal entities are excluded.

  Filters select shares with OR semantics (`{:project, id}` or `{:company}`),
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

    income = category_list(categories.income)
    expenses = category_list(categories.expenses)
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

  defp categories_for_tags(tags) do
    cond do
      Enum.any?(tags, &(&1.kind == :internal)) -> []
      Enum.any?(tags, &(&1.kind == :company)) -> [%{key: :company, name: nil, color: "#354E4E"}]
      true -> project_categories(tags)
    end
  end

  defp project_categories(tags) do
    projects =
      tags
      |> Enum.filter(&(&1.kind == :project))
      |> Enum.uniq_by(& &1.tag_definition_id)
      |> Enum.sort_by(& &1.tag_definition_id)
      |> Enum.map(fn tag ->
        %{
          key: {:project, tag.tag_definition_id},
          name: tag.tag_definition.name,
          color: tag.tag_definition.color
        }
      end)

    case projects do
      [] -> [%{key: :unassigned, name: nil, color: "#94A3B8"}]
      projects -> projects
    end
  end

  defp allocate([], _cents), do: []

  defp allocate(categories, cents) do
    count = length(categories)

    categories
    |> Enum.with_index()
    |> Enum.map(fn {category, index} ->
      share = div(cents, count) + if(index < rem(cents, count), do: 1, else: 0)
      Map.put(category, :amount, share |> Decimal.new() |> Decimal.div(100))
    end)
  end

  defp selected?(_key, []), do: true
  defp selected?(:company, filters), do: {:company} in filters
  defp selected?({:project, id}, filters), do: {:project, id} in filters
  defp selected?(:unassigned, _filters), do: false

  defp category_list(rows), do: rows |> Map.values() |> Enum.sort_by(& &1.key)
  defp sum(rows), do: Enum.reduce(rows, Decimal.new(0), &Decimal.add(&1.amount, &2))
end
