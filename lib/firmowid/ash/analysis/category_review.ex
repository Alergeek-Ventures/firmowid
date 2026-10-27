defmodule Firmowid.Ash.Analysis.CategoryReview do
  @moduledoc """
  Pure classification of analysis entries into industry template categories.

  Entries are grouped by counterparty. A group takes the category the owner
  confirmed for it; otherwise it gets a suggestion, from the strongest source:
  certain signals (salaries, tax tags), invoice lines, the counterparty name,
  invoice line words of groups the owner already confirmed, or the industry's
  default income. Suggestions count in totals only once their source proved
  accurate enough on the owner's confirmations; until then they wait for review.
  """

  alias Firmowid.Ash.Analysis.IndustryTemplate

  @type source :: :certain | :invoice_lines | :name | :learned | :default
  @type entry :: %{
          side: IndustryTemplate.side(),
          month: Date.t(),
          name: String.t(),
          amount: Decimal.t(),
          lines: [{String.t(), Decimal.t()}],
          certain: IndustryTemplate.category() | nil
        }

  @auto_accuracy 0.9
  @auto_samples 10

  @doc """
  Builds the review of `entries` with the owner's `rules` for `industry`.

  Amounts are positive. Each side lists template categories (plus any other
  confirmed ones) with their amounts, and the amount still waiting for review.
  Groups are sorted by amount, largest first; `months` holds their amount per
  month. The result echoes `industry`.
  """
  @spec build([entry()], [map()], IndustryTemplate.industry()) :: map()
  def build(entries, rules, industry) do
    rules = Map.new(rules, &{{&1.side, &1.counterparty_key}, &1})
    accuracy = accuracy(Map.values(rules))
    learned = learned_words(entries, rules)

    groups =
      entries
      |> Enum.group_by(&{&1.side, key(&1.name)})
      |> Enum.map(fn {{side, key}, entries} ->
        group(side, key, entries, Map.get(rules, {side, key}), industry, learned, accuracy)
      end)
      |> Enum.sort_by(& &1.amount, {:desc, Decimal})

    %{
      income: side_totals(groups, :income, industry),
      expenses: side_totals(groups, :expenses, industry),
      groups: groups,
      accuracy: accuracy,
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

  defp group(side, key, entries, rule, industry, learned, accuracy) do
    {suggestion, source, reason} = suggest(side, entries, industry, learned)

    status =
      cond do
        rule != nil -> :confirmed
        suggestion != nil and automatic?(accuracy, source) -> :automatic
        true -> :pending
      end

    %{
      side: side,
      key: key,
      name: entries |> Enum.max_by(& &1.amount, Decimal) |> Map.fetch!(:name),
      amount: sum(entries),
      months:
        entries
        |> Enum.group_by(& &1.month)
        |> Map.new(fn {month, entries} -> {month, sum(entries)} end),
      count: length(entries),
      suggestion: suggestion,
      source: source,
      reason: reason,
      status: status,
      category: if(rule, do: rule.category, else: if(status == :automatic, do: suggestion))
    }
  end

  defp suggest(side, entries, industry, learned) do
    name = hd(entries).name

    with nil <- certain(entries),
         nil <- if(side == :expenses, do: line_suggestion(entries)),
         nil <- name_suggestion(industry, side, name),
         nil <- learned_suggestion(entries, learned) do
      if side == :income,
        do: {IndustryTemplate.default_income(industry), :default, nil},
        else: {nil, nil, nil}
    end
  end

  defp certain(entries) do
    case entries |> Enum.map(& &1.certain) |> Enum.uniq() do
      [category] when category != nil -> {category, :certain, nil}
      _ -> nil
    end
  end

  defp line_suggestion(entries) do
    matches =
      for entry <- entries,
          {line, amount} <- entry.lines,
          category = IndustryTemplate.line_category(line),
          category != nil,
          do: {category, line, amount}

    if matches != [] do
      {category, lines} =
        matches
        |> Enum.group_by(&elem(&1, 0))
        |> Enum.max_by(fn {_category, lines} ->
          lines |> Enum.map(&elem(&1, 2)) |> Enum.reduce(&Decimal.add/2)
        end)

      examples = lines |> Enum.map(&elem(&1, 1)) |> Enum.uniq() |> Enum.take(1)
      {category, :invoice_lines, examples}
    end
  end

  defp name_suggestion(industry, side, name) do
    case IndustryTemplate.name_category(industry, side, name) do
      nil -> nil
      category -> {category, :name, nil}
    end
  end

  defp learned_suggestion(entries, learned) do
    votes =
      entries
      |> Enum.flat_map(&words/1)
      |> Enum.uniq()
      |> Enum.flat_map(&Map.get(learned, &1, []))

    if votes != [] do
      {category, _count} = votes |> Enum.frequencies() |> Enum.max_by(&elem(&1, 1))
      {category, :learned, nil}
    end
  end

  # Invoice line words of confirmed groups vote for the confirmed category.
  defp learned_words(entries, rules) do
    entries
    |> Enum.flat_map(fn entry ->
      case Map.get(rules, {entry.side, key(entry.name)}) do
        nil -> []
        rule -> entry |> words() |> Enum.map(&{&1, rule.category})
      end
    end)
    |> Enum.uniq()
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
  end

  defp key(name), do: name |> IndustryTemplate.normalize() |> String.trim()

  defp words(entry) do
    entry.lines
    |> Enum.flat_map(fn {line, _amount} ->
      line |> IndustryTemplate.normalize() |> String.split()
    end)
    |> Enum.filter(&(String.length(&1) >= 4 and not String.match?(&1, ~r/\d/)))
  end

  @doc "Counts confirmations whose suggestion the owner accepted unchanged, per source and overall."
  @spec accuracy([map()]) :: %{
          accepted: non_neg_integer(),
          total: non_neg_integer(),
          by_source: map()
        }
  def accuracy(rules) do
    measured = Enum.filter(rules, &(&1.suggestion_source != nil))

    %{
      accepted: Enum.count(measured, &(&1.category == &1.suggested_category)),
      total: length(measured),
      by_source:
        measured
        |> Enum.group_by(& &1.suggestion_source)
        |> Map.new(fn {source, rules} ->
          {source, {Enum.count(rules, &(&1.category == &1.suggested_category)), length(rules)}}
        end)
    }
  end

  defp automatic?(accuracy, source) do
    case Map.get(accuracy.by_source, source) do
      {accepted, total} when total >= @auto_samples -> accepted / total >= @auto_accuracy
      _ -> false
    end
  end

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
