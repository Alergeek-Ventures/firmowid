defmodule FirmowidWeb.Analysis.Views.Dashboard do
  @moduledoc """
  Analysis of the company's money in three views: the summary of where every 100 zł of
  income went by category, the trends month by month for the whole company or one project,
  and the project results with the category review.

  Views share the selected period, any run of months, built from the authorized
  year summaries; a trends month opens the summary narrowed to it. Project
  results always allocate over the whole company. Entries are assigned to
  projects in invoicing; tax estimates stay separate from realized totals. Each
  view can start an assistant conversation about what it shows.
  """
  use FirmowidWeb, :live_view

  import FirmowidWeb.DesignSystem.Components.MonthPicker, only: [month_range_picker: 1]
  import FirmowidWeb.Infrastructure.Flags, only: [flag_enabled?: 2]

  alias Firmowid.Analysis
  alias Firmowid.Analysis.CategoryReview
  alias Firmowid.Analysis.CounterpartyCategory
  alias Firmowid.Analysis.IndustryTemplate
  alias Firmowid.Analysis.ProjectProfitability
  alias Firmowid.Analysis.TagDefinition
  alias FirmowidWeb.Analysis.Components.AskAssistant
  alias FirmowidWeb.Analysis.Components.FinancialOverview
  alias FirmowidWeb.Analysis.Components.MonthlyResults
  alias FirmowidWeb.Analysis.Components.PeriodDetails
  alias FirmowidWeb.Analysis.Components.ProjectSwitcher
  alias FirmowidWeb.Analysis.Components.SegmentRanking
  alias FirmowidWeb.Analysis.Utilities.Navigation
  alias FirmowidWeb.Analysis.Utilities.Periods

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.ash_scope

    # Employees cannot read the invoices and transactions the dashboard aggregates.
    if flag_enabled?(:analysis_dashboard, socket.assigns) and scope.actor.member.role != :employee do
      if connected?(socket) do
        Phoenix.PubSub.subscribe(Firmowid.PubSub, "analysis-classification:#{scope.tenant}")
      end

      tag_definitions = TagDefinition.list_tag_definitions!(scope: scope)

      socket =
        socket
        |> assign(:tag_definitions, tag_definitions)
        |> assign(:with_overhead, false)

      {:ok, assign(socket, page_title: pgettext("main navigation", "Analysis"))}
    else
      {:ok, redirect(socket, to: ~p"/")}
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    view = Navigation.parse_view(params)

    # Only the trends show one project; the summary's categories and the projects' allocation
    # need the whole company.
    tag_filters =
      if view.view == :trends,
        do:
          params
          |> Navigation.parse_tag_filters(socket.assigns.tag_definitions)
          |> Enum.filter(&match?({:project, _id}, &1))
          |> Enum.take(1),
        else: []

    socket =
      socket
      |> assign(params: view, tag_filters: tag_filters)
      |> load_view()

    {:noreply, socket}
  end

  @impl true
  def handle_event("confirm-category", %{"key" => key, "side" => side} = params, socket) when is_binary(key) do
    with %{} = group <-
           Enum.find(
             review_groups(socket.assigns),
             &(&1.key == key and Atom.to_string(&1.side) == side and
                 to_string(&1.suggestion) == params["suggestion"] and
                 to_string(&1.source) == params["source"])
           ),
         category when category != nil <-
           Enum.find(
             IndustryTemplate.all_categories(group.side),
             &(Atom.to_string(&1) == params["category"])
           ) do
      confirm_category(socket, group, category)
    else
      nil -> {:noreply, socket}
    end
  end

  def handle_event("select-period", %{"from" => from, "to" => to}, socket) when is_binary(from) and is_binary(to) do
    with {:ok, from} <- Date.from_iso8601(from),
         {:ok, to} <- Date.from_iso8601(to) do
      {from, to} =
        Enum.min_max_by([Date.beginning_of_month(from), Date.beginning_of_month(to)], & &1, Date)

      {:noreply, push_patch(socket, to: build_path(socket, period: {from, to}, month: nil))}
    else
      _invalid -> {:noreply, socket}
    end
  end

  # The period picker's clear button sends no months and goes back to this year; anything partial is ignored.
  def handle_event("select-period", params, socket) when map_size(params) == 0 do
    period = Navigation.year_period(Date.utc_today().year)
    {:noreply, push_patch(socket, to: build_path(socket, period: period, month: nil))}
  end

  def handle_event("select-period", _params, socket), do: {:noreply, socket}

  # A trends month of the whole company opens the summary narrowed to it.
  def handle_event("select-month", %{"month" => month}, %{assigns: %{params: %{view: :trends}, tag_filters: []}} = socket)
      when is_binary(month) do
    case Date.from_iso8601(month) do
      {:ok, month} ->
        month = Date.beginning_of_month(month)

        if month in closed_months(socket.assigns.summary),
          do: {:noreply, push_patch(socket, to: month_path(socket.assigns.params.period).(month))},
          else: {:noreply, socket}

      _invalid ->
        {:noreply, socket}
    end
  end

  def handle_event("select-month", _params, socket), do: {:noreply, socket}

  def handle_event("show-overhead", %{"overhead" => %{"with" => with_overhead}}, socket) do
    {:noreply, assign(socket, :with_overhead, with_overhead == "true")}
  end

  # Company functions are chosen in the segments view, including forged events.
  def handle_event("toggle-function", %{"id" => id}, %{assigns: %{params: %{view: :segments}}} = socket) do
    definition = Enum.find(socket.assigns.tag_definitions, &(&1.id == id))

    if definition != nil and can_tag?(socket.assigns) do
      result =
        TagDefinition.set_overhead(definition, not definition.overhead, scope: socket.assigns.ash_scope)

      definitions = TagDefinition.list_tag_definitions!(scope: socket.assigns.ash_scope)
      socket = socket |> assign(:tag_definitions, definitions) |> load_view()

      case result do
        {:ok, _definition} ->
          {:noreply, socket}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, gettext("Could not move the project."))}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("toggle-function", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_info(:analysis_classification_updated, socket), do: {:noreply, load_view(socket)}

  defp can_tag?(assigns) do
    flag_enabled?(:analysis_dashboard, assigns) and
      assigns.ash_scope.actor.member.role in [:admin, :accountant]
  end

  # Category confirmations are confined to the dashboard's period details, including forged events.
  defp review_groups(%{params: %{view: :dashboard}, review: %{} = review} = assigns) do
    if can_tag?(assigns), do: review.groups, else: []
  end

  defp review_groups(_assigns), do: []

  defp confirm_category(socket, group, category) do
    # Each of the counterparty's names gets the rule, so a period showing only one applies it too.
    result =
      Enum.reduce_while(group.names, nil, fn name, _result ->
        %{
          side: group.side,
          counterparty_key: CategoryReview.key(name),
          counterparty_name: name,
          category: category,
          suggested_category: group.suggestion,
          suggestion_source: group.source
        }
        |> CounterpartyCategory.confirm(scope: socket.assigns.ash_scope)
        |> case do
          {:ok, rule} -> {:cont, {:ok, rule}}
          error -> {:halt, error}
        end
      end)

    # A corrected suggestion teaches the classifier, so its other suggestions are refreshed.
    if category != group.suggestion,
      do:
        for(
          year <- years(socket.assigns.params.period),
          do: Analysis.classify_categories_later(year, true, socket.assigns.ash_scope)
        )

    socket = load_review(socket)

    case result do
      {:ok, _rule} ->
        {:noreply, socket}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Could not update categories."))}
    end
  end

  defp load_view(%{assigns: %{params: %{view: :segments, period: period}, ash_scope: scope}} = socket) do
    summary = Analysis.period_summary(period, [], scope)

    seconds =
      period
      |> years()
      |> Enum.map(&Analysis.project_seconds_by_month(&1, scope))
      |> Enum.reduce(%{}, &Map.merge/2)

    socket
    |> assign(
      :profitability,
      ProjectProfitability.from_year_summary(%{summary | months: closed(summary)}, seconds)
    )
    |> load_review()
    |> update(:review, &closed_review(&1, closed_months(summary)))
  end

  defp load_view(%{assigns: %{params: %{view: :trends} = params, tag_filters: tag_filters, ash_scope: scope}} = socket) do
    assign(socket,
      summary: Analysis.period_summary(params.period, tag_filters, scope),
      review: nil
    )
  end

  defp load_view(%{assigns: %{params: params, ash_scope: scope}} = socket) do
    summary = Analysis.period_summary(params.period, [], scope)

    socket
    |> assign(summary: summary, previous: previous(details_months(params, summary), scope))
    |> load_review()
  end

  # What the summary compares with: a month with the month before, more months with the
  # same months a year earlier, so seasons match. Without income then there is nothing to compare.
  defp previous([], _scope), do: nil

  defp previous(months, scope) do
    shift = if length(months) == 1, do: -1, else: -12

    {from, to} =
      period =
      {Date.shift(List.first(months), month: shift), Date.shift(List.last(months), month: shift)}

    totals = Analysis.period_summary(period, [], scope).totals

    if Decimal.positive?(totals.total_income) do
      review = Analysis.get_category_review(Date.range(from, Date.end_of_month(to)), scope)

      %{
        period: period,
        income: totals.total_income,
        result: totals.net_profit,
        groups: CategoryReview.period(review, Navigation.months(period), [])
      }
    end
  end

  # Income channels, like the projects, count only closed months.
  defp closed_review(review, months) do
    groups = CategoryReview.period(review, months, [])

    income =
      groups
      |> Enum.filter(&(&1.side == :income))
      |> Enum.reduce(Decimal.new(0), &Decimal.add(&1.amount, &2))

    %{review | groups: groups, income: %{review.income | total: income}}
  end

  # Entries without a category are classified in the background for members who may store categories.
  defp load_review(socket) do
    %{params: %{period: {from, to} = period}, ash_scope: scope} = socket.assigns
    review = Analysis.get_category_review(Date.range(from, Date.end_of_month(to)), scope)

    # A unique conflict returns the existing job, so reopening the view queues nothing new.
    # The previous year follows, so it is ready when the owner first looks back.
    if review.unclassified != [] and can_tag?(socket.assigns) do
      for year <- Enum.uniq(years(period) ++ [Date.utc_today().year - 1]),
          do: Analysis.classify_categories_later(year, false, scope)
    end

    assign(socket, :review, review)
  end

  defp closed(summary), do: Enum.filter(summary.months, & &1.closed?)

  defp closed_months(summary), do: summary |> closed() |> Enum.map(& &1.month)

  defp years({from, to}), do: Enum.to_list(from.year..to.year)

  defp build_path(socket, overrides) do
    {tag_filters, overrides} = Keyword.pop(overrides, :tag_filters, socket.assigns.tag_filters)

    socket.assigns.params
    |> Map.merge(Map.new(overrides))
    |> Navigation.view_path(tag_filters)
  end

  defp view_for(params, :dashboard), do: %{view: :dashboard, period: params.period, month: nil}
  defp view_for(params, :trends), do: %{view: :trends, period: params.period}
  defp view_for(params, :segments), do: %{view: :segments, period: params.period}

  defp month_path(period), do: &Navigation.view_path(%{view: :dashboard, period: period, month: &1}, [])

  defp project_options(params, tag_filters, definitions) do
    company = %{
      name: gettext("Whole company"),
      patch: Navigation.view_path(view_for(params, :trends), []),
      selected?: tag_filters == []
    }

    projects =
      for definition <- Enum.sort_by(definitions, &String.downcase(&1.name)),
          not definition.overhead do
        key = {:project, definition.id}

        %{
          name: definition.name,
          patch: Navigation.view_path(view_for(params, :trends), [key]),
          selected?: tag_filters == [key]
        }
      end

    [company | projects]
  end

  # What the assistant is asked about: the view on screen, its period and month or project.
  defp assistant_context(params, summary, tag_filters, definitions) do
    {view, title} =
      case params.view do
        :dashboard -> {"summary", pgettext("analysis view", "Summary")}
        :trends -> {"trends", pgettext("analysis view", "Trends")}
        :segments -> {"projects", pgettext("analysis view", "Projects")}
      end

    month = if params.view == :dashboard, do: selected_month(params, summary)
    project_id = Enum.find_value(tag_filters, fn {:project, id} -> id end)

    shown =
      cond do
        params.view == :dashboard -> details_title(params, summary)
        project_id -> "#{Periods.label(params.period)} · #{slice_name(tag_filters, definitions)}"
        true -> Periods.label(params.period)
      end

    %{
      view: view,
      from: Date.to_iso8601(elem(params.period, 0)),
      to: Date.to_iso8601(elem(params.period, 1)),
      month: month && Date.to_iso8601(month),
      project_id: project_id,
      # The conversation keeps at most 200 characters of it; a long project name must not fail the ask.
      title: String.slice(gettext("%{view}: %{period}", view: title, period: shown), 0, 200)
    }
  end

  # A month that is not closed has no result to show, so a link to one shows the whole period.
  defp selected_month(%{month: %Date{} = month}, summary) do
    if month in closed_months(summary), do: month
  end

  defp selected_month(_params, _summary), do: nil

  defp details_months(params, summary) do
    case selected_month(params, summary) do
      nil -> closed_months(summary)
      month -> [month]
    end
  end

  # A month compares with the period's other closed months, its usual baseline.
  defp compared_months(params, summary) do
    case selected_month(params, summary) do
      nil -> []
      month -> closed_months(summary) -- [month]
    end
  end

  # The details cover only closed months, so their title names those.
  defp details_title(params, summary) do
    closed = closed_months(summary)

    cond do
      month = selected_month(params, summary) ->
        Periods.month_name(month, "LLLL y")

      closed == [] or closed == Enum.map(summary.months, & &1.month) ->
        Periods.label(params.period)

      true ->
        Periods.label({List.first(closed), List.last(closed)})
    end
  end

  # The picker holds only ranges; a single month or a calendar year is shown as its label instead,
  # so two clicks start a new range.
  defp range({%Date{month: 1, year: year}, %Date{month: 12, year: year}}), do: nil
  defp range({from, to}) when from != to, do: {from, to}
  defp range(_month), do: nil

  defp slice_name(filters, definitions) do
    Enum.map_join(filters, ", ", fn
      {:project, id} -> definitions |> Enum.find(&(&1.id == id)) |> Map.fetch!(:name)
      {:company} -> gettext("Company")
      {:taxes} -> gettext("Taxes")
    end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="analysis-dashboard" class="mx-auto flex w-full max-w-7xl flex-col gap-6 py-4">
      <h1 class="sr-only">{pgettext("main navigation", "Analysis")}</h1>
      <div class="mb-4 flex flex-wrap items-center justify-between gap-4">
        <.filter_tabs label={gettext("Analysis views")}>
          <:tab
            id="analysis-overview"
            patch={Navigation.view_path(view_for(@params, :dashboard), [])}
            active={@params.view == :dashboard}
          >
            {pgettext("analysis view", "Summary")}
          </:tab>
          <:tab
            id="analysis-trends-tab"
            patch={Navigation.view_path(view_for(@params, :trends), @tag_filters)}
            active={@params.view == :trends}
          >
            {pgettext("analysis view", "Trends")}
          </:tab>
          <:tab
            id="analysis-segments-tab"
            patch={Navigation.view_path(view_for(@params, :segments), [])}
            active={@params.view == :segments}
          >
            {pgettext("analysis view", "Projects")}
          </:tab>
        </.filter_tabs>
        <div class="flex flex-wrap items-center gap-3">
          <ProjectSwitcher.switcher
            :if={@params.view == :trends}
            id="analysis-project-switcher"
            label={
              if @tag_filters == [],
                do: gettext("Whole company"),
                else: slice_name(@tag_filters, @tag_definitions)
            }
            options={project_options(@params, @tag_filters, @tag_definitions)}
          />
          <.month_range_picker
            id="analysis-period-picker"
            selected={range(@params.period)}
            label={Periods.label(@params.period)}
            clear_label={gettext("This year")}
            aria-label={gettext("Period")}
            data-position="bottom right"
          />
          <AskAssistant.button
            id="analysis-ask-assistant"
            context={
              assistant_context(
                @params,
                @params.view != :segments && @summary,
                @tag_filters,
                @tag_definitions
              )
            }
          />
        </div>
      </div>
      <PeriodDetails.details
        :if={@params.view == :dashboard}
        title={details_title(@params, @summary)}
        title_shown={details_title(@params, @summary) != Periods.label(@params.period)}
        previous={@previous}
        whole_period={
          selected_month(@params, @summary) &&
            Navigation.view_path(view_for(@params, :dashboard), [])
        }
        months={Enum.filter(@summary.months, &(&1.month in details_months(@params, @summary)))}
        groups={
          @review &&
            CategoryReview.period(
              @review,
              details_months(@params, @summary),
              compared_months(@params, @summary)
            )
        }
        industry={@review && @review.industry}
        can_edit={can_tag?(assigns)}
      />
      <%= if @params.view == :trends do %>
        <FinancialOverview.overview
          summary={@summary}
          tag_filters={@tag_filters}
        />
        <MonthlyResults.table
          months={@summary.months}
          totals={@summary.totals}
          month_path={@tag_filters == [] && month_path(@params.period)}
        />
      <% end %>
      <SegmentRanking.ranking
        :if={@params.view == :segments}
        profitability={@profitability}
        review={@review}
        period={@params.period}
        with_overhead={@with_overhead}
        functions={Enum.filter(@tag_definitions, & &1.overhead)}
        can_edit={can_tag?(assigns)}
      />
    </div>
    """
  end
end
