defmodule FirmowidWeb.Analysis.Views.Dashboard do
  @moduledoc """
  Financial overview with month details, segment ranking, category review and
  monthly entry classification.

  Read-only views share the authorized year summary. Project results always
  allocate over the whole company. Only tagging allows entry category changes;
  unrealized entries and tax estimates stay separate from realized financial totals.
  """
  use FirmowidWeb, :live_view

  import FirmowidWeb.DesignSystem.Components.MonthPicker
  import FirmowidWeb.DesignSystem.Components.YearPicker
  import FirmowidWeb.Infrastructure.Flags, only: [flag_enabled?: 2]

  alias Firmowid.Ash.Analysis
  alias Firmowid.Ash.Analysis.CategoryReview
  alias Firmowid.Ash.Analysis.CounterpartyCategory
  alias Firmowid.Ash.Analysis.EntityTag
  alias Firmowid.Ash.Analysis.IndustryTemplate
  alias Firmowid.Ash.Analysis.ProjectProfitability
  alias Firmowid.Ash.Analysis.TagDefinition
  alias Firmowid.Ash.Analysis.TaxForecast
  alias Firmowid.Ash.Analysis.YearSummary
  alias Firmowid.Ash.Finances.Transaction
  alias Firmowid.Ash.Invoicing.CostInvoice
  alias Firmowid.Ash.Invoicing.SalesInvoice
  alias FirmowidWeb.Analysis.Utilities.CategoryColors
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

      active_months =
        Analysis.get_months_with_entries(scope) ++
          [Date.utc_today()]

      tag_definitions = TagDefinition.list_tag_definitions!(scope: scope)

      socket =
        socket
        |> assign(:active_months, active_months)
        |> assign(:tag_definitions, tag_definitions)
        |> assign(:category_colors, CategoryColors.for_definitions(tag_definitions))
        |> assign(:expanded_section, :income)
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
  def handle_event(event, params, socket)
      when event in ["set-entity-category", "clear-entity-tags", "toggle-project-tag", "create-category"] do
    # Read-only views need not load entries, so authorization comes before looking them up.
    row =
      if can_write?(socket.assigns) do
        Enum.find(
          socket.assigns.sales_invoices ++
            socket.assigns.cost_invoices ++ socket.assigns.transactions,
          fn row ->
            row.id == params["entity_id"] and
              Atom.to_string(category_entity_type(row)) == params["entity_type"]
          end
        )
      end

    if row != nil and category_editable?(row) do
      case change_category(event, params, row, socket) do
        {:ok, _} when event == "create-category" ->
          {:noreply, socket |> load_categories() |> load_totals()}

        {:ok, _} ->
          {:noreply, load_totals(socket)}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, gettext("Could not update categories."))}
      end
    else
      {:noreply, socket}
    end
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
      confirm_categories(socket, [{group, category}])
    else
      nil -> {:noreply, socket}
    end
  end

  # Confirmations apply to the whole counterparty, so one already confirmed or
  # suggested several categories is left for the owner to decide.
  def handle_event("confirm-suggestions", _params, socket) do
    groups = review_groups(socket.assigns)

    undecided =
      groups
      |> Enum.group_by(&{&1.side, &1.key})
      |> Map.filter(fn {_counterparty, groups} ->
        Enum.any?(groups, &(&1.status == :confirmed)) or
          groups |> Enum.map(& &1.suggestion) |> Enum.uniq() |> length() > 1
      end)

    confirm_categories(
      socket,
      for(
        group <- groups,
        group.suggestion,
        not Map.has_key?(undecided, {group.side, group.key}),
        do: {group, group.suggestion}
      )
    )
  end

  def handle_event("assign-unassigned", _params, socket) do
    if can_write?(socket.assigns) do
      case EntityTag.classify_month(%{month: socket.assigns.params.month},
             scope: socket.assigns.ash_scope
           ) do
        {:ok, _job} ->
          {:noreply, put_flash(socket, :info, gettext("Assignment started in the background."))}

        {:error, _reason} ->
          {:noreply, put_flash(socket, :error, gettext("Assignment is currently unavailable."))}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("clear-month-tags", _params, socket) do
    if can_write?(socket.assigns) do
      case EntityTag.clear_month(%{month: socket.assigns.params.month},
             scope: socket.assigns.ash_scope
           ) do
        :ok ->
          {:noreply, load_totals(socket)}

        {:error, _reason} ->
          {:noreply, put_flash(socket, :error, gettext("Could not update categories."))}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("change-month", %{"month" => month}, socket) do
    month = Date.from_iso8601!(month)
    {:noreply, push_patch(socket, to: build_path(socket, month: month))}
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

  def handle_event("filter-project", %{"project" => project}, socket) do
    valid_ids = Enum.map(socket.assigns.tag_definitions, & &1.id)

    if project == "all" or project in valid_ids do
      filters = if project == "all", do: [], else: [{:project, project}]
      {:noreply, push_patch(socket, to: build_path(socket, tag_filters: filters))}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("select-section", %{"section" => "income"}, socket) do
    {:noreply, assign(socket, :expanded_section, :income)}
  end

  def handle_event("select-section", %{"section" => "expenses"}, socket) do
    {:noreply, assign(socket, :expanded_section, :expenses)}
  end

  @impl true
  def handle_event("clear-tag-filters", _params, socket) do
    {:noreply, push_patch(socket, to: build_path(socket, tag_filters: []))}
  end

  @impl true
  def handle_info(:analysis_classification_updated, %{assigns: %{params: %{view: :tagging}}} = socket),
    do: {:noreply, load_totals(socket)}

  def handle_info(:analysis_classification_updated, socket), do: {:noreply, load_view(socket)}

  defp entries_for_section(%{expanded_section: :income} = assigns) do
    omitted_last(assigns.sales_invoices ++ Enum.filter(assigns.transactions, &Money.positive?(&1.amount)))
  end

  defp entries_for_section(%{expanded_section: :expenses} = assigns) do
    omitted_last(assigns.cost_invoices ++ Enum.filter(assigns.transactions, &Money.negative?(&1.amount)))
  end

  defp omitted_last(entries) do
    Enum.sort_by(entries, fn entry -> Enum.any?(entry.entity_tags, &(&1.kind == :internal)) end)
  end

  defp can_tag?(assigns) do
    flag_enabled?(:analysis_dashboard, assigns) and
      assigns.ash_scope.actor.member.role in [:admin, :accountant]
  end

  # Category changes are confined to tagging, including forged read-only events.
  defp can_write?(assigns), do: assigns.params.view == :tagging and can_tag?(assigns)

  # Category confirmations are confined to the categories view, including forged events.
  defp review_groups(%{params: %{view: :categories}, review: review} = assigns) do
    if can_tag?(assigns), do: review.groups, else: []
  end

  defp review_groups(_assigns), do: []

  # Nothing to confirm, e.g. a forged event outside the categories view, leaves the view as is.
  defp confirm_categories(socket, []), do: {:noreply, socket}

  defp confirm_categories(socket, confirmations) do
    result =
      Enum.reduce_while(confirmations, :ok, fn {group, category}, :ok ->
        case CounterpartyCategory.confirm(
               %{
                 side: group.side,
                 counterparty_key: group.key,
                 counterparty_name: group.name,
                 category: category,
                 suggested_category: group.suggestion,
                 suggestion_source: group.source
               },
               scope: socket.assigns.ash_scope
             ) do
          {:ok, _rule} -> {:cont, :ok}
          {:error, error} -> {:halt, {:error, error}}
        end
      end)

    # A corrected suggestion teaches the classifier, so its other suggestions are refreshed.
    refreshing =
      Enum.any?(confirmations, fn {group, category} -> category != group.suggestion end) and
        match?(
          {:ok, _job},
          Analysis.classify_categories_later(
            socket.assigns.params.year,
            true,
            socket.assigns.ash_scope
          )
        )

    socket = load_review(socket)
    socket = assign(socket, :classifying, socket.assigns.classifying or refreshing)

    case result do
      :ok ->
        {:noreply, socket}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Could not update categories."))}
    end
  end

  defp category_entity_type(%SalesInvoice{}), do: :sales_invoice
  defp category_entity_type(%CostInvoice{}), do: :cost_invoice
  defp category_entity_type(%Transaction{}), do: :transaction

  defp category_editable?(%Transaction{} = row), do: row.skip_invoicing

  defp category_editable?(row), do: row.skip_invoicing or row.transactions != []

  defp change_category("create-category", %{"name" => name}, row, socket) do
    TagDefinition.create_for_entry(
      %{name: name, entity_type: category_entity_type(row), resource_id: row.id},
      scope: socket.assigns.ash_scope
    )
  end

  defp change_category("clear-entity-tags", _params, row, socket) do
    EntityTag.clear_entity_tags(
      %{entity_type: category_entity_type(row), resource_id: row.id},
      scope: socket.assigns.ash_scope
    )
  end

  defp change_category("set-entity-category", %{"kind" => kind}, row, socket)
       when kind in ["company", "taxes", "internal"] do
    EntityTag.set_entity_category(
      %{
        entity_type: category_entity_type(row),
        resource_id: row.id,
        kind: kind
      },
      scope: socket.assigns.ash_scope
    )
  end

  defp change_category("toggle-project-tag", %{"tag_definition_id" => id}, row, socket) do
    active_ids = Enum.map(socket.assigns.categories, & &1.id)

    if id in active_ids do
      current =
        row.entity_tags
        |> Enum.filter(&(&1.kind == :project and &1.tag_definition_id in active_ids))
        |> Enum.map(& &1.tag_definition_id)

      ids = if id in current, do: List.delete(current, id), else: [id | current]

      EntityTag.set_entity_project_tags(
        %{entity_type: category_entity_type(row), resource_id: row.id, tag_definition_ids: ids},
        scope: socket.assigns.ash_scope
      )
    else
      {:error, :invalid_category}
    end
  end

  defp change_category(_event, _params, _row, _socket), do: {:error, :invalid_category}

  defp load_categories(socket) do
    scope = socket.assigns.ash_scope
    definitions = TagDefinition.list_tag_definitions!(scope: scope)

    socket
    |> assign(:tag_definitions, definitions)
    |> assign(:category_colors, CategoryColors.for_definitions(definitions))
    |> assign(:categories, Analysis.list_available_categories(socket.assigns.params.month, scope))
  end

  defp load_view(%{assigns: %{params: %{view: :tagging}}} = socket), do: load_month(socket)

  defp load_view(%{assigns: %{params: %{view: :categories}}} = socket), do: load_review(socket)

  defp load_view(%{assigns: %{params: %{view: :segments, year: year}}} = socket) do
    summary = YearSummary.get!(year, %{tag_filters: []}, scope: socket.assigns.ash_scope)

    socket
    |> assign(:profitability, ProjectProfitability.from_year_summary(summary))
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

    # A unique conflict returns the existing job, which may have finished already.
    classifying =
      review.unclassified != [] and can_tag?(socket.assigns) and
        case Analysis.classify_categories_later(year, false, scope) do
          {:ok, job} -> job.state in ["available", "scheduled", "executing", "retryable"]
          {:error, :classification_unavailable} -> false
        end

    socket
    |> assign(:review, review)
    |> assign(:classifying, classifying)
  end

  defp load_month(socket) do
    socket
    |> assign(
      :categories,
      Analysis.list_available_categories(socket.assigns.params.month, socket.assigns.ash_scope)
    )
    |> assign(:expanded_section, :income)
    |> load_tax_forecast()
    |> load_data()
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

  # Category changes do not affect unrealized entries, so they only reload totals.
  defp load_data(socket) do
    month = socket.assigns.params.month

    unrealized =
      Analysis.get_unrealized_entries(
        Date.beginning_of_month(month),
        Date.end_of_month(month),
        socket.assigns.ash_scope
      )

    socket
    |> assign(:unrealized, unrealized)
    |> load_totals()
  end

  defp load_totals(socket) do
    month = socket.assigns.params.month
    tag_filters = socket.assigns.tag_filters

    totals =
      Analysis.get_organization_totals(
        Date.beginning_of_month(month),
        Date.end_of_month(month),
        [tag_filters: tag_filters],
        socket.assigns.ash_scope
      )

    socket
    |> assign(:monthly_totals, Map.drop(totals, [:transactions, :sales_invoices, :cost_invoices]))
    |> assign(:transactions, totals.transactions)
    |> assign(:sales_invoices, totals.sales_invoices)
    |> assign(:cost_invoices, totals.cost_invoices)
  end

  defp unrealized_for_section(%{expanded_section: :income, unrealized: unrealized}), do: unrealized.income_entries

  defp unrealized_for_section(%{expanded_section: :expenses, unrealized: unrealized}), do: unrealized.expense_entries

  defp build_path(socket, overrides) do
    {tag_filters, overrides} = Keyword.pop(overrides, :tag_filters, socket.assigns.tag_filters)

    socket.assigns.params
    |> Map.merge(Map.new(overrides))
    |> Navigation.view_path(tag_filters)
  end

  defp view_for(params, :tagging), do: %{view: :tagging, month: selected_month(params)}

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

  defp selected_project([{:project, id}]), do: id
  defp selected_project(_filters), do: "all"

  defp tab_styles(true) do
    "inline-flex min-block-11 items-center rounded-md bg-teal-700 px-4 text-sm font-medium text-white focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-teal-700 active:opacity-90"
  end

  defp tab_styles(false) do
    "inline-flex min-block-11 items-center rounded-md px-4 text-sm font-medium text-grey-700 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-teal-700 active:bg-grey-200"
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="analysis-dashboard" class="mx-auto flex w-full max-w-7xl flex-col gap-6 py-4">
      <div class="flex flex-wrap items-center justify-between gap-4">
        <h1 class="text-xl font-semibold text-grey-900">
          {pgettext("main navigation", "Analysis")}
        </h1>
        <div class="flex flex-wrap items-center gap-3">
          <FirmowidUI.Components.Button.button
            :if={can_write?(assigns)}
            id="clear-month-tags"
            variant="secondary"
            type="button"
            phx-click={show_modal("clear-month-tags-modal")}
          >
            {gettext("Clear month's categories")}
          </FirmowidUI.Components.Button.button>
          <FirmowidUI.Components.Button.button
            :if={can_write?(assigns)}
            id="assign-unassigned"
            variant="secondary"
            type="button"
            phx-click="assign-unassigned"
            phx-disable-with={gettext("Assign unassigned")}
          >
            {gettext("Assign unassigned")}
          </FirmowidUI.Components.Button.button>
          <.month_picker
            :if={@params.view == :tagging}
            id="month"
            active_months={@active_months}
            selected_date={@params.month}
            data-position="bottom right"
          />
          <.year_picker
            :if={@params.view != :tagging}
            id="year"
            selected_year={@params.year}
            active_years={@active_months |> Enum.map(& &1.year) |> Enum.uniq()}
            variant="secondary"
            data-position="bottom right"
          />
        </div>
      </div>
      <nav
        id="analysis-modes"
        aria-label={gettext("Analysis views")}
        class="flex flex-wrap items-center gap-1"
      >
        <FirmowidUI.Components.Link.link
          id="analysis-overview"
          kind="unstyled"
          patch={Navigation.view_path(view_for(@params, :dashboard), @tag_filters)}
          aria-current={if @params.view == :dashboard, do: "page"}
          class={tab_styles(@params.view == :dashboard)}
        >
          {pgettext("analysis view", "Dashboard")}
        </FirmowidUI.Components.Link.link>
        <FirmowidUI.Components.Link.link
          id="analysis-segments-tab"
          kind="unstyled"
          patch={Navigation.view_path(view_for(@params, :segments), [])}
          aria-current={if @params.view == :segments, do: "page"}
          class={tab_styles(@params.view == :segments)}
        >
          {pgettext("analysis view", "Segments")}
        </FirmowidUI.Components.Link.link>
        <FirmowidUI.Components.Link.link
          :if={can_tag?(assigns)}
          id="analysis-categories"
          kind="unstyled"
          patch={Navigation.view_path(view_for(@params, :categories), [])}
          aria-current={if @params.view == :categories, do: "page"}
          class={tab_styles(@params.view == :categories)}
        >
          {pgettext("analysis view", "Categories")}
        </FirmowidUI.Components.Link.link>
        <FirmowidUI.Components.Link.link
          :if={can_tag?(assigns)}
          id="analysis-tagging"
          kind="unstyled"
          patch={Navigation.view_path(view_for(@params, :tagging), @tag_filters)}
          aria-current={if @params.view == :tagging, do: "page"}
          class={tab_styles(@params.view == :tagging)}
        >
          {pgettext("analysis mode", "Tagging")}
        </FirmowidUI.Components.Link.link>
      </nav>
      <div
        :if={@params.view == :dashboard or @tag_filters != []}
        class="@container flex flex-wrap items-end gap-x-3 gap-y-2 @lg:gap-4"
      >
        <form
          :if={@params.view == :dashboard}
          id="analysis-project-filter"
          phx-change="filter-project"
          class="flex flex-col gap-1 min-inline-0"
        >
          <label for="analysis-project" class="text-xs font-medium text-grey-700">{gettext("Project")}</label>
          <select
            id="analysis-project"
            name="project"
            class="rounded-md border border-grey-400 bg-white px-3 text-sm max-inline-full min-block-11 focus-visible:outline-2 focus-visible:outline-teal-700"
          >
            <option value="all" selected={selected_project(@tag_filters) == "all"}>
              {gettext("All projects")}
            </option>
            <option
              :for={definition <- @tag_definitions}
              value={definition.id}
              selected={selected_project(@tag_filters) == definition.id}
            >
              {definition.name}
            </option>
          </select>
        </form>
        <div :if={@tag_filters != []} class="text-sm text-grey-700">
          <FirmowidUI.Components.Button.button
            id="clear-tag-filters"
            type="button"
            variant="unstyled"
            phx-click="clear-tag-filters"
            class="cursor-pointer underline active:text-grey-900"
          >
            {gettext("Clear filters")}
          </FirmowidUI.Components.Button.button>
        </div>
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
            if can_tag?(assigns),
              do: Navigation.view_path(view_for(@params, :tagging), @tag_filters)
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
        classifying={@classifying}
      />
      <FirmowidWeb.Analysis.Components.SegmentRanking.ranking
        :if={@params.view == :segments}
        profitability={@profitability}
        review={@review}
        year={@params.year}
      />
      <%= if @params.view == :tagging do %>
        <section id="analysis-month" class="flex flex-col gap-4">
          <div role="group" aria-label={gettext("Entry direction")} class="flex flex-wrap gap-1">
            <FirmowidUI.Components.Button.button
              type="button"
              variant="unstyled"
              id="analysis-income"
              phx-click="select-section"
              phx-value-section="income"
              aria-pressed={to_string(@expanded_section == :income)}
              class={tab_styles(@expanded_section == :income)}
            >
              {gettext("Income")}
              <span class="ps-2 tabular-nums">{Money.new(:PLN, @monthly_totals.total_income)}</span>
            </FirmowidUI.Components.Button.button>
            <FirmowidUI.Components.Button.button
              type="button"
              variant="unstyled"
              id="analysis-expenses"
              phx-click="select-section"
              phx-value-section="expenses"
              aria-pressed={to_string(@expanded_section == :expenses)}
              class={tab_styles(@expanded_section == :expenses)}
            >
              {gettext("Expenses")}
              <span class="ps-2 tabular-nums">{Money.new(
                :PLN,
                Decimal.abs(@monthly_totals.total_expenses)
              )}</span>
            </FirmowidUI.Components.Button.button>
          </div>
        </section>
        <section id="analysis-entries">
          <p :if={@tag_filters != []} class="text-sm text-grey-700">
            {gettext("Entry amounts are shown in full; project filters select matching documents.")}
          </p>
          <div class="overflow-x-auto">
            <FirmowidWeb.Analysis.Components.EntriesTable.table
              entries={entries_for_section(assigns)}
              categories={@categories}
              colors={@category_colors}
              can_write={can_write?(assigns)}
            />
          </div>
        </section>
        <section
          :if={@tag_filters == [] and unrealized_for_section(assigns) != []}
          id="analysis-unrealized"
          class="flex flex-col gap-3"
        >
          <h2 class="text-lg font-medium text-grey-700">
            {if @expanded_section == :income,
              do: gettext("Unrealized income"),
              else: gettext("Unrealized expenses")}
          </h2>
          <p class="mt-1 text-sm text-grey-700">
            {gettext(
              "Invoices without a payment and payments without an invoice or salary, dated this month. Link them or mark them as skipped to include them in the analysis."
            )}
          </p>
          <div class="overflow-x-auto">
            <FirmowidWeb.Analysis.Components.EntriesTable.table
              entries={unrealized_for_section(assigns)}
              colors={@category_colors}
              unrealized
            />
          </div>
        </section>
        <.modal :if={can_write?(assigns)} id="clear-month-tags-modal">
          <div class="flex flex-col gap-6">
            <h2 class="font-bold">{gettext("Clear month's categories?")}</h2>
            <p>
              {gettext(
                "All categories assigned to this month's entries will be removed, including manual ones. This cannot be undone."
              )}
            </p>
            <div class="flex flex-wrap justify-end gap-3">
              <FirmowidUI.Components.Button.button
                type="button"
                variant="outline"
                phx-click={hide_modal("clear-month-tags-modal")}
              >
                {gettext("Cancel")}
              </FirmowidUI.Components.Button.button>
              <FirmowidUI.Components.Button.button
                id="confirm-clear-month-tags"
                type="button"
                phx-click={JS.push("clear-month-tags") |> hide_modal("clear-month-tags-modal")}
              >
                {gettext("Clear categories")}
              </FirmowidUI.Components.Button.button>
            </div>
          </div>
        </.modal>
      <% end %>
    </div>
    """
  end
end
