# Phase 8: Move Invoicing Context

## Goal

Move functions from `lib/firmowid/invoicing.ex` to Ash-native locations and delete
the legacy context.

## Current state of invoicing.ex

Already uses Ash resources heavily. The Ecto schema references are minimal:
- `EctoSalesInvoice` in search queries and months query
- `EctoCostInvoice` in search queries and months query
- `EctoTransaction` in months query

Since Ash resources ARE Ecto schemas, we can swap references directly.

## Target locations

| Function | Target |
|----------|--------|
| `search_invoices/1` | `lib/firmowid/ash/invoicing/search.ex` |
| `get_all_months_with_invoicing_entries/0` | `lib/firmowid/ash/invoicing/entries.ex` |
| `get_invoicing_entries/3` | `lib/firmowid/ash/invoicing/entries.ex` |
| `order_entries_for_display/1` | `lib/firmowid/ash/invoicing/entries.ex` |
| `get_potential_transactions_for_invoice/1` | `lib/firmowid/ash/invoicing/matching.ex` |
| `match_cost_invoices/1` | `lib/firmowid/ash/invoicing/matching.ex` |
| `match_cost_invoice/2` | `lib/firmowid/ash/invoicing/matching.ex` |
| `match_sales_invoices/1` | `lib/firmowid/ash/invoicing/matching.ex` |
| `match_sales_invoice/2` | `lib/firmowid/ash/invoicing/matching.ex` |
| `score_and_sort_transactions/2` | `lib/firmowid/ash/invoicing/matching.ex` |
| `subscribe_invoicing_broadcast/1` | `lib/firmowid/ash/invoicing/matching.ex` |
| `broadcast_cost_invoice_match/3` | `lib/firmowid/ash/invoicing/matching.ex` |
| Bodyguard `authorize/3` | Removed (Ash policies) |

## search.ex

```elixir
defmodule Firmowid.Ash.Invoicing.Search do
  @moduledoc "ParadeDB full-text search across sales and cost invoices."

  import Ecto.Query, warn: false

  alias Firmowid.Ash.Invoicing.CostInvoice
  alias Firmowid.Ash.Invoicing.SalesInvoice
  alias Firmowid.Repo

  # Same logic as current invoicing.ex search_invoices/1
  # Replace EctoSalesInvoice → SalesInvoice, EctoCostInvoice → CostInvoice
  # These work because Ash resources are Ecto schemas
end
```

**Note:** The search uses raw Ecto queries with ParadeDB `&&&` operator and `pdb.score()`.
This is not easily expressible in Ash's query DSL. Keep as raw Ecto queries but on
Ash resource modules. This is an acceptable pattern for specialized search.

The `hydrate_search_results/1` function currently hydrates cost invoices via Ecto preload
and sales invoices via Ash `list_by_ids!`. After migration, both can use Ash reads.

## entries.ex

```elixir
defmodule Firmowid.Ash.Invoicing.Entries do
  @moduledoc "Invoicing entries aggregation — timeline of invoices and transactions."

  alias Firmowid.Ash.Invoicing.CostInvoice
  alias Firmowid.Ash.Invoicing.SalesInvoice
  alias Firmowid.Ash.Finances

  def get_invoicing_entries(from, to, filter) do
    # Same logic, already uses Ash code interfaces
    # Just update module references
  end

  def get_all_months_with_invoicing_entries do
    # Swap Ecto schema references to Ash resources in UNION query
    # SalesInvoice, CostInvoice, Transaction are all Ecto schemas
  end

  def order_entries_for_display(entries) do
    # Pure function, move as-is
  end
end
```

## matching.ex

```elixir
defmodule Firmowid.Ash.Invoicing.Matching do
  @moduledoc "Invoice-transaction matching orchestration."

  alias Firmowid.Ash.Finances
  alias Firmowid.Ash.Invoicing.CostInvoice
  alias Firmowid.Ash.Invoicing.CostInvoiceTransaction
  alias Firmowid.Ash.Invoicing.SalesInvoice
  alias Firmowid.Ash.Invoicing.SalesInvoiceTransaction
  alias Firmowid.Invoicing.Matching, as: MatchingEngine

  # Move match_cost_invoices, match_cost_invoice, match_sales_invoices,
  # match_sales_invoice, score_and_sort_transactions,
  # get_potential_transactions_for_invoice, subscribe/broadcast
end
```

The sub-modules under `lib/firmowid/invoicing/matching/` (Windowing, RegressionPredictor,
ParametrizedResult, etc.) stay where they are for now. They're pure computation modules
with no Ecto/Ash coupling.

## Callers to update

- `lib/firmowid_web/invoicing/views/index.ex` — main invoicing dashboard
  - `Invoicing.search_invoices` → `Search.search_invoices`
  - `Invoicing.get_invoicing_entries` → `Entries.get_invoicing_entries`
  - `Invoicing.get_all_months_with_invoicing_entries` → `Entries.get_all_months_with_invoicing_entries`
  - `Invoicing.order_entries_for_display` → `Entries.order_entries_for_display`
  - `Invoicing.get_potential_transactions_for_invoice` → `Matching.get_potential_transactions_for_invoice`
  - `Invoicing.subscribe_invoicing_broadcast` → `Matching.subscribe_invoicing_broadcast`
  - Bodyguard checks → removed

- `lib/firmowid/invoicing/worker.ex` — Oban matching worker
  - `Invoicing.match_cost_invoices` → `Matching.match_cost_invoices`
  - `Invoicing.match_sales_invoices` → `Matching.match_sales_invoices`

## Testing

1. Search invoices → verify results (sales + cost)
2. Search with filters → verify filtering
3. Get entries → verify aggregation by month
4. Get entries with filter → verify :all, :unmatched, :invoices, :transactions
5. Months query → verify distinct months
6. Matching → verify auto-match still works
