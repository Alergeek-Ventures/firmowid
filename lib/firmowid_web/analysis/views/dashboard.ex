defmodule FirmowidWeb.Analysis.Views.Dashboard do
  @moduledoc """
  Financial overview with month details, project results and category review.

  Views share the authorized year summary. Project results always allocate over
  the whole company. Entries are assigned to projects in invoicing; tax
  estimates stay separate from realized financial totals.
  """
  use FirmowidWeb, :live_view

  import FirmowidWeb.DesignSystem.Components.YearPicker
  import FirmowidWeb.Infrastructure.Flags, only: [flag_enabled?: 2]

  alias Firmowid.Analysis
  alias Firmowid.Analysis.CategoryReview
  alias Firmowid.Analysis.CounterpartyCategory
  alias Firmowid.Analysis.IndustryTemplate
  alias Firmowid.Analysis.ProjectProfitability
  alias Firmowid.Analysis.TagDefinition
  alias Firmowid.Analysis.TaxForecast
  alias Firmowid.Analysis.YearSummary
  alias FirmowidWeb.Analysis.Utilities.Navigation
  alias FirmowidWeb.Invoicing.Utilities.Navigation, as: InvoicingNavigation
  alias FirmowidWeb.Settings.Utilities.Navigation, as: SettingsNavigation

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.ash_scope

    # Employees cannot read the invoices and transactions the dashboard aggregates.
    if flag_enabled?(:analysis_dashboard, socket.assigns) and scope.actor.member.role != :employee do
      if connected?(socket) do
        Phoenix.PubSub.subscribe(Firmowid.PubSub, "analysis-classification:#{scope.tenant}")
      end

      active_months =
        Analysis.get_months_with_entries(scope) ++
          [Date.utc_today()]

      tag_definitions = TagDefinition.list_tag_definitions!(scope: scope)

      socket =
        socket
        |> assign(:active_months, active_months)
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

  @impl true
  def handle_event("change-year", %{"year" => year}, socket) do
    case Integer.parse(year) do
      {year, ""} when year in 1..9999 ->
        {:noreply, push_patch(socket, to: build_path(socket, year: year, month: nil))}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("select-month", %{"month" => month}, %{assigns: %{params: %{view: :dashboard}}} = socket) do
    case Date.from_iso8601(month) do
      {:ok, %Date{year: year} = month} when year == socket.assigns.params.year ->
        month = if socket.assigns.params.month == month, do: nil, else: month
        {:noreply, push_patch(socket, to: build_path(socket, month: month))}

      _ ->
        {:noreply, socket}
    end
  end

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

  # Category confirmations are confined to the categories view, including forged events.
  defp review_groups(%{params: %{view: :categories}, review: review} = assigns) do
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
        Analysis.classify_categories_later(
          socket.assigns.params.year,
          true,
          socket.assigns.ash_scope
        )

    socket = load_review(socket)

    case result do
      {:ok, _rule} ->
        {:noreply, socket}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Could not update categories."))}
    end
  end

  defp load_view(%{assigns: %{params: %{view: :categories}}} = socket), do: load_review(socket)

  defp load_view(%{assigns: %{params: %{view: :segments, year: year}, ash_scope: scope}} = socket) do
    summary = YearSummary.get!(year, %{tag_filters: []}, scope: scope)
    seconds = Analysis.project_seconds_by_month(year, scope)

    socket
    |> assign(:profitability, ProjectProfitability.from_year_summary(summary, seconds))
    |> load_review()
  end

  # Categories come from unfiltered entries, so project filters leave them out.
  defp load_view(socket) do
    socket = socket |> load_year() |> load_tax_forecast()

    if socket.assigns.tag_filters == [],
      do: load_review(socket),
      else: assign(socket, :review, nil)
  end

  # Entries without a category are classified in the background for members who may store categories.
  defp load_review(socket) do
    %{params: %{year: year}, ash_scope: scope} = socket.assigns
    review = Analysis.get_category_review(year, scope)

    # A unique conflict returns the existing job, so reopening the view queues nothing new.
    if review.unclassified != [] and can_tag?(socket.assigns),
      do: Analysis.classify_categories_later(year, false, scope)

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

  defp load_year(socket) do
    summary =
      YearSummary.get!(socket.assigns.params.year, %{tag_filters: socket.assigns.tag_filters},
        scope: socket.assigns.ash_scope
      )

    assign(socket, :year_summary, summary)
  end

  defp build_path(socket, overrides) do
    {tag_filters, overrides} = Keyword.pop(overrides, :tag_filters, socket.assigns.tag_filters)

    socket.assigns.params
    |> Map.merge(Map.new(overrides))
    |> Navigation.view_path(tag_filters)
  end

  defp view_for(params, :categories), do: %{view: :categories, year: selected_month(params).year}

  defp view_for(params, :dashboard), do: %{view: :dashboard, year: selected_month(params).year, month: nil}

  defp view_for(params, :segments), do: %{view: :segments, year: selected_month(params).year}

  # Completed months of the year besides the selected one, as its usual baseline.
  defp compared_months(%{year: year, month: month}) do
    current = Date.beginning_of_month(Date.utc_today())

    for number <- 1..12,
        compared = Date.new!(year, number, 1),
        Date.before?(compared, current) and compared != month,
        do: compared
  end

  defp selected_month(%{month: %Date{} = month}), do: month

  defp selected_month(%{year: year}) do
    today = Date.utc_today()
    if year == today.year, do: Date.beginning_of_month(today), else: Date.new!(year, 1, 1)
  end

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
          <:tab
            :if={can_tag?(assigns)}
            id="analysis-categories"
            patch={Navigation.view_path(view_for(@params, :categories), [])}
            active={@params.view == :categories}
          >
            {pgettext("analysis view", "Costs and income")}
          </:tab>
        </.filter_tabs>
        <.year_picker
          id="year"
          selected_year={@params.year}
          active_years={@active_months |> Enum.map(& &1.year) |> Enum.uniq()}
          variant="secondary"
          size="big"
          data-position="bottom right"
        />
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
          summary={@year_summary}
          tag_filters={@tag_filters}
          selected_month={@params.month}
          key_costs={if @review, do: CategoryReview.key_costs(@review), else: []}
        />
        <FirmowidWeb.Analysis.Components.MonthDetails.details
          :if={@params.month}
          month={Enum.find(@year_summary.months, &(&1.month == @params.month))}
          groups={@review && CategoryReview.month(@review, @params.month, compared_months(@params))}
          entries_path={
            InvoicingNavigation.invoicing_index_path(%{
              month: @params.month,
              filter: :all,
              subfilter: nil,
              view_mode: :list
            })
          }
        />
        <FirmowidWeb.DesignSystem.Components.TaxForecastSummary.tax_forecast_summary
          :if={@tax_forecast && flag_enabled?(:tax_prognosis, assigns)}
          id="analysis-tax-forecast"
          forecast={@tax_forecast}
          settings_path={@tax_forecast_settings_path}
        />
      <% end %>
      <FirmowidWeb.Analysis.Components.CategoryReview.review
        :if={@params.view == :categories}
        review={@review}
        year={@params.year}
      />
      <FirmowidWeb.Analysis.Components.SegmentRanking.ranking
        :if={@params.view == :segments}
        profitability={@profitability}
        review={@review}
        year={@params.year}
        with_overhead={@with_overhead}
        functions={Enum.filter(@tag_definitions, & &1.overhead)}
        can_edit={can_tag?(assigns)}
      />
    </div>
    """
  end
end
