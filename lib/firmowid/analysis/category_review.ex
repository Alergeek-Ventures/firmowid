defmodule Firmowid.Analysis.CategoryReview do
  @moduledoc """
  Pure classification of analysis entries into industry template categories.

  The owner has the last word: an entry takes the category confirmed for its
  counterparty. Otherwise it is only suggested one, from a certain signal
  (salaries, ZUS and tax payments) or else the one the classifier chose from
  its description, until the owner confirms. Entries are grouped by
  counterparty and that outcome, so a mixed supplier shows each kind of
  purchase.
  """

  alias Firmowid.Analysis.IndustryTemplate

  @type source :: :certain | :jev
  @type resolution :: {IndustryTemplate.category(), :confirmed | source()} | {nil, nil}
  @type entry :: %{
          side: IndustryTemplate.side(),
          month: Date.t(),
          name: String.t(),
          amount: Decimal.t(),
          lines: [String.t()],
          certain: IndustryTemplate.category() | nil,
          classified: IndustryTemplate.category() | nil,
          probability: float() | nil
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
    resolved = resolve(entries, rules)

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
  Pairs each entry with its counterparty key and its category with where it
  comes from: `:confirmed` by the owner in `rules`, else a `:certain` signal,
  else the classifier (`:jev`), else `{nil, nil}`.
  """
  @spec resolve([entry()], [map()]) :: [{entry(), String.t(), resolution()}]
  def resolve(entries, rules) do
    rules = rules_by_key(rules)

    Enum.map(entries, fn entry ->
      key = key(entry.name)
      {entry, key, resolution(entry, Map.get(rules, {entry.side, key}))}
    end)
  end

  @doc """
  Returns the owner's `rules` by side and counterparty key. Keys come from the
  confirmed name, so rules stored under an earlier key format still apply; of
  rules with the same key the latest wins.
  """
  @spec rules_by_key([map()]) :: %{{IndustryTemplate.side(), String.t()} => map()}
  def rules_by_key(rules) do
    rules
    |> Enum.sort_by(&{DateTime.to_unix(&1.updated_at, :microsecond), &1.id})
    |> Map.new(&{{&1.side, key(&1.counterparty_name)}, &1})
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
  Narrows the review's groups to `months`: `amount` becomes the sum over those
  months and `average` the group's mean monthly amount over `compared` months
  (nil without any). Groups absent from the period keep a zero amount, so
  categories can still compare against their usual amount.
  """
  @spec period(map(), [Date.t()], [Date.t()]) :: [map()]
  def period(review, months, compared) do
    Enum.map(review.groups, fn group ->
      average =
        if compared == [],
          do: nil,
          else:
            compared
            |> Enum.map(&Map.get(group.months, &1, Decimal.new(0)))
            |> Enum.reduce(&Decimal.add/2)
            |> Decimal.div(length(compared))

      amount =
        months
        |> Enum.map(&Map.get(group.months, &1, Decimal.new(0)))
        |> Enum.reduce(Decimal.new(0), &Decimal.add/2)

      Map.put(%{group | amount: amount}, :average, average)
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
      reason: reason(entries),
      status: status,
      category: if(status == :confirmed, do: category)
    }
  end

  # The largest described entry explains the group; transfers may come without a title.
  defp reason(entries) do
    case Enum.filter(entries, &(&1.lines != [])) do
      [] ->
        []

      described ->
        described |> Enum.max_by(& &1.amount, Decimal) |> Map.fetch!(:lines) |> Enum.take(1)
    end
  end

  # The owner has the last word; a certain signal, else the classifier, only suggests.
  defp resolution(_entry, %{category: category}), do: {category, :confirmed}
  defp resolution(%{certain: category}, nil) when category != nil, do: {category, :certain}
  defp resolution(%{classified: category}, nil) when category != nil, do: {category, :jev}
  defp resolution(_entry, nil), do: {nil, nil}

  @doc """
  Returns the key of a counterparty's name, the same for the ways invoices and
  bank transfers write it: lowercase words without Polish letters, punctuation,
  reference numbers or a trailing legal form.
  """
  @spec key(String.t()) :: String.t()
  def key(name) do
    name
    |> String.downcase()
    # "ł" has no decomposition to drop.
    |> String.replace("ł", "l")
    |> :unicode.characters_to_nfd_binary()
    |> String.replace(~r/\p{Mn}/u, "")
    |> String.split(~r/[^\p{L}\p{N}]+/u, trim: true)
    |> distinctive_words()
    |> Enum.join(" ")
  end

  # Card payments carry reference numbers, five or more digits with at most a letter before
  # them ("AIRLINE 1234567890 WARSAW", "P123456789"). The name drops them and its legal form,
  # unless nothing else tells it apart ("1234567890 Inc").
  defp distinctive_words(words) do
    [Enum.reject(words, &(&1 =~ ~r/^\p{L}?\d{5,}$/u)), words]
    |> Enum.map(&strip_legal_form/1)
    |> Enum.find(words, &(&1 != []))
  end

  # Without punctuation and Polish letters; several forms may follow each other.
  @legal_forms [
    ~w(spolka z ograniczona odpowiedzialnoscia),
    ~w(spolka komandytowo akcyjna),
    ~w(spolka komandytowa),
    ~w(spolka jawna),
    ~w(spolka akcyjna),
    ~w(spolka z o o),
    ~w(sp z o o),
    ~w(sp z oo),
    ~w(sp zoo),
    ~w(sp k),
    ~w(sp j),
    ~w(s a),
    ~w(pte ltd),
    ~w(inc),
    ~w(ltd),
    ~w(limited),
    ~w(llc),
    ~w(pbc),
    ~w(gmbh),
    ~w(ab),
    ~w(bv),
    ~w(b v),
    ~w(srl),
    ~w(s r l),
    ~w(s r o),
    ~w(sarl)
  ]

  # Bank transfers cut long names short, so the start of a long legal form counts as one.
  defp strip_legal_form([]), do: []

  defp strip_legal_form(words) do
    stripped =
      Enum.find_value(@legal_forms, words, fn form ->
        Enum.find_value(min(length(form), length(words))..1//-1, fn size ->
          {name, tail} = Enum.split(words, -size)

          if tail == form or (size >= 2 and length(form) >= 3 and List.starts_with?(form, tail)),
            do: name
        end)
      end)

    if stripped == words, do: words, else: strip_legal_form(stripped)
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
