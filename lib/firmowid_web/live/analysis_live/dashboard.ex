defmodule FirmowidWeb.AnalysisLive.Dashboard do
  @moduledoc false
  use FirmowidWeb, :live_view

  alias Firmowid.Analysis

  @impl true
  def mount(_params, _session, socket) do
    Bodyguard.permit!(Analysis, :read, socket.assigns.current_user)

    active_months =
      Analysis.get_months_with_entries() ++
        [Date.utc_today()]

    tag_definitions = Analysis.list_tag_definitions()

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
  def handle_event("select-section", %{"section" => section}, socket) do
    {:noreply, assign(socket, :expanded_section, String.to_existing_atom(section))}
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
    kind = String.to_existing_atom(kind)
    Analysis.set_entity_category(String.to_existing_atom(type), id, kind)
    {:noreply, load_data(socket)}
  end

  @impl true
  def handle_event("clear-entity-tags", %{"entity_type" => type, "entity_id" => id}, socket) do
    Analysis.clear_entity_tags(String.to_existing_atom(type), id)
    {:noreply, load_data(socket)}
  end

  @impl true
  def handle_event("toggle-project-tag", params, socket) do
    %{"entity_type" => type, "entity_id" => id, "tag_definition_id" => tag_def_id} = params
    entity_type = String.to_existing_atom(type)

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

    Analysis.set_entity_project_tags(entity_type, id, updated_ids)
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

    totals = Analysis.get_organization_totals(date_range_from, date_range_to, tag_filters: tag_filters)

    socket
    |> assign(:total_income, totals.total_income)
    |> assign(:total_expenses, totals.total_expenses)
    |> assign(:net_profit, totals.net_profit)
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

  # Parses tag filters from URL query params.
  # Tags are stored as `tags=company,project:<id>,project:<id>`.
  defp parse_tag_filters(%{"tags" => tags_param}, tag_definitions) when is_binary(tags_param) do
    valid_project_ids = MapSet.new(tag_definitions, & &1.id)

    tags_param
    |> String.split(",", trim: true)
    |> Enum.map(&decode_tag_key/1)
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
end
