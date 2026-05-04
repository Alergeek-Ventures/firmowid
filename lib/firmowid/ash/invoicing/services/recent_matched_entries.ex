defmodule Firmowid.Ash.Invoicing.Services.RecentMatchedEntries do
  @moduledoc """
  Builds the dashboard read model for recently matched invoice entries.

  This service keeps event-log querying and invoice loading in the invoicing
  domain, so LiveViews can stay focused on params and assigns.
  """

  alias Firmowid.Ash.Events
  alias Firmowid.Ash.Events.Decoder
  alias Firmowid.Ash.Events.Event
  alias Firmowid.Ash.Invoicing
  alias Firmowid.Ash.Invoicing.CostInvoice
  alias Firmowid.Ash.Invoicing.SalesInvoice
  alias Firmowid.Ash.Scope

  require Ash.Query

  @default_limit 5

  @type matched_entry :: %{
          entry: CostInvoice.t() | SalesInvoice.t(),
          matched_at: NaiveDateTime.t(),
          match_confidence: float() | nil,
          match_source: atom() | nil
        }

  @type list_result :: %{
          entries: [matched_entry()],
          total_count: non_neg_integer()
        }

  @doc """
  Returns recently matched invoice entries for the dashboard.

  The result is derived from the latest connect/disconnect event per invoice in
  the current organization, filtered to connections that happened inside the
  provided date range.
  """
  @spec list(Date.t(), Date.t(), Scope.t(), keyword()) :: list_result()
  def list(from, to, %Scope{} = scope, opts \\ []) do
    limit = Keyword.get(opts, :limit, @default_limit)
    cost_invoice_loads = Keyword.get(opts, :cost_invoice_loads, [])
    sales_invoice_loads = Keyword.get(opts, :sales_invoice_loads, [])

    {month_start, month_end} = month_range_as_naive_datetimes(from, to)

    matched_events =
      (latest_cost_invoice_match_events(scope) ++
         latest_sales_invoice_match_events(scope))
      |> Enum.filter(fn event ->
        event.action == :connect_transactions and
          NaiveDateTime.compare(event.occurred_at, month_start) != :lt and
          NaiveDateTime.compare(event.occurred_at, month_end) != :gt
      end)
      |> Enum.sort_by(& &1.occurred_at, {:desc, NaiveDateTime})

    cost_invoices_by_id =
      matched_events
      |> Enum.filter(&(&1.resource == :cost_invoice))
      |> Enum.map(& &1.record_id)
      |> load_cost_invoices_by_id(scope, cost_invoice_loads)

    sales_invoices_by_id =
      matched_events
      |> Enum.filter(&(&1.resource == :sales_invoice))
      |> Enum.map(& &1.record_id)
      |> load_sales_invoices_by_id(scope, sales_invoice_loads)

    matched_entries =
      matched_events
      |> Enum.map(fn event ->
        build_matched_entry(event, cost_invoices_by_id, sales_invoices_by_id)
      end)
      |> Enum.reject(&is_nil/1)

    %{
      entries: Enum.take(matched_entries, limit),
      total_count: length(matched_entries)
    }
  end

  defp latest_cost_invoice_match_events(scope) do
    list_match_events(CostInvoice, scope)
  end

  defp latest_sales_invoice_match_events(scope) do
    list_match_events(SalesInvoice, scope)
  end

  defp list_match_events(resource, scope) do
    query =
      Event
      |> Ash.Query.select([:record_id, :occurred_at, :resource, :action, :data, :metadata])
      |> Ash.Query.for_read(:read, %{}, scope: scope)
      |> Ash.Query.filter(
        resource == ^resource and
          action in [
            :connect_transactions,
            :disconnect_transactions,
            :disconnect_all_transactions
          ]
      )
      |> Ash.Query.sort(record_id: :asc, occurred_at: :desc)
      |> Ash.Query.distinct(:record_id)

    [scope: scope, query: query]
    |> Events.list_events!()
    |> Enum.flat_map(&decode_match_event/1)
  end

  defp build_matched_entry(event, cost_invoices_by_id, sales_invoices_by_id) do
    invoice =
      case event.resource do
        :cost_invoice -> Map.get(cost_invoices_by_id, event.record_id)
        :sales_invoice -> Map.get(sales_invoices_by_id, event.record_id)
      end

    case invoice do
      nil ->
        nil

      invoice ->
        %{match_confidence: confidence_score, match_source: source} = match_details(event)

        %{
          entry: invoice,
          matched_at: event.occurred_at,
          match_confidence: confidence_score,
          match_source: source
        }
    end
  end

  defp decode_match_event(raw_event) do
    case Decoder.decode(raw_event) do
      {:ok, typed_event} -> [typed_event]
      {:error, _reason} -> []
    end
  end

  defp match_details(%{payload: %Ash.Union{type: payload_type, value: payload}})
       when payload_type in [
              :cost_invoice_transactions_connected,
              :cost_invoice_transactions_disconnected,
              :sales_invoice_transactions_connected,
              :sales_invoice_transactions_disconnected
            ] do
    %{
      match_confidence: Map.get(payload, :confidence_score),
      match_source: Map.get(payload, :source)
    }
  end

  defp match_details(_event), do: %{match_confidence: nil, match_source: nil}

  defp load_cost_invoices_by_id([], _scope, _loads), do: %{}

  defp load_cost_invoices_by_id(ids, scope, loads) do
    %{ids: Enum.uniq(ids)}
    |> Invoicing.list_cost_invoices!(load: loads, scope: scope)
    |> Map.new(&{&1.id, &1})
  end

  defp load_sales_invoices_by_id([], _scope, _loads), do: %{}

  defp load_sales_invoices_by_id(ids, scope, loads) do
    %{ids: Enum.uniq(ids)}
    |> Invoicing.list_sales_invoices!(load: loads, scope: scope)
    |> Map.new(&{&1.id, &1})
  end

  defp month_range_as_naive_datetimes(from, to) do
    {
      NaiveDateTime.new!(from, ~T[00:00:00]),
      NaiveDateTime.new!(to, ~T[23:59:59.999999])
    }
  end
end
