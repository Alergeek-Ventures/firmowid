defmodule FirmowidWeb.Analysis.Views.Dashboard do
  @moduledoc """
  Financial overview with month details, project results and category review.

  Views share the selected period, any run of months, built from the authorized
  year summaries; a chart month narrows the dashboard's details to it. Project
  results always allocate over the whole company. Entries are assigned to
  projects in invoicing; tax estimates stay separate from realized totals.
  """
  use FirmowidWeb, :live_view

  import FirmowidWeb.DesignSystem.Components.MonthPicker, only: [month_range_picker: 1]
  import FirmowidWeb.Infrastructure.Flags, only: [flag_enabled?: 2]

  alias Firmowid.Analysis
  alias Firmowid.Analysis.CategoryReview
  alias Firmowid.Analysis.CategoryTotals
  alias Firmowid.Analysis.CounterpartyCategory
  alias Firmowid.Analysis.IndustryTemplate
  alias Firmowid.Analysis.ProjectProfitability
  alias Firmowid.Analysis.TagDefinition
  alias Firmowid.Analysis.TaxForecast
  alias Firmowid.Analysis.YearSummary
  alias FirmowidWeb.Analysis.Utilities.Navigation
  alias FirmowidWeb.Settings.Utilities.Navigation, as: SettingsNavigation

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
        |> assign(
          :tax_forecast_settings_path,
          tax_forecast_settings_path(socket.assigns.current_org, scope)
        )

      {:ok, assign(socket, page_title: pgettext("main navigation", "Analysis"))}
    else
      {:ok, redirect(socket, to: ~p"/")}
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    socket =
      socket
      |> assign(:params, Navigation.parse_view(params))
      |> assign(
        :tag_filters,
        Navigation.parse_tag_filters(params, socket.assigns.tag_definitions)
      )
      |> load_view()

    {:noreply, socket}
  end

  @impl true
  def handle_event("confirm-category", %{"key" => key, "side" => side} = params, socket) do
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

  # A chart month narrows the details; choosing it again shows the whole period.
  def handle_event("select-month", %{"month" => month}, %{assigns: %{params: %{view: :dashboard} = params}} = socket)
      when is_binary(month) do
    case Date.from_iso8601(month) do
      {:ok, month} ->
        month = Date.beginning_of_month(month)

        if month in Navigation.months(params.period) do
          month = if month == params.month, do: nil, else: month
          {:noreply, push_patch(socket, to: build_path(socket, month: month))}
        else
          {:noreply, socket}
        end

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
  def handle_event("clear-tag-filters", _params, socket) do
    {:noreply, push_patch(socket, to: build_path(socket, tag_filters: []))}
  end

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
    result =
      CounterpartyCategory.confirm(
        %{
          side: group.side,
          counterparty_key: group.key,
          counterparty_name: group.name,
          category: category,
          suggested_category: group.suggestion,
          suggestion_source: group.source
        },
        scope: socket.assigns.ash_scope
      )

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
    summary = period_summary(period, [], scope)

    seconds =
      period
      |> years()
      |> Enum.map(&Analysis.project_seconds_by_month(&1, scope))
      |> Enum.reduce(%{}, &Map.merge/2)

    socket
    |> assign(:profitability, ProjectProfitability.from_year_summary(summary, seconds))
    |> load_review()
  end

  # Categories come from unfiltered entries, so project filters leave them out.
  defp load_view(%{assigns: %{params: params, tag_filters: tag_filters, ash_scope: scope}} = socket) do
    socket =
      socket
      |> assign(:summary, period_summary(params.period, tag_filters, scope))
      |> load_tax_forecast()

    if tag_filters == [],
      do: load_review(socket),
      else: assign(socket, :review, nil)
  end

  # Entries without a category are classified in the background for members who may store categories.
  defp load_review(socket) do
    %{params: %{period: {from, to} = period}, ash_scope: scope} = socket.assigns
    review = Analysis.get_category_review(Date.range(from, Date.end_of_month(to)), scope)

    # A unique conflict returns the existing job, so reopening the view queues nothing new.
    if review.unclassified != [] and can_tag?(socket.assigns),
      do: for(year <- years(period), do: Analysis.classify_categories_later(year, false, scope))

    assign(socket, :review, review)
  end

  defp load_tax_forecast(%{assigns: %{params: %{view: :dashboard, month: %Date{} = month}, tag_filters: []}} = socket) do
    assign(
      socket,
      :tax_forecast,
      TaxForecast.get!(%{month: month}, scope: socket.assigns.ash_scope)
    )
  end

  defp load_tax_forecast(socket), do: assign(socket, :tax_forecast, nil)

  # Only viewers who may change the reserve assumptions get a link to them.
  defp tax_forecast_settings_path(organization, scope) do
    if Ash.can?({organization, :update_tax_forecast_settings}, scope),
      do: SettingsNavigation.canonical_path(:invoices) <> "#rezerwa-podatkowa"
  end

  # The period's months from the year summaries it spans.
  defp period_summary(period, tag_filters, scope) do
    months = Navigation.months(period)

    months =
      for year <- years(period),
          month <- YearSummary.get!(year, %{tag_filters: tag_filters}, scope: scope).months,
          month.month in months,
          do: month

    %{
      currency: "PLN",
      months: months,
      totals: months |> Enum.map(& &1.totals) |> CategoryTotals.combine()
    }
  end

  defp years({from, to}), do: Enum.to_list(from.year..to.year)

  defp build_path(socket, overrides) do
    {tag_filters, overrides} = Keyword.pop(overrides, :tag_filters, socket.assigns.tag_filters)

    socket.assigns.params
    |> Map.merge(Map.new(overrides))
    |> Navigation.view_path(tag_filters)
  end

  defp view_for(params, :dashboard), do: %{view: :dashboard, period: params.period, month: nil}
  defp view_for(params, :segments), do: %{view: :segments, period: params.period}

  defp details_months(%{month: %Date{} = month}), do: [month]
  defp details_months(%{period: period}), do: Navigation.months(period)

  # A month compares with the period's other completed months, its usual baseline.
  defp compared_months(%{period: period, month: %Date{} = month}) do
    current = Date.beginning_of_month(Date.utc_today())

    for compared <- Navigation.months(period),
        Date.before?(compared, current),
        compared != month,
        do: compared
  end

  defp compared_months(_params), do: []

  defp details_title(%{month: %Date{} = month}), do: month_name(month, "LLLL y")
  defp details_title(%{period: period}), do: period_title(period)

  defp period_title({month, month}), do: month_name(month, "LLLL y")

  defp period_title({%Date{month: 1, year: year}, %Date{month: 12, year: year}}), do: Integer.to_string(year)

  defp period_title({%Date{year: year} = from, %Date{year: year} = to}),
    do: gettext("%{from} – %{to}", from: month_name(from, "LLLL"), to: month_name(to, "LLLL y"))

  defp period_title({from, to}),
    do: gettext("%{from} – %{to}", from: month_name(from, "LLLL y"), to: month_name(to, "LLLL y"))

  # The picker holds only ranges; a single month or a calendar year is shown as its label instead,
  # so two clicks start a new range.
  defp range({%Date{month: 1, year: year}, %Date{month: 12, year: year}}), do: nil
  defp range({from, to}) when from != to, do: {from, to}
  defp range(_month), do: nil

  defp month_name(month, format), do: month |> Firmowid.Cldr.Date.to_string!(format: format) |> String.capitalize()

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
            patch={Navigation.view_path(view_for(@params, :dashboard), @tag_filters)}
            active={@params.view == :dashboard}
          >
            {pgettext("analysis view", "Dashboard")}
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
          <.month_range_picker
            id="analysis-period-picker"
            selected={range(@params.period)}
            label={period_title(@params.period)}
            clear_label={gettext("This year")}
            aria-label={gettext("Period")}
            data-position="bottom right"
          />
        </div>
      </div>
      <div
        :if={@tag_filters != []}
        id="analysis-slice"
        class="flex flex-wrap items-baseline gap-x-4 gap-y-1"
      >
        <h2 class="text-2xl font-semibold text-grey-900">
          {slice_name(@tag_filters, @tag_definitions)}
        </h2>
        <FirmowidUI.Components.Button.button
          id="clear-tag-filters"
          type="button"
          variant="unstyled"
          phx-click="clear-tag-filters"
          class="cursor-pointer text-sm text-grey-700 underline active:text-grey-900"
        >
          {gettext("Show the whole company")}
        </FirmowidUI.Components.Button.button>
      </div>
      <%= if @params.view == :dashboard do %>
        <FirmowidWeb.Analysis.Components.FinancialOverview.overview
          summary={@summary}
          tag_filters={@tag_filters}
          selected_month={@params.month}
          key_costs={if @review, do: CategoryReview.key_costs(@review), else: []}
        />
        <FirmowidWeb.Analysis.Components.PeriodDetails.details
          title={details_title(@params)}
          months={Enum.filter(@summary.months, &(&1.month in details_months(@params)))}
          groups={
            @review &&
              CategoryReview.period(@review, details_months(@params), compared_months(@params))
          }
          industry={@review && @review.industry}
          can_edit={can_tag?(assigns)}
        />
        <FirmowidWeb.DesignSystem.Components.TaxForecastSummary.tax_forecast_summary
          :if={@tax_forecast && flag_enabled?(:tax_prognosis, assigns)}
          id="analysis-tax-forecast"
          forecast={@tax_forecast}
          settings_path={@tax_forecast_settings_path}
        />
      <% end %>
      <FirmowidWeb.Analysis.Components.SegmentRanking.ranking
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
