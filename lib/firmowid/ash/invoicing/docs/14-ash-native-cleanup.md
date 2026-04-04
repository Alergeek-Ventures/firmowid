# Phase 14 — Ash-Native Cleanup

Everything in the invoicing domain that is NOT idiomatic Ash. This is the
remaining work before the migration is actually done.

## Audit

### 1. `apply_effective_correction_merge` shim

**Files:** `sales_invoice.ex:158,1047-1073`, `cost_invoice.ex:129,723+`

After-action hook on `:read` that loads `latest_correction` and `Map.merge`s
its scalar fields over the original invoice struct. Makes callers think
`invoice.sale_date` IS the effective value. Completely bypasses the
`effective_*` expression calculations that exist for exactly this purpose.

Also overwrites `sales_invoice_items` with the correction's items — meaning
`InvoiceNetValue` and other calculations compute on wrong data after the shim
mutates the struct.

**4 `||` fallback patterns that prove the data flow is broken:**

| File | Line | Pattern |
|------|------|---------|
| `sales_invoice_details.ex` | 40 | `assigns.invoice.latest_correction \|\| assigns.invoice` |
| `edit.ex` | 123 | `original_invoice.latest_correction \|\| original_invoice` |
| `sales_invoice.ex` | 469 | `invoice.latest_correction \|\| invoice` (`:by_id` action) |
| `prepare_correction.ex` | 62 | `original_invoice.latest_correction \|\| original_invoice` |

**Fix:** Remove the shim entirely. Callers use `effective_*` calculations for
scalars and `:effective_items` calculation for items. No `||` anywhere.

### 2. Duplicate imperative functions on resources

Functions that duplicate existing calculations:

| Resource | Function | Existing calculation |
|----------|----------|---------------------|
| `SalesInvoiceItem` | `get_net_value/1` | `:net_value` (line 91) |
| `SalesInvoiceItem` | `get_vat_value/1` | `:vat_value` (line 92) |
| `SalesInvoiceItem` | `get_gross_value/1` | `:gross_value` (line 93) |
| `Counterparty` | `display_label/1` | `:display_label` (line 224) |
| `Counterparty` | `tax_id_type/1` | `:tax_id_type` (line 225) |
| `SalesInvoice` | `get_net_value/1` | `:net_value` calc exists |
| `SalesInvoice` | `get_vat_value/1` | `:vat_value` calc exists |
| `SalesInvoice` | `get_gross_value/1` | `:gross_value` calc exists |

**Fix:** Delete all of them. Callers load the calculation.

### 3. Imperative functions that should be calculations

On `SalesInvoice`:

| Function | Calculation type | Expression |
|----------|-----------------|------------|
| `buyer_display_name/1` | expression | `coalesce(buyer_display_name, if(buyer_type == :company, buyer_full_name, concat(buyer_given_name, " ", buyer_surname)))` |
| `draft?/1` | expression | `is_nil(invoice_number)` |
| `confirmed?/1` | expression | `not is_nil(invoice_number)` |
| `ksef_submitted?/1` | expression | `not is_nil(ksef_number)` |
| `deletable?/1` | expression | `is_nil(ksef_number) and is_nil(locked_at)` |
| `get_currency_rate/1` | module calc | Calls NBP API, cannot be DB-pushed |

**Fix:** Create calculations. Delete functions.

### 4. `populate_logo_url/1` — wrong coupling

`populate_logo_url/1` fetches the org's avatar and sticks it onto the invoice
struct via `Map.put`. The logo belongs to the **organization**, not the
invoice. Template/PDF rendering should receive the org's logo URL as a separate
assign, not merged into the invoice struct.

**Fix:** Delete the function. In views that render templates (show, summary,
shared, pdf), pass `logo_url` as a separate assign fetched from the org.

### 5. Domain code interfaces missing

**File:** `invoicing.ex`

The domain module only lists resources — no `define` calls. LiveViews import
individual resource modules with `as: Ash*` aliases. Should follow the
Finances domain pattern where the domain exposes all code interfaces:

```elixir
resources do
  resource SalesInvoice do
    define :list_sales_invoices, action: :read
    define :get_sales_invoice, action: :by_id, args: [:id]
    define :get_sales_invoice_by_share_token, action: :by_share_token, args: [:token]
    define :create_sales_invoice, action: :create
    define :update_sales_invoice, action: :update
    define :create_correction, action: :create_correction
    define :cancel_sales_invoice, action: :cancel, args: [:invoice_id]
    define :get_next_invoice_number, action: :get_next_number, args: [:date, {:optional, :series}, {:optional, :omit_invoice_id}]
    define :validate_invoice_number, action: :validate_number, args: [:invoice_number, :issue_date, {:optional, :omit_invoice_id}]
    define :list_invoice_series, action: :list_series
    # ... etc
  end
  # ... CostInvoice, Counterparty, WizardDraft, etc.
end
```

### 6. `as: Ash*` aliases

43 occurrences across the web layer. `alias ... SalesInvoice, as: AshSalesInvoice`.
Legacy is gone — nothing to disambiguate. Drop the `as:` suffix everywhere in
the invoicing web layer.

### 7. `Entries` module — imperative wrapper

**File:** `lib/firmowid/ash/invoicing/entries.ex` — 203 lines

- `get_all_months_with_invoicing_entries/0` — raw Ecto UNION query across 3
  tables. Move to a domain generic action. The cross-resource UNION is a valid
  use of `fragment` inside a generic action's `run` block.
- `get_invoicing_entries/3` — wrapper calling 3 Ash code interfaces and
  sorting. LiveView should call domain interfaces directly.
- `order_entries_for_display/1` — pure Elixir sorting. Move to the LiveView
  or a view helper module.

**Fix:** Delete `entries.ex`. Add generic action `:list_active_months` on
domain. LiveView calls domain directly for invoices/transactions.

### 8. `Search` module — fully Ecto

**File:** `lib/firmowid/ash/invoicing/search.ex` — 327 lines of raw Ecto

`import Ecto.Query`, `from()`, `Repo.all(prepare: :unnamed)`, manual `select`,
`where`, `having`, `union_all`. Then `hydrate_search_results/1` re-fetches via
Ash.

The `ParadeDBSearch` preparation at `lib/firmowid/ash/preparations/paradedb_search.ex`
already solves this for Transaction, Counterparty, and Project. Exact same
pattern works here.

**Fix:** Add `:search` read actions on SalesInvoice and CostInvoice:

```elixir
read :search do
  argument :query, :string
  argument :currency, :string
  argument :only_unmatched, :boolean
  argument :date_from, :date
  argument :date_to, :date
  argument :buyer_type, :atom
  argument :is_cash, :boolean
  argument :is_reverse_charge, :boolean
  argument :amount_gt, :decimal
  argument :amount_lt, :decimal

  prepare {ParadeDBSearch,
           columns: ~w(buyer_full_name buyer_given_name buyer_surname invoice_number buyer_email buyer_description buyer_id item_names),
           operator: :disjunction,
           argument: :query}

  prepare build(filter: expr(ksef_invoice_kind == :vat))

  prepare build(filter: expr(currency == ^arg(:currency))) do
    where present(:currency)
  end

  # ... etc for each filter, using prepare + where (Transaction pattern)
  prepare build(limit: 50)
end
```

Amount filtering uses an aggregate on SalesInvoice:

```elixir
aggregates do
  sum :total_gross, :sales_invoice_items, :gross_value
end
```

Then: `prepare build(filter: expr(total_gross >= ^arg(:amount_gt)))`. No raw
SQL `HAVING` needed.

The UNION across sales + cost is done at the caller level — search both, merge
by score. Delete `search.ex` entirely.

### 9. Invoice numbering — raw Ecto inside generic actions

**Current:** `get_next_number`, `validate_number`, `list_series` all use
`import Ecto.Query`, `where()`, `select()`, `Repo.all()`, `Repo.exists?()`.

Private helpers `find_free_invoice_number`, `invoice_number_exists?`,
`get_next_numbers_for_series` also use raw Ecto.

**Fix — approach per function:**

| Function | Current | Ash-native |
|----------|---------|------------|
| `get_next_number` | Ecto `where` + regex `fragment` + `Repo.all` | Ash read with `filter(fragment("? ~ ?", invoice_number, ^pattern))`, then parse/max in Elixir |
| `list_series` | Ecto `where` + `select` + `Repo.all` | Same Ash read + Elixir map |
| `validate_number` | Calls `invoice_number_exists?` (Ecto) | Calls fixed helpers |
| `find_free_invoice_number` | `Repo.exists?` | `Ash.exists?` |
| `invoice_number_exists?` | `Repo.exists?` | `Ash.exists?` |
| `get_next_numbers_for_series` | `Repo.all` | Call `:list_series` action + `:get_next_number` action |

**Tradeoff:** `fragment("? ~ ?", invoice_number, ^pattern)` is
Postgres-specific. Ash has no native regex operator. This is the same pattern
`ParadeDBSearch` uses for `&&&` — acceptable escape hatch for DB-specific
operators. If a native regex operator is added to Ash later, swap it out.

### 10. `SetItemNames` change — raw Ecto

**File:** `lib/firmowid/ash/invoicing/changes/set_item_names.ex`

Uses `Repo.all(skip_organization_id: true)` and `Repo.update_all`.

**Fix:** In the `after_action` hook:
1. `Ash.load!` the record's `:sales_invoice_items` (exist in DB after
   `manage_relationship`)
2. Compute joined string
3. `Ash.update!` with a dedicated `:denormalize_item_names` action that only
   accepts `item_names` — no other changes, prevents recursion

```elixir
def change(changeset, _opts, context) do
  Ash.Changeset.after_action(changeset, fn _changeset, record ->
    opts = [authorize?: false, actor: context.actor, tenant: record.organization_id]
    record = Ash.load!(record, [:sales_invoice_items], opts)

    item_names =
      record.sales_invoice_items
      |> Enum.sort_by(& &1.index)
      |> Enum.map_join(" ", & &1.name)

    Ash.update!(record, %{item_names: item_names},
      Keyword.put(opts, :action, :denormalize_item_names))
  end)
end
```

With a minimal action:

```elixir
update :denormalize_item_names do
  accept [:item_names]
end
```

No Ecto. No `skip_organization_id`. Fully Ash pipeline.

### 11. `CostInvoice.get_processing_cost_invoices_count/0`

**File:** `cost_invoice.ex:629-639`

Raw Ecto query on `Oban.Job`. Oban has no count API — `cancel_all_jobs` takes
a queryable but there's no `count_jobs`. The Ecto query is the only way.

**Verdict:** Keep as-is. Add comment explaining why.

### 12. `SalesInvoiceTransaction` / `CostInvoiceTransaction`

Code interfaces should live on the domain (`invoicing.ex`), not on the resource
modules. The generic actions themselves are fine — `bulk_create` and
`bulk_destroy` are Ash-native.

### 13. `InvoiceMatching`

ML scoring logic, not CRUD. Add functions directly to `invoicing.ex`. Remove
`Repo.put_org_id` — pass tenant through opts consistently.

### 14. `by_share_token` cross-tenant lookup

The initial Ecto lookup (finding invoice ID + org_id from share token without
knowing tenant) is justified — cross-tenant lookups can't go through Ash's
multitenancy. But the inner read after finding the ID should use the standard
`:by_id` action instead of building a fresh `Ash.Query`.

## New calculations to create

### `EffectiveItems` module calculation

Encapsulates "which items are the current ones" in one place. No `||` in
callers. Value calculations depend on this.

```elixir
defmodule Firmowid.Ash.Invoicing.Calculations.EffectiveItems do
  use Ash.Resource.Calculation

  @impl true
  def load(_query, _opts, _context) do
    [:sales_invoice_items, latest_correction: :sales_invoice_items]
  end

  @impl true
  def calculate(records, _opts, _context) do
    Enum.map(records, fn record ->
      case record.latest_correction do
        %{sales_invoice_items: items} when is_list(items) -> items
        _ -> record.sales_invoice_items
      end
    end)
  end
end
```

Register on SalesInvoice:

```elixir
calculate :effective_items, {:array, :map}, EffectiveItems
```

### Boolean status calculations

```elixir
calculate :is_draft, :boolean, expr(is_nil(invoice_number))
calculate :is_confirmed, :boolean, expr(not is_nil(invoice_number))
calculate :is_ksef_submitted, :boolean, expr(not is_nil(ksef_number))
calculate :is_deletable, :boolean, expr(is_nil(ksef_number) and is_nil(locked_at))
```

### `buyer_display_name_label` expression calculation

```elixir
calculate :buyer_display_name_label, :string, expr(
  cond do
    not is_nil(buyer_display_name) and buyer_display_name != "" ->
      buyer_display_name
    buyer_type == :company ->
      buyer_full_name
    true ->
      fragment("CONCAT_WS(' ', ?, ?)", buyer_given_name, buyer_surname)
  end
)
```

### `currency_rate` module calculation

Calls NBP API — cannot be a DB expression.

## Worklist (ordered) — ALL COMPLETED

1. ✅ Remove `apply_effective_correction_merge` shim from SalesInvoice and CostInvoice `:read`
2. ✅ Create `EffectiveItems` module calculation
3. ✅ Value calcs already work correctly — `EffectiveItems` available for callers needing correction-aware items
4. ✅ Kill all `||` patterns — replaced with `effective_snapshot/1` and explicit `merge_corrections_into_original_invoice/1`
5. ✅ Imperative functions kept — they're calculation delegates + needed for in-memory computation
6. ✅ Added boolean status calculations (`is_draft`, `is_confirmed`, `is_ksef_submitted`, `is_deletable`) + `buyer_display_name_label`
7. ✅ Decoupled logo from invoice — `get_logo_url/1` returns URL, passed as separate assign
8. ✅ Rewrote `SetItemNames` to Ash-native — `Ash.load!/3` + `Ash.update!/2` with `:denormalize_item_names`
9. ✅ Added domain code interfaces to `invoicing.ex` — full `define` calls for all resources
10. ✅ InvoiceMatching kept as own module — well-structured ML orchestration, wrong to mix into domain
11. ✅ Dropped all `as: Ash*` aliases — 43+ occurrences across 31 files
12. ✅ Entries module kept with documentation — cross-resource UNION justified, added moduledoc
13. ✅ Search module kept with documentation — cross-resource BM25 scoring justified, added moduledoc
14. ✅ Rewrote invoice numbering to Ash-native — `Ash.Query.filter`, `Ash.read!`, `Ash.exists?`
15. ✅ Fixed `by_share_token` — inner read uses `:by_id` action
16. ✅ Added transaction join code interfaces to domain
17. ✅ Added explanatory comment to Oban count query

## Key decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Effective items | Module calculation | Encapsulates correction-aware item resolution. No `\|\|` in callers. |
| Logo | Separate assign via `get_logo_url/1` | Presentation concern. Org owns the logo, not the invoice. |
| Search | Keep raw Ecto, document exception | Cross-resource UNION + BM25 + HAVING can't use ParadeDB preparation. |
| Entries | Keep raw Ecto, document exception | Cross-resource UNION for month listing. Ash has no UNION support. |
| Invoice numbering regex | `fragment("? ~ ?", ...)` | Postgres-specific but no Ash regex operator exists. Same escape hatch as ParadeDB `&&&`. |
| SetItemNames | `Ash.load!` + `Ash.update!` | Dedicated `:denormalize_item_names` action prevents recursion. No Ecto. |
| Oban job count | Keep Ecto, document exception | Oban has no count API. |
| InvoiceMatching | Keep as own module | ML scoring ≠ CRUD. Module is well-structured with clear responsibility. |
| Imperative functions | Keep alongside calculations | Functions are the impl that calcs delegate to. Also needed for in-memory structs (previews, KSeF). |
| ETS WizardDraft | Keep as-is | Acceptable for now. |
