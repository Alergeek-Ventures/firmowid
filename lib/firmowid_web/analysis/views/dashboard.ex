defmodule FirmowidWeb.Analysis.Views.Dashboard do
  @moduledoc """
  LiveView for the financial analysis dashboard.

  Displays monthly income and expense pie charts with project-based filtering.
  URL params control the active month (`?miesiac=YYYY-MM-DD`) and tag filters
  (`?tagi=firma,projekt:<id>`).
  """
  use FirmowidWeb, :live_view

  import FirmowidWeb.Analysis.Components.CategoryChart
  import FirmowidWeb.DesignSystem.Components.MonthPicker
  import FirmowidWeb.Infrastructure.Flags, only: [flag_enabled?: 2]

  alias Firmowid.Ash.Analysis
  alias Firmowid.Ash.Analysis.EntityTag
  alias Firmowid.Ash.Analysis.TagDefinition
  alias Firmowid.Ash.Finances.Transaction
  alias Firmowid.Ash.Invoicing.CostInvoice
  alias Firmowid.Ash.Invoicing.SalesInvoice
  alias Firmowid.Ash.Timetracker.Project
  alias FirmowidWeb.Analysis.Utilities.Navigation
  alias FirmowidWeb.Infrastructure.Utilities.QueryParams

  @impl true
  def mount(_params, _session, socket) do
    if flag_enabled?(:analysis_dashboard, socket.assigns) do
      scope = socket.assigns.ash_scope

      if connected?(socket) do
        Phoenix.PubSub.subscribe(Firmowid.PubSub, "analysis-classification:#{scope.tenant}")
      end

      active_months =
        Analysis.get_months_with_entries(scope) ++
          [Date.utc_today()]

      tag_definitions = TagDefinition.list_tag_definitions!(scope: scope)

      categories =
        %{status: :active}
        |> Project.list!(load: [:tag_definition], scope: scope)
        |> Enum.map(& &1.tag_definition)
        |> Enum.reject(&is_nil/1)
        |> Enum.sort_by(& &1.name)

      socket =
        socket
        |> assign(:active_months, active_months)
        |> assign(:tag_definitions, tag_definitions)
        |> assign(:categories, categories)
        |> assign(:category_colors, category_colors(tag_definitions))
        |> assign(:expanded_section, :income)

      {:ok, assign(socket, page_title: pgettext("main navigation", "Analysis"))}
    else
      {:ok, redirect(socket, to: ~p"/")}
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    month = QueryParams.parse_date(params, "miesiac", Date.beginning_of_month(Date.utc_today()))

    tag_filters = Navigation.parse_tag_filters(params, socket.assigns.tag_definitions)

    socket =
      socket
      |> assign(:params, %{month: month})
      |> assign(:tag_filters, tag_filters)
      |> assign(:expanded_section, :income)
      |> load_data()

    {:noreply, socket}
  end

  @impl true
  def handle_event(event, params, socket)
      when event in ["set-entity-category", "clear-entity-tags", "toggle-project-tag"] do
    allowed =
      flag_enabled?(:analysis_dashboard, socket.assigns) and
        socket.assigns.ash_scope.actor.role in [:admin, :accountant]

    row =
      Enum.find(
        socket.assigns.sales_invoices ++
          socket.assigns.cost_invoices ++ socket.assigns.transactions,
        fn row ->
          row.id == params["entity_id"] and
            Atom.to_string(category_entity_type(row)) == params["entity_type"]
        end
      )

    if allowed and row != nil and category_editable?(row) do
      case change_category(event, params, row, socket) do
        {:ok, _} ->
          {:noreply, load_data(socket)}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, gettext("Could not update categories."))}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("assign-unassigned", _params, socket) do
    case EntityTag.classify_month(%{month: socket.assigns.params.month},
           scope: socket.assigns.ash_scope
         ) do
      {:ok, _job} ->
        {:noreply, put_flash(socket, :info, gettext("Assignment started in the background."))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Assignment is currently unavailable."))}
    end
  end

  @impl true
  def handle_event("change-month", %{"month" => month}, socket) do
    month = Date.from_iso8601!(month)
    {:noreply, push_patch(socket, to: build_path(socket, month: month))}
  end

  @impl true
  def handle_event("select-section", %{"section" => "income"}, socket) do
    {:noreply, assign(socket, :expanded_section, :income)}
  end

  def handle_event("select-section", %{"section" => "expenses"}, socket) do
    {:noreply, assign(socket, :expanded_section, :expenses)}
  end

  @impl true
  def handle_event("toggle-tag", %{"tag" => tag_key}, socket) do
    current = socket.assigns.tag_filters
    filter = Navigation.parse_tag_filter(tag_key)

    case filter do
      :invalid ->
        {:noreply, socket}

      _valid_filter ->
        updated =
          if filter in current do
            List.delete(current, filter)
          else
            [filter | current]
          end

        {:noreply, push_patch(socket, to: build_path(socket, tag_filters: updated))}
    end
  end

  @impl true
  def handle_event("clear-tag-filters", _params, socket) do
    {:noreply, push_patch(socket, to: build_path(socket, tag_filters: []))}
  end

  @impl true
  def handle_info(:analysis_classification_updated, socket), do: {:noreply, load_data(socket)}

  defp entries_for_section(%{expanded_section: :income} = assigns) do
    omitted_last(assigns.sales_invoices ++ Enum.filter(assigns.transactions, &Money.positive?(&1.amount)))
  end

  defp entries_for_section(%{expanded_section: :expenses} = assigns) do
    omitted_last(assigns.cost_invoices ++ Enum.filter(assigns.transactions, &Money.negative?(&1.amount)))
  end

  defp entries_for_section(_assigns), do: []

  defp omitted_last(entries) do
    Enum.sort_by(entries, fn entry -> Enum.any?(entry.entity_tags, &(&1.kind == :internal)) end)
  end

  defp category_entity_type(%SalesInvoice{}), do: :sales_invoice
  defp category_entity_type(%CostInvoice{}), do: :cost_invoice
  defp category_entity_type(%Transaction{}), do: :transaction

  defp category_editable?(%Transaction{} = row), do: row.skip_invoicing

  defp category_editable?(row), do: row.skip_invoicing or row.transactions != []

  defp change_category("clear-entity-tags", _params, row, socket) do
    EntityTag.clear_entity_tags(
      %{entity_type: category_entity_type(row), resource_id: row.id},
      scope: socket.assigns.ash_scope
    )
  end

  defp change_category("set-entity-category", %{"kind" => kind}, row, socket) when kind in ["company", "internal"] do
    EntityTag.set_entity_category(
      %{
        entity_type: category_entity_type(row),
        resource_id: row.id,
        kind: if(kind == "company", do: :company, else: :internal)
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

  defp load_data(socket) do
    month = socket.assigns.params.month
    date_range_from = Date.beginning_of_month(month)
    date_range_to = Date.end_of_month(month)
    tag_filters = socket.assigns.tag_filters
    scope = socket.assigns.ash_scope

    totals =
      Analysis.get_organization_totals(
        date_range_from,
        date_range_to,
        [tag_filters: tag_filters],
        scope
      )

    socket
    |> assign(:income_categories, totals.income_categories)
    |> assign(:expense_categories, totals.expense_categories)
    |> assign(:transactions, totals.transactions)
    |> assign(:sales_invoices, totals.sales_invoices)
    |> assign(:cost_invoices, totals.cost_invoices)
  end

  defp build_path(socket, overrides) do
    month = Keyword.get(overrides, :month, socket.assigns.params.month)
    tag_filters = Keyword.get(overrides, :tag_filters, socket.assigns.tag_filters)

    Navigation.dashboard_path(month, tag_filters)
  end

  @doc false
  def tag_filter_active?(tag_filters, filter) do
    filter in tag_filters
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="analysis-dashboard" class="mx-auto w-full max-w-7xl py-4">
      <div class="mb-8 flex flex-wrap items-center justify-between gap-4">
        <div>
          <h1 class="text-grey-900 text-3xl font-semibold">
            {pgettext("main navigation", "Analysis")}
          </h1>
          <p class="text-darkGrey mt-2 text-sm">{gettext("Income and expenses by project")}</p>
        </div>
        <div class="flex items-center gap-3">
          <FirmowidWeb.DesignSystem.Components.Button.button
            :if={
              flag_enabled?(:analysis_dashboard, assigns) and
                @ash_scope.actor.role in [:admin, :accountant]
            }
            id="assign-unassigned"
            variant="secondary"
            type="button"
            phx-click="assign-unassigned"
            phx-disable-with={gettext("Assign unassigned")}
          >
            {gettext("Assign unassigned")}
          </FirmowidWeb.DesignSystem.Components.Button.button>
          <div class="relative">
            <FirmowidWeb.DesignSystem.Components.Button.button
              id="tag-filter-trigger"
              variant="secondary"
              type="button"
              phx-click={show_popover("tag-filter-popover")}
            >
              <Lucideicons.tag />
              {gettext("Categories")}
              <span :if={@tag_filters != []}>({length(@tag_filters)})</span>
            </FirmowidWeb.DesignSystem.Components.Button.button>
            <.popover
              id="tag-filter-popover"
              reference_id="tag-filter-trigger"
              placement="bottom-end"
              class="bg-grey-50 border-grey-200 w-64 rounded-lg border"
            >
              <div class="max-h-80 overflow-y-auto p-1">
                <label class="flex cursor-pointer items-center gap-2 rounded px-2 py-1.5 text-sm hover:bg-orange-100">
                  <input
                    type="checkbox"
                    checked={tag_filter_active?(@tag_filters, {:company})}
                    phx-click="toggle-tag"
                    phx-value-tag="firma"
                    class="border-darkGrey size-4 rounded-[3px] border"
                  />
                  <span
                    class="size-2.5 shrink-0 rounded-full"
                    style={"background-color: #{@category_colors.company}"}
                    aria-hidden="true"
                  />
                  {gettext("Company")}
                </label>
                <label
                  :for={tag_def <- @tag_definitions}
                  class="flex cursor-pointer items-center gap-2 rounded px-2 py-1.5 text-sm hover:bg-orange-100"
                >
                  <input
                    type="checkbox"
                    checked={tag_filter_active?(@tag_filters, {:project, tag_def.id})}
                    phx-click="toggle-tag"
                    phx-value-tag={"projekt:#{tag_def.id}"}
                    class="border-darkGrey size-4 rounded-[3px] border"
                  />
                  <span
                    class="size-2.5 shrink-0 rounded-full"
                    style={"background-color: #{Map.fetch!(@category_colors, {:project, tag_def.id})}"}
                    aria-hidden="true"
                  />
                  <span class="text-darkGrey truncate">{tag_def.name}</span>
                </label>
                <FirmowidWeb.DesignSystem.Components.Button.button
                  :if={@tag_filters != []}
                  id="clear-tag-filters"
                  type="button"
                  variant="unstyled"
                  phx-click="clear-tag-filters"
                  class="text-darkGrey mt-1 w-full border-t p-2 text-sm"
                >
                  {gettext("Clear filters")}
                </FirmowidWeb.DesignSystem.Components.Button.button>
              </div>
            </.popover>
          </div>
          <.month_picker id="month" active_months={@active_months} selected_date={@params.month} />
        </div>
      </div>
      <div class="grid grid-cols-1 gap-6 lg:grid-cols-2">
        <.chart
          id="income-chart"
          title={gettext("Income")}
          categories={@income_categories}
          colors={@category_colors}
          section="income"
          active={@expanded_section == :income}
        />
        <.chart
          id="expense-chart"
          title={gettext("Expenses")}
          categories={@expense_categories}
          colors={@category_colors}
          section="expenses"
          active={@expanded_section == :expenses}
        />
      </div>
      <p class="text-darkGrey mt-4 text-sm">
        {gettext("Selected projects share the amount equally.")}
      </p>
      <section id="analysis-entries" class="mt-8">
        <h2 class="text-darkGrey text-lg font-medium">
          {if @expanded_section == :income,
            do: gettext("Income entries"),
            else: gettext("Expense entries")}
        </h2>
        <p :if={@tag_filters != []} class="text-darkGrey mt-1 text-sm">
          {gettext(
            "The list shows full document amounts; the charts show the selected projects' shares."
          )}
        </p>
        <div class="overflow-x-auto">
          <FirmowidWeb.Analysis.Components.EntriesTable.table
            entries={entries_for_section(assigns)}
            categories={@categories}
            colors={@category_colors}
            can_write={
              flag_enabled?(:analysis_dashboard, assigns) and
                @ash_scope.actor.role in [:admin, :accountant]
            }
          />
        </div>
      </section>
    </div>
    """
  end
end
