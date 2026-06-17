defmodule Firmowid.Ash.Invoicing.SalesInvoice.Scanners.OverdueReminders do
  @moduledoc """
  Scans overdue sales invoices and dispatches reminder events for eligible invoices.
  """

  use Ash.Resource.Actions.Implementation

  alias Firmowid.Ash.Invoicing.SalesInvoice
  alias Firmowid.Ash.Invoicing.SalesInvoice.Dispatchers.Communication
  alias Firmowid.Ash.Scope
  alias Firmowid.Ash.SystemActor

  require Ash.Query
  require Logger

  @batch_size 100

  @doc false
  @impl true
  @spec run(Ash.ActionInput.t(), Keyword.t(), Ash.Resource.Actions.Implementation.Context.t()) ::
          {:ok, non_neg_integer()}
  def run(_input, _opts, context) do
    organization_id = context.tenant

    scope = %Scope{
      actor: %SystemActor{org_id: organization_id, role: :sales_invoice_processor},
      tenant: organization_id
    }

    Logger.info("Overdue sales invoice reminder scan started org=#{organization_id}")

    result =
      process_batches(scope, Date.utc_today(), nil, %{
        events_created: 0,
        invoices_skipped: 0,
        invoices_failed: 0
      })

    Logger.info(
      "Overdue sales invoice reminder scan finished org=#{organization_id} events_created=#{result.events_created} " <>
        "invoices_skipped=#{result.invoices_skipped} invoices_failed=#{result.invoices_failed}"
    )

    {:ok, result.events_created}
  end

  defp process_batches(scope, today, cursor, totals) do
    invoices = overdue_candidates(scope, today, cursor)

    if invoices == [] do
      totals
    else
      latest_invoice_ids = latest_invoice_ids_for_batch(invoices, scope)
      batch_totals = process_batch(invoices, latest_invoice_ids, scope)
      last_invoice = List.last(invoices)

      totals = %{
        events_created: totals.events_created + batch_totals.events_created,
        invoices_skipped: totals.invoices_skipped + batch_totals.invoices_skipped,
        invoices_failed: totals.invoices_failed + batch_totals.invoices_failed
      }

      process_batches(scope, today, {last_invoice.inserted_at, last_invoice.id}, totals)
    end
  end

  defp overdue_candidates(scope, today, cursor) do
    SalesInvoice
    |> overdue_candidate_query(today, cursor)
    |> Ash.Query.sort(inserted_at: :asc, id: :asc)
    |> Ash.Query.limit(@batch_size)
    |> Ash.read!(scope: scope)
  end

  defp overdue_candidate_query(query, today, nil) do
    Ash.Query.filter(
      query,
      not is_nil(invoice_number) and
        not is_nil(ksef_number) and
        not is_nil(due_date) and
        due_date < ^today and
        skip_invoicing == false and
        not exists(transactions, true)
    )
  end

  defp overdue_candidate_query(query, today, {inserted_at, id}) do
    Ash.Query.filter(
      query,
      not is_nil(invoice_number) and
        not is_nil(ksef_number) and
        not is_nil(due_date) and
        due_date < ^today and
        skip_invoicing == false and
        not exists(transactions, true) and
        (inserted_at > ^inserted_at or (inserted_at == ^inserted_at and id > ^id))
    )
  end

  defp latest_invoice_ids_for_batch(invoices, scope) do
    root_ids = Enum.uniq(Enum.map(invoices, &(&1.corrected_invoice_id || &1.id)))

    SalesInvoice
    |> Ash.Query.filter(id in ^root_ids or corrected_invoice_id in ^root_ids)
    |> Ash.read!(scope: scope)
    |> Enum.group_by(&(&1.corrected_invoice_id || &1.id))
    |> Map.new(fn {root_id, chain} ->
      latest_invoice =
        chain
        |> Enum.sort_by(&{datetime_sort_value(&1.locked_at), datetime_sort_value(&1.inserted_at)})
        |> List.last()

      {root_id, latest_invoice.id}
    end)
    |> Map.values()
    |> MapSet.new()
  end

  defp process_batch(invoices, latest_invoice_ids, scope) do
    Enum.reduce(
      invoices,
      %{events_created: 0, invoices_skipped: 0, invoices_failed: 0},
      fn invoice, totals ->
        if MapSet.member?(latest_invoice_ids, invoice.id) do
          case Communication.dispatch(invoice, :overdue_reminder, scope) do
            {:ok, :dispatched} -> %{totals | events_created: totals.events_created + 1}
            {:ok, :skipped} -> %{totals | invoices_skipped: totals.invoices_skipped + 1}
            {:error, _reason} -> %{totals | invoices_failed: totals.invoices_failed + 1}
          end
        else
          %{totals | invoices_skipped: totals.invoices_skipped + 1}
        end
      end
    )
  end

  defp datetime_sort_value(nil), do: 9_999_999_999_999_999
  defp datetime_sort_value(%DateTime{} = value), do: DateTime.to_unix(value, :microsecond)

  defp datetime_sort_value(%NaiveDateTime{} = value),
    do: DateTime.to_unix(DateTime.from_naive!(value, "Etc/UTC"), :microsecond)
end
