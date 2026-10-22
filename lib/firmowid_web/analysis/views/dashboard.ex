defmodule FirmowidWeb.Analysis.Views.Dashboard do
  @moduledoc """
  LiveView for the financial analysis dashboard.

  Displays monthly income and expense pie charts with project-based filtering.
  URL params control the active month (`?miesiac=YYYY-MM-DD`) and tag filters
  (`?tagi=firma,projekt:<id>`).

  Without tag filters, the charts also show unrealized capital from the month:
  invoices without a linked payment and payments without an invoice or salary.
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

    categories =
      %{active_from: month, active_to: Date.end_of_month(month)}
      |> Project.list!(load: [:tag_definition], scope: socket.assigns.ash_scope)
      |> Enum.map(& &1.tag_definition)
      |> Enum.reject(&is_nil/1)
      |> Enum.sort_by(& &1.name)

    socket =
      socket
      |> assign(:params, %{month: month})
      |> assign(:categories, categories)
      |> assign(:tag_filters, tag_filters)
      |> assign(:expanded_section, :income)
      |> load_data()

    {:noreply, socket}
  end

  @impl true
  def handle_event(event, params, socket)
      when event in ["set-entity-category", "clear-entity-tags", "toggle-project-tag"] do
    row =
      Enum.find(
        socket.assigns.sales_invoices ++
          socket.assigns.cost_invoices ++ socket.assigns.transactions,
        fn row ->
          row.id == params["entity_id"] and
            Atom.to_string(category_entity_type(row)) == params["entity_type"]
        end
      )

    if can_write?(socket.assigns) and row != nil and category_editable?(row) do
      case change_category(event, params, row, socket) do
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
  def handle_info(:analysis_classification_updated, socket), do: {:noreply, load_totals(socket)}

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

  defp can_write?(assigns) do
    flag_enabled?(:analysis_dashboard, assigns) and
      assigns.ash_scope.actor.member.role in [:admin, :accountant]
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
    unrealized = socket.assigns.unrealized

    totals =
      Analysis.get_organization_totals(
        Date.beginning_of_month(month),
        Date.end_of_month(month),
        [tag_filters: tag_filters],
        socket.assigns.ash_scope
      )

    socket
    |> assign(
      :income_categories,
      with_unrealized(totals.income_categories, unrealized.income, tag_filters)
    )
    |> assign(
      :expense_categories,
      with_unrealized(totals.expense_categories, unrealized.expenses, tag_filters)
    )
    |> assign(:transactions, totals.transactions)
    |> assign(:sales_invoices, totals.sales_invoices)
    |> assign(:cost_invoices, totals.cost_invoices)
  end

  # Unrealized invoices have no categories, so project or company filters hide them.
  defp with_unrealized(categories, amount, []) do
    if Decimal.positive?(amount),
      do: categories ++ [%{key: :unrealized, name: nil, amount: amount}],
      else: categories
  end

  defp with_unrealized(categories, _amount, _tag_filters), do: categories

  defp unrealized_for_section(%{expanded_section: :income, unrealized: unrealized}), do: unrealized.income_entries

  defp unrealized_for_section(%{expanded_section: :expenses, unrealized: unrealized}), do: unrealized.expense_entries

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
          <h1 class="text-3xl font-semibold text-grey-900">
            {pgettext("main navigation", "Analysis")}
          </h1>
          <p class="mt-2 text-sm text-darkGrey">{gettext("Income and expenses by project")}</p>
        </div>
        <div class="flex items-center gap-3">
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
          <div class="relative">
            <FirmowidUI.Components.Button.button
              id="tag-filter-trigger"
              variant="secondary"
              type="button"
              phx-click={show_popover("tag-filter-popover")}
            >
              <Lucideicons.tag />
              {gettext("Categories")}
              <span :if={@tag_filters != []}>({length(@tag_filters)})</span>
            </FirmowidUI.Components.Button.button>
            <.popover
              id="tag-filter-popover"
              reference_id="tag-filter-trigger"
              placement="bottom-end"
              class="w-64 rounded-lg border border-grey-200 bg-grey-50"
            >
              <div class="max-h-80 overflow-y-auto p-1">
                <label class="flex cursor-pointer items-center gap-2 rounded px-2 py-1.5 text-sm hover:bg-orange-100">
                  <input
                    type="checkbox"
                    checked={tag_filter_active?(@tag_filters, {:company})}
                    phx-click="toggle-tag"
                    phx-value-tag="firma"
                    class="size-4 rounded-[3px] border border-darkGrey"
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
                    class="size-4 rounded-[3px] border border-darkGrey"
                  />
                  <span
                    class="size-2.5 shrink-0 rounded-full"
                    style={"background-color: #{Map.fetch!(@category_colors, {:project, tag_def.id})}"}
                    aria-hidden="true"
                  />
                  <span class="truncate text-darkGrey">{tag_def.name}</span>
                </label>
                <FirmowidUI.Components.Button.button
                  :if={@tag_filters != []}
                  id="clear-tag-filters"
                  type="button"
                  variant="unstyled"
                  phx-click="clear-tag-filters"
                  class="mt-1 w-full border-t p-2 text-sm text-darkGrey"
                >
                  {gettext("Clear filters")}
                </FirmowidUI.Components.Button.button>
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
      <section id="analysis-entries" class="mt-8">
        <p :if={@tag_filters != []} class="text-sm text-darkGrey">
          {gettext(
            "The list shows full document amounts; the charts show the selected projects' shares."
          )}
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
        class="mt-8"
      >
        <h2 class="text-lg font-medium text-darkGrey">
          {if @expanded_section == :income,
            do: gettext("Unrealized income"),
            else: gettext("Unrealized expenses")}
        </h2>
        <p class="mt-1 text-sm text-darkGrey">
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
    </div>
    """
  end
end
