defmodule FirmowidWeb.Analysis.Components.AskAssistant do
  @moduledoc """
  Starts an assistant conversation about the analysis view on screen: the assistant panel
  opens with the view's period, month or project and the figures it shows as context. The
  button takes the place of the assistant's floating launcher, which a page with a
  `data-assistant-entry` element hides.

  The view also suggests questions as tiles: each leads with a figure of the view (what
  stayed, the largest cost, the weakest month) and asks about it, so the conversation starts
  with that question already sent. Views with too few figures get general questions.
  """
  use FirmowidWeb, :html

  import FirmowidWeb.Analysis.Utilities.Amounts, only: [whole_money: 1]

  alias Firmowid.Analysis.ProjectProfitability
  alias Firmowid.Cldr.Number
  alias FirmowidWeb.Analysis.Utilities.Periods
  alias Phoenix.LiveView.Rendered

  @tiles 4
  @notable_change Decimal.new("0.1")
  @material_share Decimal.new("0.02")

  @typedoc """
  A suggested question: an optional `figure` from the view with its `tone` and `caption`,
  the `question` on the tile and the `prompt` sent, which names the figure.
  """
  @type question :: %{
          key: String.t(),
          figure: String.t() | nil,
          tone: :neutral | :kept | :loss,
          caption: String.t() | nil,
          question: String.t(),
          prompt: String.t()
        }

  attr :id, :string, required: true

  attr :context, :map,
    required: true,
    doc: "`view` (summary or trends), `from`, `to`, `month`, `project_id` and `title`"

  @doc "Renders the button asking the assistant about this view."
  @spec button(map()) :: Rendered.t()
  def button(assigns) do
    ~H"""
    <FirmowidUI.Components.Button.button
      id={@id}
      type="button"
      variant="special"
      size="big"
      data-assistant-entry
      phx-click={JS.push("ask_analysis", target: "#firmowid-assistant", value: @context)}
    >
      <Lucideicons.messages_square aria-hidden="true" />
      {gettext("Ask the assistant")}
    </FirmowidUI.Components.Button.button>
    """
  end

  attr :id, :string, required: true
  attr :context, :map, required: true, doc: "as for `button/1`"
  attr :questions, :list, required: true, doc: "`t:question/0` maps"

  @doc "Renders the suggested questions as tiles, each asking the assistant right away."
  @spec tiles(map()) :: Rendered.t()
  def tiles(assigns) do
    ~H"""
    <ul
      :if={@questions != []}
      id={@id}
      aria-label={gettext("Questions for the assistant")}
      class="grid grid-cols-[repeat(auto-fit,minmax(min(100%,14rem),1fr))] gap-3"
    >
      <li :for={question <- @questions} class="flex">
        <FirmowidUI.Components.Button.button
          id={"#{@id}-#{question.key}"}
          type="button"
          variant="unstyled"
          phx-click={
            JS.push("ask_analysis",
              target: "#firmowid-assistant",
              value: Map.put(@context, :question, question.prompt)
            )
          }
          class="group flex w-full cursor-pointer flex-col items-stretch justify-between gap-4 rounded-lg border border-grey-200 bg-white p-4 text-start font-normal whitespace-normal select-none active:bg-grey-100 motion-safe:transition-colors motion-safe:duration-150 pointer-fine:hover:border-grey-400 phx-click-loading:opacity-75"
        >
          <span :if={question.figure} class="flex flex-col gap-0.5">
            <span class={["text-2xl/tight font-semibold tabular-nums", tone_styles(question.tone)]}>
              {question.figure}
            </span>
            <span class="text-sm text-grey-700">{question.caption}</span>
          </span>
          <span class="flex items-start gap-2 text-sm font-medium text-grey-900">
            <Lucideicons.messages_square
              class="mt-0.5 size-4 shrink-0 text-grey-600 pointer-fine:group-hover:text-grey-900"
              aria-hidden="true"
            />
            <span class="min-w-0 flex-1 underline-offset-[.2em] pointer-fine:group-hover:underline">
              {question.question}
            </span>
            <Lucideicons.arrow_right
              class="mt-0.5 size-4 shrink-0 text-grey-500 pointer-fine:group-hover:text-grey-900"
              aria-hidden="true"
            />
          </span>
        </FirmowidUI.Components.Button.button>
      </li>
    </ul>
    """
  end

  @doc """
  Questions about the summary's figures, as many as there are of: what one złoty more of
  every 100 zł is worth, the largest cost, the cost that grew most, the unpaid sales, the
  months at a loss and the largest payee.

  `costs` are the summary's cost categories, largest first, with `key`, `label`,
  `amount`, `per_100`, `monthly` and `average`, and their counterparty `groups`; `months`
  are the closed months shown, of `YearSummary.get/3`.
  """
  @spec summary(%{
          costs: [map()],
          kept: integer() | nil,
          spent: integer() | nil,
          income: Decimal.t(),
          unpaid_income: Decimal.t(),
          months: [map()]
        }) :: [question()]
  def summary(figures) do
    [
      kept_question(figures),
      largest_cost_question(figures.costs),
      growing_cost_question(figures.costs, length(figures.months)),
      unpaid_question(figures.unpaid_income),
      loss_months_question(figures.months),
      payee_question(figures.costs)
    ]
    |> Enum.reject(&is_nil/1)
    |> fill([
      general("largest_costs", gettext("What takes the most of my money?")),
      general("cut_costs", gettext("Where could I spend less?")),
      general("unusual_costs", gettext("Which costs differ from the usual?"))
    ])
  end

  @doc """
  Questions about the trends' months: the weakest and the best, the latest one and the
  projects. `months` are the period's months of `YearSummary.get/3`; only closed ones
  count. `projects` are the `ProjectProfitability` projects of those months, empty
  without projects or for one project's trends.
  """
  @spec trends([map()], [ProjectProfitability.project()]) :: [question()]
  def trends(months, projects) do
    # Months without any money, before the company started, are not the weakest.
    closed =
      Enum.filter(months, fn month ->
        month.closed? and
          not (Decimal.eq?(month.totals.total_income, 0) and
                 Decimal.eq?(month.totals.total_expenses, 0))
      end)

    {weakest, best} =
      if length(closed) >= 2,
        do: Enum.min_max_by(closed, & &1.totals.net_profit, Decimal),
        else: {nil, nil}

    questions =
      Enum.reject(
        [
          weakest && month_question("weakest", weakest),
          best && month_question("best", best),
          latest_question(closed, [weakest, best])
        ],
        &is_nil/1
      )

    general = [
      general("direction", gettext("Is my result getting better month by month?")),
      general("weakest_month", gettext("Which month was the weakest and why?")),
      general("recent_change", gettext("What changed in the last three months?"))
    ]

    # The projects keep the last tile, after the months and any general questions.
    case project_question(projects) do
      nil -> fill(questions, general)
      project -> Enum.take(questions ++ general, @tiles - 1) ++ [project]
    end
  end

  # What stays of every 100 zł is abstract; one złoty more of every 100 is a sum of money.
  defp kept_question(%{income: income} = figures) do
    if Decimal.positive?(income) and (figures.kept || figures.spent) do
      figure = income |> Decimal.div(100) |> whole_money()

      {question, prompt} =
        if figures.kept,
          do:
            {gettext("How can I keep more?"),
             gettext(
               "Of every 100 zł of income, %{kept} stays in the company. Each złoty more of every 100 would be %{amount} in this period. How can I keep more?",
               kept: whole_money(figures.kept),
               amount: figure
             )},
          else:
            {gettext("How do I get back above zero?"),
             gettext(
               "On every 100 zł of income I lose %{lost}. Each złoty of every 100 is %{amount} in this period. What would get me back above zero?",
               lost: whole_money(figures.spent - 100),
               amount: figure
             )}

      %{
        key: "kept",
        figure: "+" <> figure,
        tone: :kept,
        caption: gettext("what 1 zł more of every 100 zł of income is worth"),
        question: question,
        prompt: prompt
      }
    end
  end

  defp largest_cost_question(costs) do
    case Enum.find(costs, &(&1.key && &1.per_100)) do
      nil ->
        nil

      category ->
        figure = whole_money(category.per_100)

        %{
          key: "largest_cost",
          figure: gettext("%{amount} of 100", amount: figure),
          tone: :neutral,
          caption: gettext("%{category}, the largest cost", category: category.label),
          question: gettext("Where can I save on it?"),
          prompt:
            gettext(
              "My largest cost is %{category}: %{amount} of every 100 zł of income. Where can I save on it?",
              category: category.label,
              amount: figure
            )
        }
    end
  end

  # One month compares with its usual amount; a longer period compares its last three
  # months with the months before. Small changes, or ones small against a month's costs, are
  # noise.
  defp growing_cost_question(costs, count) do
    total = Enum.reduce(costs, Decimal.new(0), &Decimal.add(&1.amount, &2))

    costs
    |> Enum.filter(& &1.key)
    |> Enum.map(&{&1, monthly_change(&1, count)})
    |> Enum.filter(fn
      {_category, {now, before}} ->
        Decimal.positive?(before) and
          Decimal.compare(Decimal.sub(Decimal.div(now, before), 1), @notable_change) != :lt and
          Decimal.compare(Decimal.sub(now, before), material(total, count)) != :lt

      {_category, nil} ->
        false
    end)
    |> Enum.max_by(fn {_category, {now, before}} -> Decimal.sub(now, before) end, Decimal, fn ->
      nil
    end)
    |> case do
      nil -> nil
      {category, {now, before}} -> growing_cost(category, now, before, count)
    end
  end

  defp material(total, count), do: total |> Decimal.div(count) |> Decimal.mult(@material_share)

  defp monthly_change(%{average: %Decimal{} = average, amount: amount}, 1), do: {amount, average}

  defp monthly_change(%{monthly: monthly}, count) when count >= 6 do
    {before, recent} = Enum.split(monthly, -3)
    {average(recent), average(before)}
  end

  defp monthly_change(_category, _count), do: nil

  defp growing_cost(category, now, before, count) do
    change = now |> Decimal.div(before) |> Decimal.sub(1) |> Number.to_string!(format: "+#,##0%")

    {caption, prompt} =
      if count == 1,
        do:
          {gettext("%{category} against a usual month", category: category.label),
           gettext("%{category} cost %{amount} this month, usually %{usual}. Why is it higher?",
             category: category.label,
             amount: whole_money(now),
             usual: whole_money(before)
           )},
        else:
          {gettext("%{category} in the last 3 months", category: category.label),
           gettext(
             "%{category} costs %{amount} a month in the last 3 months, %{usual} before. Why is it growing?",
             category: category.label,
             amount: whole_money(now),
             usual: whole_money(before)
           )}

    %{
      key: "growing_cost",
      figure: change,
      tone: :loss,
      caption: caption,
      question: gettext("Why is it growing?"),
      prompt: prompt
    }
  end

  defp unpaid_question(unpaid) do
    if Decimal.positive?(unpaid) do
      figure = whole_money(unpaid)

      %{
        key: "unpaid",
        figure: figure,
        tone: :neutral,
        caption: gettext("in unpaid sales invoices"),
        question: gettext("Who hasn't paid me yet?"),
        prompt:
          gettext(
            "Unpaid sales invoices add up to %{amount}. Who hasn't paid me yet, and since when?",
            amount: figure
          )
      }
    end
  end

  defp loss_months_question([_, _ | _] = months) do
    losses = Enum.count(months, &Decimal.negative?(&1.totals.net_profit))

    if losses > 0 do
      figure = gettext("%{losses} of %{count}", losses: losses, count: length(months))

      %{
        key: "loss_months",
        figure: figure,
        tone: :loss,
        # Polish names the months after "of %{count}", so one phrase fits every count.
        caption: gettext("months ended at a loss"),
        question: gettext("What do they have in common?"),
        prompt:
          gettext(
            "%{losses} of %{count} months in this period ended at a loss. What do they have in common?",
            losses: losses,
            count: length(months)
          )
      }
    end
  end

  defp loss_months_question(_months), do: nil

  # Payroll rows name no one, so the largest payee is a counterparty, summed over the
  # categories and statuses its payments fall into.
  defp payee_question(costs) do
    costs
    |> Enum.flat_map(& &1.groups)
    |> Enum.filter(&(Map.get(&1, :people) == nil))
    |> Enum.group_by(& &1.key)
    |> Enum.map(fn {_key, groups} ->
      %{
        name: Enum.max_by(groups, & &1.amount, Decimal).name,
        amount: Enum.reduce(groups, Decimal.new(0), &Decimal.add(&1.amount, &2))
      }
    end)
    |> Enum.max_by(& &1.amount, Decimal, fn -> nil end)
    |> case do
      nil ->
        nil

      group ->
        figure = whole_money(group.amount)

        %{
          key: "payee",
          figure: figure,
          tone: :neutral,
          caption: gettext("%{name}, the largest payee", name: group.name),
          question: gettext("Can I pay less there?"),
          prompt:
            gettext(
              "I paid %{name} %{amount} in this period, the most of all counterparties. Can I pay less there?",
              name: group.name,
              amount: figure
            )
        }
    end
  end

  defp month_question(kind, month) do
    name = Periods.month_name(month.month, "LLLL y")
    result = month.totals.net_profit
    figure = whole_money(result)

    {caption, question, prompt} =
      case kind do
        "weakest" ->
          {gettext("%{month}, the weakest month", month: name), gettext("Why was it the weakest?"),
           gettext("The weakest month was %{month}, with a result of %{amount}. Why?",
             month: name,
             amount: figure
           )}

        "best" ->
          {gettext("%{month}, the best month", month: name), gettext("What worked then?"),
           gettext(
             "The best month was %{month}, with a result of %{amount}. What worked then, and can I repeat it?",
             month: name,
             amount: figure
           )}
      end

    %{
      key: kind,
      figure: figure,
      tone: if(Decimal.negative?(result), do: :loss, else: :neutral),
      caption: caption,
      question: question,
      prompt: prompt
    }
  end

  # The latest closed month against the months before it, unless it is already the weakest or the best.
  defp latest_question([_, _, _ | _] = closed, shown) do
    latest = List.last(closed)

    if latest not in shown do
      name = Periods.month_name(latest.month, "LLLL y")
      figure = whole_money(latest.totals.net_profit)

      usual =
        closed |> Enum.drop(-1) |> Enum.map(& &1.totals.net_profit) |> average() |> whole_money()

      %{
        key: "latest",
        figure: figure,
        tone: if(Decimal.negative?(latest.totals.net_profit), do: :loss, else: :neutral),
        caption: gettext("%{month}, usually %{amount}", month: name, amount: usual),
        question: gettext("What changed lately?"),
        prompt:
          gettext(
            "The latest closed month, %{month}, ended with %{amount}; months before averaged %{usual}. What changed?",
            month: name,
            amount: figure,
            usual: usual
          )
      }
    end
  end

  defp latest_question(_closed, _shown), do: nil

  # A project at a loss is the hook; without one, the project that earns most. The result is
  # the project's own income and costs, before the company's shared costs.
  defp project_question([]), do: nil

  defp project_question(projects) do
    {weakest, best} = Enum.min_max_by(projects, & &1.direct_profit, Decimal)
    losing? = Decimal.negative?(weakest.direct_profit)
    project = if losing?, do: weakest, else: best
    figure = whole_money(project.direct_profit)

    details = [
      project: project.name,
      amount: figure,
      income: whole_money(project.income),
      costs: whole_money(project.direct_expenses)
    ]

    if losing? do
      %{
        key: "losing_project",
        figure: figure,
        tone: :loss,
        caption: gettext("%{project}, a project at a loss", project: project.name),
        question: gettext("Why is it losing money?"),
        prompt:
          gettext(
            "Project %{project} ended this period at %{amount}: %{income} of income against %{costs} of its own costs, before shared costs. Why is it losing money, and what can I do about it?",
            details
          )
      }
    else
      %{
        key: "best_project",
        figure: figure,
        tone: :kept,
        caption: gettext("%{project}, the project that earns most", project: project.name),
        question: gettext("What sets it apart?"),
        prompt:
          gettext(
            "Project %{project} earned %{amount} this period: %{income} of income against %{costs} of its own costs, before shared costs. What sets it apart from the other projects?",
            details
          )
      }
    end
  end

  defp general(key, question),
    do: %{key: key, figure: nil, tone: :neutral, caption: nil, question: question, prompt: question}

  # Figures first; general questions make up the rest of the row.
  defp fill(questions, general), do: Enum.take(questions ++ general, @tiles)

  defp average(values), do: values |> Enum.reduce(Decimal.new(0), &Decimal.add/2) |> Decimal.div(length(values))

  defp tone_styles(:kept), do: "text-teal-700"
  defp tone_styles(:loss), do: "text-brick-700"
  defp tone_styles(:neutral), do: "text-grey-900"
end
