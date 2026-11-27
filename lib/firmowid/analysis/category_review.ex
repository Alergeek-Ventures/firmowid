defmodule Firmowid.Analysis.CategoryReview do
  @moduledoc """
  Pure classification of analysis entries into industry template categories.

  The owner has the last word: an entry takes the category confirmed for its
  counterparty. Otherwise it is only suggested one, from a certain signal
  (salaries, ZUS and tax payments) or else the one the classifier chose from
  its description, until the owner confirms. Entries are grouped by
  counterparty and category, so a mixed supplier shows each kind of
  purchase; salaries paid through payroll form one group.
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
          nip: String.t() | nil,
          transfer_names: [String.t()],
          accounts: [String.t()],
          salary_person: Ash.UUID.t() | nil,
          certain: IndustryTemplate.category() | nil,
          classified: IndustryTemplate.category() | nil,
          probability: float() | nil,
          probabilities: %{String.t() => float()} | nil
        }

  @doc """
  Builds the review of `entries` with the owner's `rules` for `industry`.

  Amounts are positive. Each side lists template categories (plus any other
  confirmed ones) with their amounts, and the amount still waiting for review.
  Groups are sorted by amount, largest first; `months` holds their amount per
  month and `names` the names of its counterparty in any category, one per key. The salaries
  group has no `key`, `name` or `names`, but `people`, the ids of the users
  paid per month (a transfer whose user is gone counts as a person of its own). A group the
  classifier suggested has the `probability` of its
  least certain entry and, as `options`, the categories the classifier found
  comparable for that entry, its own first. Every group keeps its `entries`. `unclassified` lists the entries still waiting for the classifier:
  without a confirmed counterparty, a certain signal or a stored category;
  `classifier_suggested` the entries whose suggestion came from it.
  `rules` holds the owner's rules by side and group key, the latest of a key.
  The result echoes `industry`.
  """
  @spec build([entry()], [map()], IndustryTemplate.industry()) :: map()
  def build(entries, rules, industry) do
    shared = shared_keys(entries)
    rules = rules_by_key(rules, shared)
    resolved = resolve_by(entries, rules, shared)

    # All of a counterparty's names, also those in its other categories, so a rule covers each.
    names =
      resolved
      |> Enum.group_by(fn {entry, key, _resolution} -> {entry.side, key} end, &elem(&1, 0))
      |> Map.new(fn {side_key, entries} ->
        {side_key, entries |> Enum.uniq_by(&key(&1.name)) |> Enum.map(& &1.name)}
      end)

    groups =
      resolved
      |> Enum.group_by(&group_by/1)
      |> Enum.map(fn {{side, key, category, _status}, resolved} ->
        entries = Enum.map(resolved, &elem(&1, 0))
        group(side, key, entries, Map.get(names, {side, key}), {category, source(resolved)})
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
      rules: rules,
      industry: industry
    }
  end

  @doc """
  Lists at most `count` counterparties of the review whose category the owner
  should check first, as `{side, key}`: those the classifier suggested with
  several comparable `options` or without being almost sure, the larger amount
  of such suggestions first.
  """
  @spec to_check(map(), pos_integer()) :: [{IndustryTemplate.side(), String.t()}]
  def to_check(review, count) do
    review.groups
    |> Enum.filter(
      &(&1.source == :jev and
          (length(&1.options) > 1 or certainty(&1.probability) != :almost_sure))
    )
    |> Enum.group_by(&{&1.side, &1.key}, & &1.amount)
    |> Enum.sort_by(
      fn {_counterparty, amounts} -> Enum.reduce(amounts, &Decimal.add/2) end,
      {:desc, Decimal}
    )
    |> Enum.take(count)
    |> Enum.map(&elem(&1, 0))
  end

  @doc "Reads the classifier's probability of its choice as how sure it is."
  @spec certainty(float()) :: :almost_sure | :fairly_sure | :guessing
  def certainty(probability) when probability >= 0.85, do: :almost_sure
  def certainty(probability) when probability >= 0.6, do: :fairly_sure
  def certainty(_probability), do: :guessing

  @doc """
  Pairs each entry with its counterparty key and its category with where it
  comes from: `:confirmed` by the owner in `rules`, else a `:certain` signal,
  else the classifier (`:jev`), else `{nil, nil}`. Names on invoices with the
  same NIP are one counterparty: they share the first of their keys, and a
  rule confirmed for any of them. So do the names the bank gives it on
  transfers paired with those invoices, which its other transfers carry
  without a NIP, and the names of entries without a NIP paid to an account
  only its invoices show.
  """
  @spec resolve([entry()], [map()]) :: [{entry(), String.t(), resolution()}]
  def resolve(entries, rules) do
    shared = shared_keys(entries)
    resolve_by(entries, rules_by_key(rules, shared), shared)
  end

  defp resolve_by(entries, rules, shared) do
    Enum.map(entries, fn entry ->
      key = Map.get(shared, {entry.side, key(entry.name)}, key(entry.name))
      {entry, key, resolution(entry, Map.get(rules, {entry.side, key}))}
    end)
  end

  # Keys come from the confirmed name, so rules stored under an earlier key format still
  # apply; of rules with the same key the latest wins.
  defp rules_by_key(rules, shared) do
    rules
    |> Enum.sort_by(&{DateTime.to_unix(&1.updated_at, :microsecond), &1.id})
    |> Map.new(fn rule ->
      key = key(rule.counterparty_name)
      {{rule.side, Map.get(shared, {rule.side, key}, key)}, rule}
    end)
  end

  # Joins the keys of names written on invoices with the same NIP, transitively, under the
  # alphabetically first of them. Transfers carry no NIP and join by their name's key, which
  # also joins the NIP when a transfer paired with one of its invoices has that name, or when
  # an entry without a NIP pays an account only that NIP's invoices show. A linked name or
  # account claimed by another NIP, such as a payment operator's, joins none of them.
  defp shared_keys(entries) do
    {with_nip, without_nip} = Enum.split_with(entries, &nip(&1.nip))

    owners =
      with_nip
      |> Enum.flat_map(fn entry ->
        for account <- entry.accounts, do: {{entry.side, account}, nip(entry.nip)}
      end)
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
      |> Map.new(fn {side_account, nips} -> {side_account, Enum.uniq(nips)} end)

    invoice_names =
      Enum.flat_map(with_nip, fn entry ->
        nip = nip(entry.nip)

        [{{entry.side, nip}, key(entry.name), :written}] ++
          for(name <- entry.transfer_names, do: {{entry.side, nip}, key(name), :linked})
      end)

    # A salary keeps its own name, so a supplier's rule never takes it out of the salaries group.
    account_names =
      for entry <- without_nip,
          entry.salary_person == nil,
          account <- entry.accounts,
          [nip] <- [Map.get(owners, {entry.side, account}, [])],
          do: {{entry.side, nip}, key(entry.name), :linked}

    names = invoice_names ++ account_names

    nips =
      Enum.reduce(names, %{}, fn {{side, nip}, key, _origin}, nips ->
        Map.update(nips, {side, key}, MapSet.new([nip]), &MapSet.put(&1, nip))
      end)

    names
    |> Enum.filter(fn {{side, _nip}, key, origin} ->
      origin == :written or MapSet.size(Map.fetch!(nips, {side, key})) == 1
    end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.reduce(%{}, fn {{side, _nip}, keys}, shared ->
      joined =
        keys |> Enum.map(&Map.get(shared, {side, &1}, &1)) |> Enum.concat(keys) |> Enum.uniq()

      first = Enum.min(joined)

      shared
      |> Map.new(fn {{other_side, key}, to} ->
        {{other_side, key}, if(other_side == side and to in joined, do: first, else: to)}
      end)
      |> Map.merge(Map.new(keys, &{{side, &1}, first}))
    end)
  end

  # Invoices write a NIP with or without separators and the Polish prefix.
  defp nip(nil), do: nil

  defp nip(nip) do
    nip =
      nip
      |> String.upcase()
      |> String.replace(~r/[^A-Z0-9]/, "")
      |> String.replace_prefix("PL", "")

    if byte_size(nip) >= 8, do: nip
  end

  @doc """
  Narrows the review's groups to `months`: `amount` becomes the sum over those
  months and `average` the group's mean monthly amount over `compared` months
  (nil without any). Groups absent from the period keep a zero amount, so
  categories can still compare against their usual amount. The salaries
  group's `people` becomes the number of people paid in those months.
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

      people =
        if group.people,
          do:
            months
            |> Enum.map(&Map.get(group.people, &1, MapSet.new()))
            |> Enum.reduce(MapSet.new(), &MapSet.union/2)
            |> MapSet.size()

      Map.put(%{group | amount: amount, people: people}, :average, average)
    end)
  end

  # Payroll salaries are one group, also of people the owner confirmed: each person's amount is
  # nobody's business in the overview.
  defp group_by({%{salary_person: person} = entry, _key, {:payroll, _source}}) when person != nil,
    do: {entry.side, nil, :payroll, :salaries}

  defp group_by({entry, key, {category, source}}), do: {entry.side, key, category, source == :confirmed}

  # The strongest source of a group's suggestion; owner rules cover a whole counterparty.
  defp source(resolved) do
    sources = Enum.map(resolved, fn {_entry, _key, {_category, source}} -> source end)
    Enum.find([:confirmed, :certain, :jev], &(&1 in sources))
  end

  defp group(side, key, entries, names, {category, source}) do
    status = if source == :confirmed, do: :confirmed, else: :pending

    largest = Enum.max_by(entries, & &1.amount, Decimal)
    classifier = classifier(entries, side, source)

    %{
      side: side,
      key: key,
      name: if(key, do: largest.name),
      names: if(key, do: names),
      people:
        if(key == nil,
          do:
            entries
            |> Enum.group_by(& &1.month, & &1.salary_person)
            |> Map.new(fn {month, users} -> {month, MapSet.new(users)} end)
        ),
      amount: sum(entries),
      months:
        entries
        |> Enum.group_by(& &1.month)
        |> Map.new(fn {month, entries} -> {month, sum(entries)} end),
      count: length(entries),
      entries: entries,
      suggestion: if(source != :confirmed, do: category),
      source: if(source != :confirmed, do: source),
      probability: classifier.probability,
      options: classifier.options,
      reason: reason(entries),
      status: status,
      category: if(status == :confirmed, do: category)
    }
  end

  # Each entry of a group the classifier suggested has the probabilities it stored with its choice.
  defp classifier(entries, side, :jev),
    do: %{probability: entries |> Enum.map(& &1.probability) |> Enum.min(), options: options(entries, side)}

  defp classifier(_entries, _side, _source), do: %{probability: nil, options: nil}

  # The categories at least half as likely as the likeliest one for the entry the classifier was
  # least sure of, likeliest first; the classifier names them as strings.
  defp options(entries, side) do
    probabilities = Enum.min_by(entries, & &1.probability).probabilities
    top = probabilities |> Map.values() |> Enum.max()
    categories = Map.new(IndustryTemplate.all_categories(side), &{Atom.to_string(&1), &1})

    for {name, probability} <- Enum.sort_by(probabilities, &elem(&1, 1), :desc),
        probability >= top / 2,
        Map.has_key?(categories, name),
        do: Map.fetch!(categories, name)
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
  def key(name), do: name |> words() |> distinctive_words() |> Enum.join(" ")

  @doc """
  Splits a name into lowercase words without Polish letters or punctuation,
  since bank transfers often drop Polish letters ("SPOLKA Z OGRANICZONA").
  """
  @spec words(String.t()) :: [String.t()]
  def words(name) do
    name
    |> String.downcase()
    # "ł" has no decomposition to drop.
    |> String.replace("ł", "l")
    |> :unicode.characters_to_nfd_binary()
    |> String.replace(~r/\p{Mn}/u, "")
    |> String.split(~r/[^\p{L}\p{N}]+/u, trim: true)
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
