defmodule Firmowid.Assistant.Changes.SetAnalysisSubject do
  @moduledoc """
  Stores the analysis view the user asked about as reference context: its view, period, month
  and project with the figures that view showed, computed with the actor's permissions from
  the same summaries. The figures are a snapshot of what the user saw when asking.
  """
  use Ash.Resource.Change

  alias Ash.Error.Changes.InvalidArgument
  alias Firmowid.Analysis
  alias Firmowid.Analysis.CategoryReview
  alias Firmowid.Analysis.CategoryTotals
  alias Firmowid.Analysis.ProjectProfitability
  alias Firmowid.Analysis.TagDefinition
  alias Firmowid.Scope

  # The dashboard shows at most this many months.
  @max_months 36

  @impl true
  def change(changeset, _opts, context) do
    scope = %Scope{actor: context.actor, tenant: context.tenant}
    arguments = changeset.arguments
    from = Date.beginning_of_month(arguments.from)
    to = Date.beginning_of_month(arguments.to)
    month = arguments[:month] && Date.beginning_of_month(arguments.month)

    case validate_period(from, to, month) do
      :ok ->
        # The figures are read once the policies allowed the action, so an actor who may not
        # read them gets the action's Forbidden.
        Ash.Changeset.before_action(changeset, &put_subject(&1, {from, to}, month, scope))

      {:error, error} ->
        Ash.Changeset.add_error(changeset, error)
    end
  end

  defp put_subject(changeset, period, month, scope) do
    arguments = changeset.arguments

    case project(arguments[:project_id], scope) do
      {:ok, project} ->
        {from, to} = period

        subject =
          Map.merge(
            %{
              "type" => "analysis",
              "view" => Atom.to_string(arguments.view),
              "from" => Date.to_iso8601(from),
              "to" => Date.to_iso8601(to),
              "month" => month && Date.to_iso8601(month),
              "project" => project && %{"id" => project.id, "name" => project.name},
              "title" => arguments.title
            },
            figures(arguments.view, period, month, project, scope)
          )

        changeset
        |> Ash.Changeset.force_change_attribute(:subject, subject)
        |> Ash.Changeset.force_change_attribute(:title, String.slice(arguments.title, 0, 100))

      {:error, error} ->
        Ash.Changeset.add_error(changeset, error)
    end
  end

  defp validate_period(from, to, month) do
    cond do
      Date.after?(from, to) ->
        {:error, InvalidArgument.exception(field: :to, message: "must not be before from")}

      Date.after?(to, Date.shift(from, month: @max_months - 1)) ->
        {:error,
         InvalidArgument.exception(
           field: :to,
           message: "must be within #{@max_months} months of from"
         )}

      month && (Date.before?(month, from) or Date.after?(month, to)) ->
        {:error, InvalidArgument.exception(field: :month, message: "must be within the period")}

      true ->
        :ok
    end
  end

  defp project(nil, _scope), do: {:ok, nil}

  # Projects counted as shared costs are not slices of their own, as on the dashboard.
  defp project(id, scope) do
    case TagDefinition.get_tag_definition(id, scope: scope) do
      {:ok, %TagDefinition{overhead: false} = definition} ->
        {:ok, definition}

      {:ok, _overhead} ->
        {:error, InvalidArgument.exception(field: :project_id, message: "is not a project")}

      {:error, error} ->
        {:error, error}
    end
  end

  # The figures each view shows: months and their totals, the summary's categories (which
  # exist only for the whole company) and the projects' results.
  defp figures(view, period, month, project, scope) do
    filters = if project, do: [{:project, project.id}], else: []
    summary = Analysis.period_summary(period, filters, scope)
    closed = Enum.filter(summary.months, & &1.closed?)

    # A month that is not closed has no result, so the whole period is shown, as on the dashboard.
    shown =
      case Enum.filter(closed, &(&1.month == month)) do
        [] -> closed
        selected -> selected
      end

    Map.merge(
      %{"months" => Enum.map(summary.months, &month_figures/1), "totals" => totals(shown)},
      view_figures(view, period, summary, shown, project, scope)
    )
  end

  defp view_figures(:summary, {from, to}, _summary, shown, nil, scope) do
    review = Analysis.get_category_review(Date.range(from, Date.end_of_month(to)), scope)

    categories =
      review
      |> CategoryReview.period(Enum.map(shown, & &1.month), [])
      |> Enum.group_by(&{&1.side, &1.category || &1.suggestion}, & &1.amount)
      |> Enum.map(fn {key, amounts} ->
        {key, Enum.reduce(amounts, Decimal.new(0), &Decimal.add/2)}
      end)
      |> Enum.filter(fn {_key, amount} -> Decimal.positive?(amount) end)
      |> Enum.sort_by(&elem(&1, 1), {:desc, Decimal})
      |> Enum.map(fn {{side, category}, amount} ->
        %{
          "side" => Atom.to_string(side),
          "category" => if(category, do: Atom.to_string(category), else: "uncategorized"),
          "amount" => Decimal.to_string(amount)
        }
      end)

    %{"categories" => categories}
  end

  # Allocation needs the unfiltered summary, which a project-less view already has.
  defp view_figures(:projects, {from, to}, summary, _shown, nil, scope) do
    seconds =
      from.year..to.year
      |> Enum.map(&Analysis.project_seconds_by_month(&1, scope))
      |> Enum.reduce(%{}, &Map.merge/2)

    profitability =
      ProjectProfitability.from_year_summary(
        %{summary | months: Enum.filter(summary.months, & &1.closed?)},
        seconds
      )

    projects =
      profitability.annual.projects
      |> Enum.sort_by(& &1.direct_profit, {:desc, Decimal})
      |> Enum.map(fn project ->
        %{
          "name" => project.name,
          "hours" => div(project.seconds, 3600),
          "income" => Decimal.to_string(project.income),
          "direct_expenses" => Decimal.to_string(project.direct_expenses),
          "direct_profit" => Decimal.to_string(project.direct_profit),
          "net_profit" => Decimal.to_string(project.net_profit)
        }
      end)

    %{"projects" => projects}
  end

  defp view_figures(_view, _period, _summary, _shown, _project, _scope), do: %{}

  defp month_figures(%{closed?: false} = month), do: %{"month" => Date.to_iso8601(month.month), "closed" => false}

  defp month_figures(month) do
    month.totals
    |> money()
    |> Map.merge(%{"month" => Date.to_iso8601(month.month), "closed" => true})
  end

  defp totals(months) do
    months
    |> Enum.map(& &1.totals)
    |> CategoryTotals.combine()
    |> money()
  end

  defp money(totals) do
    %{
      "income" => Decimal.to_string(totals.total_income),
      "expenses" => totals.total_expenses |> Decimal.abs() |> Decimal.to_string(),
      "result" => Decimal.to_string(totals.net_profit)
    }
  end
end
