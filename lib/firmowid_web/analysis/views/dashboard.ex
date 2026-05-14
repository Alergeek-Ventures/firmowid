defmodule FirmowidWeb.Analysis.Views.Dashboard do
  @moduledoc """
  LiveView for the financial analysis dashboard.

  Displays monthly income, expenses, and net profit with tag-based filtering.
  URL params control the active month (`?miesiac=YYYY-MM-DD`) and tag filters
  (`?tagi=firma,projekt:<id>`).
  """
  use FirmowidWeb, :live_view

  import FirmowidWeb.DesignSystem.Components.MonthPicker

  alias Firmowid.Ash.Analysis
  alias Firmowid.Ash.Analysis.EntityTag
  alias Firmowid.Ash.Analysis.TagDefinition
  alias FirmowidWeb.Analysis.Utilities.Navigation
  alias FirmowidWeb.Infrastructure.Utilities.QueryParams

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.ash_scope

    active_months =
      Analysis.get_months_with_entries(scope) ++
        [Date.utc_today()]

    tag_definitions = TagDefinition.list_tag_definitions!(scope: scope)

    socket =
      socket
      |> assign(:active_months, active_months)
      |> assign(:tag_definitions, tag_definitions)
      |> assign(:expanded_section, :income)

    {:ok, assign(socket, page_title: "Analiza finansowa")}
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

  # Tag assignment events (from per-row tag selector in entries table)

  @impl true
  def handle_event("set-entity-category", %{"entity_type" => type, "entity_id" => id, "kind" => kind}, socket) do
    entity_type = cast_entity_type!(type)
    kind = cast_entity_kind!(kind)
    scope = socket.assigns.ash_scope

    EntityTag.set_entity_category!(%{entity_type: entity_type, resource_id: id, kind: kind},
      scope: scope
    )

    {:noreply, load_data(socket)}
  end

  @impl true
  def handle_event("clear-entity-tags", %{"entity_type" => type, "entity_id" => id}, socket) do
    scope = socket.assigns.ash_scope

    EntityTag.clear_entity_tags!(%{entity_type: cast_entity_type!(type), resource_id: id},
      scope: scope
    )

    {:noreply, load_data(socket)}
  end

  @impl true
  def handle_event("toggle-project-tag", params, socket) do
    %{"entity_type" => type, "entity_id" => id, "tag_definition_id" => tag_def_id} = params
    entity_type = cast_entity_type!(type)
    scope = socket.assigns.ash_scope

    # Find the current entity in assigns and compute toggled project tag IDs
    current_tags = find_entity_tags(socket.assigns, entity_type, id)

    current_project_ids =
      current_tags
      |> Enum.filter(&(&1.kind == :project))
      |> Enum.map(& &1.tag_definition_id)

    updated_ids =
      if tag_def_id in current_project_ids do
        List.delete(current_project_ids, tag_def_id)
      else
        [tag_def_id | current_project_ids]
      end

    EntityTag.set_entity_project_tags!(
      %{entity_type: entity_type, resource_id: id, tag_definition_ids: updated_ids},
      scope: scope
    )

    {:noreply, load_data(socket)}
  end

  defp entries_for_section(%{expanded_section: :income} = assigns) do
    assigns.sales_invoices ++
      Enum.filter(assigns.transactions, &Money.positive?(&1.amount))
  end

  defp entries_for_section(%{expanded_section: :expenses} = assigns) do
    assigns.cost_invoices ++
      Enum.filter(assigns.transactions, &Money.negative?(&1.amount))
  end

  defp entries_for_section(_assigns), do: []

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
    |> assign(:total_income, totals.total_income)
    |> assign(:total_expenses, totals.total_expenses)
    |> assign(:net_profit, totals.net_profit)
    |> assign(:profitable?, Decimal.positive?(totals.net_profit))
    |> assign(:transactions, totals.transactions)
    |> assign(:sales_invoices, totals.sales_invoices)
    |> assign(:cost_invoices, totals.cost_invoices)
  end

  defp build_path(socket, overrides) do
    month = Keyword.get(overrides, :month, socket.assigns.params.month)
    tag_filters = Keyword.get(overrides, :tag_filters, socket.assigns.tag_filters)

    Navigation.dashboard_path(month, tag_filters)
  end

  # Finds entity_tags for a specific entity from the current assigns.
  defp find_entity_tags(assigns, entity_type, entity_id) do
    entity =
      case entity_type do
        :sales_invoice -> Enum.find(assigns.sales_invoices, &(&1.id == entity_id))
        :cost_invoice -> Enum.find(assigns.cost_invoices, &(&1.id == entity_id))
        :transaction -> Enum.find(assigns.transactions, &(&1.id == entity_id))
      end

    if entity, do: Map.get(entity, :entity_tags, []), else: []
  end

  @doc false
  def tag_filter_active?(tag_filters, filter) do
    filter in tag_filters
  end

  defp summary_card(assigns) do
    ~H"""
    <FirmowidWeb.DesignSystem.Components.Button.button
      phx-click="select-section"
      type="button"
      variant="unstyled"
      phx-value-section={@section}
      class={[
        "block w-full cursor-pointer rounded-lg border-2 p-6 text-left transition-all duration-200",
        if(@active, do: "#{@active_border} ring-2 #{@ring}", else: "#{@border} #{@hover_border}"),
        @bg,
        @text
      ]}
    >
      <div class="flex items-center">
        <div class="shrink-0">
          <.icon name={@icon} class={["size-8", @text]} />
        </div>
        <div class="ml-4">
          <p class={["text-sm font-medium", @text]}>{@label}</p>
          <p class={["text-2xl font-bold", @text]}>
            {Money.new(:PLN, @amount)}
          </p>
        </div>
      </div>
    </FirmowidWeb.DesignSystem.Components.Button.button>
    """
  end

  # Casts browser-supplied entity type strings to known atoms.
  defp cast_entity_type!("sales_invoice"), do: :sales_invoice
  defp cast_entity_type!("cost_invoice"), do: :cost_invoice
  defp cast_entity_type!("transaction"), do: :transaction

  # Casts browser-supplied entity kind strings to known atoms.
  defp cast_entity_kind!("company"), do: :company
  defp cast_entity_kind!("internal"), do: :internal
end
