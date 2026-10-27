defmodule Firmowid.Ash.Analysis.CategoryReview do
  @moduledoc """
  Pure classification of analysis entries into industry template categories.

  The owner has the last word: an entry takes the category confirmed for its
  counterparty. Otherwise it is only suggested one, from a certain signal
  (salaries, tax tags) or else the one the classifier chose from its
  description, until the owner confirms. Entries are grouped by counterparty
  and that outcome, so a mixed supplier shows each kind of purchase.
  """

  alias Firmowid.Ash.Analysis.IndustryTemplate

  @type source :: :certain | :jev
  @type entry :: %{
          side: IndustryTemplate.side(),
          month: Date.t(),
          name: String.t(),
          amount: Decimal.t(),
          lines: [String.t()],
          certain: IndustryTemplate.category() | nil,
          classified: IndustryTemplate.category() | nil
        }

  @doc """
  Builds the review of `entries` with the owner's `rules` for `industry`.

  Amounts are positive. Each side lists template categories (plus any other
  confirmed ones) with their amounts, and the amount still waiting for review.
  Groups are sorted by amount, largest first; `months` holds their amount per
  month. `unclassified` lists the entries still waiting for the classifier:
  without a confirmed counterparty, a certain signal or a stored category;
  `classifier_suggested` the entries whose suggestion came from it.
  The result echoes `industry`.
  """
  @spec build([entry()], [map()], IndustryTemplate.industry()) :: map()
  def build(entries, rules, industry) do
    rules = Map.new(rules, &{{&1.side, &1.counterparty_key}, &1})

    resolved =
      Enum.map(entries, fn entry ->
        key = key(entry.name)
        {entry, key, resolve(entry, Map.get(rules, {entry.side, key}))}
      end)

    groups =
      resolved
      |> Enum.group_by(
        fn {entry, key, resolution} -> {entry.side, key, resolution} end,
        &elem(&1, 0)
      )
      |> Enum.map(fn {{side, key, resolution}, entries} ->
        group(side, key, entries, resolution)
      end)
      |> Enum.sort_by(& &1.amount, {:desc, Decimal})

    unclassified = for {entry, _key, {nil, nil}} <- resolved, do: entry
    classifier_suggested = for {entry, _key, {_category, :jev}} <- resolved, do: entry

    %{
      income: side_totals(groups, :income, industry),
      expenses: side_totals(groups, :expenses, industry),
      groups: groups,
      unclassified: unclassified,
      classifier_suggested: classifier_suggested,
      industry: industry
    }
  end

  @doc """
  Sums the industry's key costs from confirmed or suggested categories, with
  their share of income (nil without income).
  """
  @spec key_costs(map()) :: [%{key: atom(), amount: Decimal.t(), share: Decimal.t() | nil}]
  def key_costs(review) do
    expenses = Enum.filter(review.groups, &(&1.side == :expenses))

    for {key, categories} <- IndustryTemplate.key_costs(review.industry) do
      amount = expenses |> Enum.filter(&((&1.category || &1.suggestion) in categories)) |> sum()

      share =
        if Decimal.positive?(review.income.total), do: Decimal.div(amount, review.income.total)

      %{key: key, amount: amount, share: share}
    end
  end

  @doc """
  Narrows the review's groups to `month`: `amount` becomes the month's amount
  and `average` the group's mean monthly amount over `compared` months (nil
  without any). Groups absent from the month keep a zero amount, so categories
  can still compare against their usual amount.
  """
  @spec month(map(), Date.t(), [Date.t()]) :: [map()]
  def month(review, month, compared) do
    Enum.map(review.groups, fn group ->
      average =
        if compared == [],
          do: nil,
          else:
            compared
            |> Enum.map(&Map.get(group.months, &1, Decimal.new(0)))
            |> Enum.reduce(&Decimal.add/2)
            |> Decimal.div(length(compared))

      Map.put(%{group | amount: Map.get(group.months, month, Decimal.new(0))}, :average, average)
    end)
  end

  defp group(side, key, entries, {category, source}) do
    status = if source == :confirmed, do: :confirmed, else: :pending

    largest = Enum.max_by(entries, & &1.amount, Decimal)

    %{
      side: side,
      key: key,
      name: largest.name,
      amount: sum(entries),
      months:
        entries
        |> Enum.group_by(& &1.month)
        |> Map.new(fn {month, entries} -> {month, sum(entries)} end),
      count: length(entries),
      suggestion: if(source != :confirmed, do: category),
      source: if(source != :confirmed, do: source),
      reason: Enum.take(largest.lines, 1),
      status: status,
      category: if(status == :confirmed, do: category)
    }
  end

  # The owner has the last word; a certain signal, else the classifier, only suggests.
  defp resolve(_entry, %{category: category}), do: {category, :confirmed}
  defp resolve(%{certain: category}, nil) when category != nil, do: {category, :certain}
  defp resolve(%{classified: category}, nil) when category != nil, do: {category, :jev}
  defp resolve(_entry, nil), do: {nil, nil}

  defp key(name), do: name |> IndustryTemplate.normalize() |> String.trim()

  defp side_totals(groups, side, industry) do
    groups = Enum.filter(groups, &(&1.side == side))
    amounts = groups |> Enum.filter(& &1.category) |> Enum.group_by(& &1.category, & &1.amount)
    keys = Enum.uniq(IndustryTemplate.categories(industry, side) ++ Map.keys(amounts))

    %{
      total: sum(groups),
      pending: groups |> Enum.reject(& &1.category) |> sum(),
      categories:
        Enum.map(keys, fn key ->
          %{
            key: key,
            amount: amounts |> Map.get(key, []) |> Enum.reduce(Decimal.new(0), &Decimal.add/2)
          }
        end)
    }
  end

  defp sum(rows), do: Enum.reduce(rows, Decimal.new(0), &Decimal.add(&1.amount, &2))
end
