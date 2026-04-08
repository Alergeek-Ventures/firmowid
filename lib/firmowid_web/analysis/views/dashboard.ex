defmodule FirmowidWeb.Analysis.Views.Dashboard do
  @moduledoc """
  LiveView for the financial analysis dashboard.

  Displays monthly income, expenses, and net profit with tag-based filtering.
  URL params control the active month (`?month=YYYY-MM-DD`) and tag filters
  (`?tags=company,project:<id>`).
  """
  use FirmowidWeb, :live_view

  alias Firmowid.Ash.Analysis
  alias Firmowid.Ash.Analysis.EntityTag
  alias Firmowid.Ash.Analysis.TagDefinition

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
    month =
      case Map.get(params, "month") do
        nil -> Date.beginning_of_month(Date.utc_today())
        date_string -> Date.from_iso8601!(date_string)
      end

    tag_filters = parse_tag_filters(params, socket.assigns.tag_definitions)

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
    filter = decode_tag_key(tag_key)

    updated =
      if filter in current do
        List.delete(current, filter)
      else
        [filter | current]
      end

    {:noreply, push_patch(socket, to: build_path(socket, tag_filters: updated))}
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
      Enum.filter(assigns.transactions, &Decimal.positive?(&1.transaction_amount))
  end

  defp entries_for_section(%{expanded_section: :expenses} = assigns) do
    assigns.cost_invoices ++
      Enum.filter(assigns.transactions, &Decimal.negative?(&1.transaction_amount))
  end

  defp entries_for_section(_assigns), do: []

  defp load_data(socket) do
    month = socket.assigns.params.month
    date_range_from = Date.beginning_of_month(month)
    date_range_to = Date.end_of_month(month)
    tag_filters = socket.assigns.tag_filters
    scope = socket.assigns.ash_scope

    totals =
      Analysis.get_organization_totals(date_range_from, date_range_to, [tag_filters: tag_filters], scope)

    socket
    |> assign(:total_income, totals.total_income)
    |> assign(:total_expenses, totals.total_expenses)
    |> assign(:net_profit, totals.net_profit)
    |> assign(:profitable?, Decimal.positive?(totals.net_profit))
    |> assign(:transactions, totals.transactions)
    |> assign(:sales_invoices, totals.sales_invoices)
    |> assign(:cost_invoices, totals.cost_invoices)
  end

  # ---------------------------------------------------------------------------
  # URL param helpers for tag filters
  # ---------------------------------------------------------------------------

  # Encodes a tag filter tuple into a URL-safe string key.
  defp encode_tag_key({:company}), do: "company"
  defp encode_tag_key({:project, id}), do: "project:#{id}"

  # Decodes a URL string key back into a tag filter tuple.
  defp decode_tag_key("company"), do: {:company}

  defp decode_tag_key("project:" <> id), do: {:project, id}

  defp decode_tag_key(_), do: :invalid

  # Parses tag filters from URL query params.
  # Tags are stored as `tags=company,project:<id>,project:<id>`.
  defp parse_tag_filters(%{"tags" => tags_param}, tag_definitions) when is_binary(tags_param) do
    valid_project_ids = MapSet.new(tag_definitions, & &1.id)

    tags_param
    |> String.split(",", trim: true)
    |> Enum.map(&decode_tag_key/1)
    |> Enum.reject(&(&1 == :invalid))
    |> Enum.filter(fn
      {:company} -> true
      {:project, id} -> MapSet.member?(valid_project_ids, id)
    end)
  end

  defp parse_tag_filters(_params, _tag_definitions), do: []

  # Builds a path with current assigns, overriding specific params.
  defp build_path(socket, overrides) do
    month = Keyword.get(overrides, :month, socket.assigns.params.month)
    tag_filters = Keyword.get(overrides, :tag_filters, socket.assigns.tag_filters)

    query_params = %{month: Date.to_iso8601(month)}

    query_params =
      case tag_filters do
        [] ->
          query_params

        filters ->
          tags_value = Enum.map_join(filters, ",", &encode_tag_key/1)
          Map.put(query_params, :tags, tags_value)
      end

    ~p"/analiza?#{query_params}"
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
    <button
      phx-click="select-section"
      phx-value-section={@section}
      class={[
        "cursor-pointer rounded-lg border-2 p-6 text-left transition-all duration-200",
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
    </button>
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
