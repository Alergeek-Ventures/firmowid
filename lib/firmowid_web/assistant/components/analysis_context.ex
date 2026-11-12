defmodule FirmowidWeb.Assistant.Components.AnalysisContext do
  @moduledoc """
  The analysis view a conversation started from, above its transcript: the view, period and
  project, the result, and a small picture of what the view showed (where every 100 zł went,
  the months' results or the best projects), with a link back to that view.
  """
  use FirmowidWeb, :html

  import FirmowidWeb.Analysis.Utilities.Amounts, only: [whole_money: 1]

  alias Firmowid.Analysis.IndustryTemplate
  alias FirmowidWeb.Analysis.Components.PeriodDetails
  alias FirmowidWeb.Analysis.Utilities.Navigation
  alias FirmowidWeb.Analysis.Utilities.Periods

  @strip_categories 3

  attr :analysis, :map, required: true, doc: "the conversation's stored analysis subject"
  attr :class, :any, default: nil

  @doc "Renders the analysis view the conversation is about."
  @spec card(map()) :: Phoenix.LiveView.Rendered.t()
  def card(assigns) do
    analysis = assigns.analysis
    from = Date.from_iso8601!(analysis["from"])
    to = Date.from_iso8601!(analysis["to"])
    month = analysis["month"] && Date.from_iso8601!(analysis["month"])
    project = analysis["project"]

    assigns =
      assign(assigns,
        view: analysis["view"],
        period: period_label(analysis["view"], {from, to}, month, analysis["months"]),
        project: project && project["name"],
        result: Decimal.new(analysis["totals"]["result"]),
        path: path(analysis["view"], {from, to}, month, project),
        picture: picture_of(analysis)
      )

    ~H"""
    <section
      id="assistant-analysis-context"
      class={["flex flex-col gap-3 py-3", @class]}
      aria-label={gettext("Analysis the conversation is about")}
    >
      <div class="flex items-center justify-between gap-3 text-xs text-grey-700">
        <span class="flex items-center gap-1.5">
          <Lucideicons.chart_column class="size-3.5" aria-hidden="true" />
          {view_label(@view)}
        </span>
        <FirmowidUI.Components.Link.link
          kind="unstyled"
          navigate={@path}
          class="underline decoration-transparent underline-offset-[.2em] hover:decoration-current active:text-grey-900"
        >
          {gettext("Open the view")}
        </FirmowidUI.Components.Link.link>
      </div>
      <div class="flex flex-wrap items-baseline justify-between gap-x-4 gap-y-0.5">
        <p class="text-base/tight font-medium text-grey-900">
          {@period}<span :if={@project} class="text-grey-700"> · {@project}</span>
        </p>
        <p class={["text-sm font-medium tabular-nums", result_styles(@result)]}>
          {gettext("Result %{amount}", amount: whole_money(@result))}
        </p>
      </div>
      <.picture picture={@picture} />
    </section>
    """
  end

  attr :picture, :any, required: true

  defp picture(%{picture: nil} = assigns), do: ~H""

  # Where every 100 zł of income went, the way the summary's strip shows it.
  defp picture(%{picture: {:strip, strip}} = assigns) do
    assigns = assign(assigns, strip: strip)

    ~H"""
    <div class="flex flex-col gap-1.5">
      <div class="flex h-2 gap-0.5 overflow-hidden rounded-xs" aria-hidden="true">
        <span
          :for={segment <- @strip.segments}
          class={["min-w-1", tone_styles(segment.tone)]}
          style={"flex: #{segment.share} 1 0"}
        />
      </div>
      <p class="text-sm text-grey-700">
        {if @strip.kept,
          do:
            gettext("Of every %{hundred} of income, %{amount} stayed.",
              hundred: whole_money(100),
              amount: whole_money(@strip.kept)
            ),
          else: gettext("Costs took all of the income.")}
        <span :if={@strip.largest}>
          {gettext("The most went to %{category}.", category: @strip.largest)}
        </span>
      </p>
    </div>
    """
  end

  # Each closed month's result on one zero line, the way the trends chart shows it.
  defp picture(%{picture: {:months, months}} = assigns) do
    assigns = assign(assigns, months: months)

    ~H"""
    <ol class="grid h-12 grid-flow-col gap-0.5" aria-hidden="true">
      <li :for={month <- @months} class="flex flex-col" title={month.name}>
        <span class="flex flex-1 items-end">
          <span
            :if={month.side == :profit}
            class="w-full rounded-t-xs bg-teal-600"
            style={"height: #{month.length}%"}
          />
        </span>
        <span class="h-px bg-grey-300" />
        <span class="flex flex-1 items-start">
          <span
            :if={month.side == :loss}
            class="w-full rounded-b-xs bg-brick-700"
            style={"height: #{month.length}%"}
          />
        </span>
      </li>
    </ol>
    """
  end

  defp picture(%{picture: {:projects, projects}} = assigns) do
    assigns = assign(assigns, projects: projects)

    ~H"""
    <ul class="flex flex-col text-sm">
      <li :for={project <- @projects} class="flex items-baseline justify-between gap-3 py-0.5">
        <span class="min-w-0 truncate text-grey-800">{project.name}</span>
        <span class={["shrink-0 tabular-nums", result_styles(project.result)]}>
          {whole_money(project.result)}
        </span>
      </li>
    </ul>
    """
  end

  defp picture_of(%{"view" => "summary", "categories" => categories, "totals" => totals}) do
    income = Decimal.new(totals["income"])
    result = Decimal.new(totals["result"])

    costs =
      for %{"side" => "expenses"} = category <- categories,
          do: %{key: category["category"], amount: Decimal.new(category["amount"])}

    if Decimal.positive?(income) and costs != [] do
      {top, rest} = Enum.split(costs, @strip_categories)

      segments =
        Enum.with_index(top, &%{share: Decimal.to_float(&1.amount), tone: &2}) ++
          if(rest == [],
            do: [],
            else: [
              %{
                share: rest |> Enum.map(& &1.amount) |> sum() |> Decimal.to_float(),
                tone: :rest
              }
            ]
          ) ++
          if(Decimal.positive?(result),
            do: [%{share: Decimal.to_float(result), tone: :kept}],
            else: []
          )

      {:strip,
       %{
         segments: segments,
         kept:
           if(Decimal.positive?(result),
             do:
               result
               |> Decimal.mult(100)
               |> Decimal.div(income)
               |> Decimal.round(0)
               |> Decimal.to_integer()
           ),
         largest: category_label(hd(costs).key)
       }}
    end
  end

  defp picture_of(%{"view" => "trends", "months" => months}) do
    results = for %{"closed" => true, "result" => result} <- months, do: Decimal.new(result)
    largest = results |> Enum.map(&Decimal.abs/1) |> Enum.reduce(Decimal.new(0), &Decimal.max/2)

    if Decimal.positive?(largest) do
      {:months,
       Enum.map(months, fn month ->
         date = Date.from_iso8601!(month["month"])
         result = if month["closed"], do: Decimal.new(month["result"]), else: Decimal.new(0)

         %{
           name: Periods.month_name(date, "LLLL y"),
           side: if(Decimal.negative?(result), do: :loss, else: :profit),
           length:
             result
             |> Decimal.abs()
             |> Decimal.div(largest)
             |> Decimal.mult(100)
             |> Decimal.round(0)
             |> Decimal.to_integer()
         }
       end)}
    end
  end

  defp picture_of(%{"view" => "projects", "projects" => [_ | _] = projects}) do
    {:projects,
     projects
     |> Enum.take(3)
     |> Enum.map(&%{name: &1["name"], result: Decimal.new(&1["direct_profit"])})}
  end

  defp picture_of(_analysis), do: nil

  # The summary names the closed months it covers, as its title on the dashboard does.
  defp period_label(_view, _period, %Date{} = month, _months), do: Periods.month_name(month, "LLLL y")

  defp period_label("summary", period, nil, months) do
    case for(%{"closed" => true, "month" => month} <- months, do: Date.from_iso8601!(month)) do
      [] -> Periods.label(period)
      closed -> Periods.label({List.first(closed), List.last(closed)})
    end
  end

  defp period_label(_view, period, nil, _months), do: Periods.label(period)

  defp category_label("uncategorized"), do: gettext("Uncategorized")

  defp category_label(key) do
    case Enum.find(IndustryTemplate.all_categories(:expenses), &(Atom.to_string(&1) == key)) do
      nil -> nil
      category -> PeriodDetails.category_label(category)
    end
  end

  defp path("summary", period, month, _project),
    do: Navigation.view_path(%{view: :dashboard, period: period, month: month}, [])

  defp path("trends", period, _month, project),
    do: Navigation.view_path(%{view: :trends, period: period}, if(project, do: [{:project, project["id"]}], else: []))

  # The projects view is gone; its earlier conversations lead to the period's summary.
  defp path("projects", period, _month, _project),
    do: Navigation.view_path(%{view: :dashboard, period: period, month: nil}, [])

  defp view_label("summary"), do: gettext("Analysis · Summary")
  defp view_label("trends"), do: gettext("Analysis · Trends")
  defp view_label("projects"), do: gettext("Analysis · Projects")

  # The summary strip's colours: its three largest costs, the rest and what stayed.
  defp tone_styles(index) when is_integer(index), do: Enum.at(~w(bg-rust-800 bg-rust-600 bg-rust-400), index)

  defp tone_styles(:rest), do: "bg-rust-200"
  defp tone_styles(:kept), do: "bg-teal-600"

  defp result_styles(amount), do: if(Decimal.negative?(amount), do: "text-brick-700", else: "text-grey-900")

  defp sum(amounts), do: Enum.reduce(amounts, Decimal.new(0), &Decimal.add/2)
end
