defmodule Firmowid.Ash.Finances.TransactionQueries do
  @moduledoc """
  Raw Ecto query helpers for complex Transaction reads and seed-only writes.

  Extracted from `Firmowid.Finances` to keep the Ash resource module focused
  on DSL declarations. The read helpers use raw Ecto because:

  - ParadeDB `~>` operator and `pdb.score()` ordering aren't expressible in Ash
  - `NOT EXISTS` subqueries against un-migrated join tables (CostInvoicesTransactions,
    SalesInvoicesTransactions) need direct Ecto access
  - Preloads reference associations defined on the legacy Ecto schema

  The `create_or_update/1` write function is retained for seed scripts only —
  production callers use the Ash `:bulk_upsert_from_sync` action.

  All functions assume `Repo.put_org_id/1` has been called by the generic
  action's `run` callback before invocation (the standard bridge pattern).

  Uses the legacy `Firmowid.Finances.Transaction` Ecto schema for queries
  that need `many_to_many` associations to cost/sales invoice join tables.
  When those contexts migrate to Ash, these queries can switch to Ash reads
  with proper relationships.

  Modules calling these helpers directly (rather than through Ash generic actions)
  set `Repo.put_org_id/1` themselves and bypass Ash policies/multitenancy.
  This is migration debt to be resolved when the invoice contexts move to Ash.
  """
  import Ecto.Query, warn: false
  import Paradex, only: [~>: 2]

  alias Firmowid.Ash.Finances
  alias Firmowid.CostInvoices.CostInvoicesTransactions
  alias Firmowid.Finances.Transaction
  alias Firmowid.Repo
  alias Firmowid.SalesInvoices.SalesInvoicesTransactions

  # ── Public API ────────────────────────────────────────────────────────

  @doc """
  Bulk upsert transactions from raw maps via Ecto `insert_all`.

  Generates UUIDv7 IDs and timestamps, then uses `Repo.insert_all` with
  `on_conflict` to update everything except `:id`, `:skip_invoicing`, and
  `:inserted_at`. Broadcasts a single transaction_list_updated after completion.

  **Seed-only.** Production callers should use the Ash `:bulk_upsert_from_sync`
  action instead. This function is retained because seed data includes
  `:skip_invoicing` values that the Ash upsert action intentionally excludes
  from its `accept` list.
  """
  @spec create_or_update(list(map())) :: :ok
  def create_or_update(transactions) do
    now = DateTime.truncate(DateTime.utc_now(), :second)

    transactions =
      Enum.map(transactions, fn transaction ->
        Map.merge(transaction, %{
          id: UUIDv7.generate(),
          inserted_at: now,
          updated_at: now
        })
      end)

    Repo.insert_all(Transaction, transactions,
      on_conflict: {:replace_all_except, [:id, :skip_invoicing, :inserted_at]},
      conflict_target: [:internal_transaction_id, :organization_id]
    )

    case List.first(transactions) do
      nil ->
        :ok

      transaction ->
        organization_id = Map.get(transaction, :organization_id)
        Finances.broadcast_transaction_list_updated(organization_id)
        :ok
    end
  end

  @doc """
  Lists transactions within a date range, ordered by booking_date desc.
  Preloads cost and sales invoice transaction join records.
  """
  @spec list_by_date_range(Date.t(), Date.t()) :: [Transaction.t()]
  def list_by_date_range(date_from, date_to) do
    from(t in Transaction,
      where: t.booking_date >= ^date_from and t.booking_date <= ^date_to,
      order_by: [desc: t.booking_date]
    )
    |> Repo.all()
    |> Repo.preload([:cost_invoices_transactions, :sales_invoices_transactions])
  end

  @doc """
  Lists transactions not matched to any invoice and not skipped,
  within a date range. Uses LEFT JOIN + IS NULL for unmatched detection.
  Preloads cost and sales invoice transaction join records.
  """
  @spec list_unmatched(Date.t(), Date.t()) :: [Transaction.t()]
  def list_unmatched(date_from, date_to) do
    from(t in Transaction,
      left_join: ci in assoc(t, :cost_invoices_transactions),
      left_join: si in assoc(t, :sales_invoices_transactions),
      where: t.skip_invoicing == false,
      where: is_nil(ci.id),
      where: is_nil(si.id),
      where: t.booking_date >= ^date_from and t.booking_date <= ^date_to,
      order_by: [desc: t.booking_date]
    )
    |> Repo.all()
    |> Repo.preload([:cost_invoices_transactions, :sales_invoices_transactions])
  end

  @doc """
  Lists transactions with skip_invoicing=true within a date range.
  """
  @spec list_skipped(Date.t(), Date.t()) :: [Transaction.t()]
  def list_skipped(date_from, date_to) do
    Transaction
    |> where([t], t.booking_date >= ^date_from and t.booking_date <= ^date_to)
    |> where([t], t.skip_invoicing == true)
    |> Repo.all()
  end

  @doc """
  Lists transactions that are skipped AND not matched to any invoice
  (neither sales nor cost). Used by Analysis to avoid double-counting:
  if a transaction is matched to an invoice, only the invoice amount
  is counted.
  """
  @spec list_skipped_unmatched(Date.t(), Date.t()) :: [Transaction.t()]
  def list_skipped_unmatched(date_from, date_to) do
    sales_match_query =
      from(sit in SalesInvoicesTransactions,
        where: sit.transaction_id == parent_as(:transaction).id
      )

    cost_match_query =
      from(cit in CostInvoicesTransactions,
        where: cit.transaction_id == parent_as(:transaction).id
      )

    Transaction
    |> from(as: :transaction)
    |> where([t], t.booking_date >= ^date_from and t.booking_date <= ^date_to)
    |> where([t], t.skip_invoicing == true)
    |> where([t], not exists(subquery(sales_match_query)))
    |> where([t], not exists(subquery(cost_match_query)))
    |> Repo.all()
  end

  @doc """
  Full-text search using ParadeDB with optional filters.

  Supports:
  - `:query` — ParadeDB `~>` text search across debtor_name, creditor_name,
    remittance_information_unstructured, transaction_currency
  - `:only_unmatched` — filter to transactions not linked to any invoice (default true)
  - `:currency`, `:amount_gt`, `:amount_lt` — value filters
  - `:date_from`, `:date_to` — date range (matches on booking_date OR value_date)

  When a search query is provided, results are ordered by ParadeDB relevance
  score; otherwise by booking_date descending. Limited to 50 results.
  """
  @spec search(map()) :: [Transaction.t()]
  def search(params \\ %{}) do
    from(Transaction, as: :transaction)
    |> preload([:cost_invoices_transactions, :sales_invoices_transactions])
    |> maybe_filter_unmatched(Map.get(params, :only_unmatched, true))
    |> maybe_filter(:currency, Map.get(params, :currency))
    |> maybe_filter(:amount_gt, Map.get(params, :amount_gt))
    |> maybe_filter(:amount_lt, Map.get(params, :amount_lt))
    |> maybe_filter(:date_from, Map.get(params, :date_from))
    |> maybe_filter(:date_to, Map.get(params, :date_to))
    |> maybe_search_transactions(Map.get(params, :query))
    |> limit(50)
    |> Repo.all()
  end

  @doc """
  Fetches transactions by a list of IDs. Returns raw structs — callers
  load the `:amount` calculation explicitly when they need the Money struct.
  """
  @spec get_by_ids([Ecto.UUID.t()]) :: [Transaction.t()]
  def get_by_ids(ids) do
    Transaction
    |> where([t], t.id in ^ids)
    |> Repo.all()
  end

  # ── Private helpers ───────────────────────────────────────────────────

  defp maybe_filter_unmatched(query, false), do: query

  defp maybe_filter_unmatched(query, _) do
    query
    |> where(
      [t],
      from(ci in CostInvoicesTransactions,
        where: parent_as(:transaction).id == ci.transaction_id
      )
      |> union(
        ^from(si in SalesInvoicesTransactions,
          where: parent_as(:transaction).id == si.transaction_id
        )
      )
      |> exists() == false
    )
    |> where([t], t.skip_invoicing == false)
  end

  defp maybe_filter(query, _field, nil), do: query

  defp maybe_filter(query, :currency, val) do
    where(query, [t], t.transaction_currency == ^val)
  end

  defp maybe_filter(query, :amount_gt, val) do
    where(query, [t], t.transaction_amount >= ^val)
  end

  defp maybe_filter(query, :amount_lt, val) do
    where(query, [t], t.transaction_amount <= ^val)
  end

  defp maybe_filter(query, :date_from, val) do
    where(query, [t], t.booking_date >= ^val or t.value_date >= ^val)
  end

  defp maybe_filter(query, :date_to, val) do
    where(query, [t], t.booking_date <= ^val or t.value_date <= ^val)
  end

  defp maybe_search_transactions(query, nil) do
    order_by(query, [t], desc: t.booking_date)
  end

  defp maybe_search_transactions(query, search) do
    query
    |> where(
      [t],
      t.debtor_name ~> ^search or
        t.creditor_name ~> ^search or
        t.remittance_information_unstructured ~> ^search or
        t.transaction_currency ~> ^search
    )
    |> order_by([t], fragment("pdb.score(?) DESC", t.id))
  end
end
