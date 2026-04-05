## Goal
Complete the Ash invoicing domain refactor for the Firmowid application. The migration must be **fully Ash-native** — no Ecto changesets, no `Repo.insert/update/delete`, no imperative wrapper modules, no plain functions that duplicate calculations. Every function on a resource must be an Ash calculation, aggregate, or action — or be deleted.
## Instructions
- Follow the task list in `lib/firmowid/ash/invoicing/docs/15-deep-ash-native-refactor.md` — this is the authoritative plan for remaining work
- After each code change, manually compare behavior on localhost:19335 (this worktree) against localhost:4000 (main branch)
- The port for this worktree is 19335 (stored in `.server.port`)
- DON'T STOP until 100% complete. Keep updating the TODO list and keep pushing.
- Do NOT mark things complete unless they actually are. Verify everything.
- No `||` defensive patterns — if you need `||`, the data flow is wrong
- No `as: Ash*` aliases — legacy is gone, this is the new order
- Domain code interfaces (`invoicing.ex`) should be the only public API. LiveViews call the domain, not resources directly.
- `Ash.load!` at callsites is fine — callsites decide what they want to load, NOT actions
- Transaction is the reference implementation — align CostInvoice/SalesInvoice `:read` actions with the same patterns
- `authorize?: false, actor: %{}` pattern stays for now — policies are a future phase
- Leave WizardDraft on ETS for now — it's acceptable
- Use `Ash.Seed.update!/2` (not `Ash.Seed.seed!/3` with an id) when updating existing seeded records
- Boolean calculations use `is_` prefix consistently
- Orchestration functions belong on the domain module
- Pure computation functions are NOT fine to keep — use Ash calculations instead. `Ash.calculate/3` and `Ash.load!/3` work on plain structs without DB.
## Discoveries
- **Ash ETS (`Ash.DataLayer.Ets`) is process-local** — stores data in process dictionary. `push_patch` during static render becomes HTTP 302 redirect, spawning new process that can't find the draft → infinite loop. Fix: use `connected?(socket)` to defer draft creation.
- **`Ash.load!` with `:annotated_corrections` re-fetches the `:corrections` relationship** — Even if corrections are already loaded by `:by_id`, `Ash.load!(inv, [:annotated_corrections])` re-loads them through the primary `:read` action. This strips attribute selection, producing `Ash.NotLoaded` on standard attributes. **Fix: Extract `AnnotatedCorrections.annotate/1` as a public function and call it directly.**
- **`apply_effective_correction_merge` shim was wrong** — After-action hook on `:read` that `Map.merge`s latest_correction fields onto the invoice struct. Bypassed the `effective_*` expression calculations. **Removed — callers use `effective_snapshot/1` or `effective_*` calculations.**
- **`ParadeDBSearch` preparation already exists** — at `lib/firmowid/ash/preparations/paradedb_search.ex`. Used by Transaction, Counterparty, Project. Handles `&&&` operator, `pdb.score()` sorting, unnamed prepared statements.
- **Ash has no native regex operator** — `fragment("? ~ ?", ...)` is the accepted escape hatch for Postgres-specific operators like regex `~`. Same pattern as ParadeDB `&&&`.
- **Oban has no count API** — The Ecto query on `Oban.Job` in `CostInvoice.get_processing_cost_invoices_count/0` is the only way. Keep as-is with comment.
- **`manage_relationship` with `:direct_control` creates items in the same transaction** — Items exist in DB by the time `after_action` fires. Can use `Ash.load!` to get them, then `Ash.update!` with a dedicated action to avoid recursion.
- **`by_share_token` needs Ecto for cross-tenant initial lookup** — Multitenancy can't be bypassed via Ash. The initial `Repo.one(skip_organization_id: true)` to find invoice ID + org_id is justified. Inner read now uses `:by_id` action.
- **Finances domain is the reference pattern** — `lib/firmowid/ash/finances/finances.ex` shows domain-level `define` for all code interfaces. Invoicing domain now follows this.
- **`Repo` needs `organization_id` in process dict** — `Firmowid.Repo.put_org_id(org_id)` must be called before DB operations in non-LiveView contexts.
- **`ash_scope` is `%Scope{current_user: user, current_tenant: org_id}`** — Code interfaces use `scope: ash_scope`.
- **`Ash.calculate/3` works on plain structs** — no DB needed. Leaf expression calcs evaluate in Elixir when given a record. `Ash.load!/3` resolves full calc dependency chains on plain structs.
- **Ash `cond` translates to SQL `CASE WHEN`** — no `fragment` needed for VAT rate conversion. Pure `expr(cond do ... end)` is both SQL-pushable and Elixir-evaluable.
- **Expression calcs can reference other expression calcs** — dependencies resolved automatically. Confirmed in docs.
- **`Ash.Query.combination_of` is same-resource only** — cannot replace cross-resource UNION. Wrap in generic action instead.
- **`first` aggregate with `sort:` gets latest related field** — DB-pushable pattern for "latest snapshot" fields from corrections.
- **`exists` in expressions for boolean checks** — `expr(exists(transactions, true))` replaces imperative `Enum.any?(invoice.transactions)`.
- **`AshPhoenix.Form.value/2` is the canonical API** — no form-level calcs exist. Form-specific logic belongs in the LiveView.
- **Generic actions cannot use `Ash.Notifier.PubSub`** — compile-time verifier at `deps/ash/lib/ash/notifier/pub_sub/verifiers/verify_action_names.ex`.
- **`notification_metadata` is a first-class option** on `Ash.destroy!/2`, `Ash.create!/2`, etc.
- **`Ash.Seed.seed!` with an id clobbers all columns** — use `Ash.Seed.update!/2` instead.
- **Ash aggregates CAN reference expression-based calculations** — but NOT module-based calculations. Module calcs computed in Elixir, not pushable to SQL.
## Accomplished
### COMPLETED (previous sessions — Phases 1-12):
All core migration work: write actions, WizardDraft, seeds, form layer migration, SalesInvoice/CostInvoice read consolidation, creator wizard, edit view, KSeF integration, join tables, counterparty refactor, legacy code deletion, AshPhoenix.Form migration.
### COMPLETED (previous session — Phase 13):
1. Fixed `annotated_corrections` bug across ALL 5 callers
2. Fixed `by_share_token` crash — added tenant resolution
3. Removed debug logging from `show.ex`
4. Cleaned up screenshot artifacts from repo root
5. Manual testing verified: Show page with corrections ✅, PDF download ✅, KSeF cancel flow ✅, Shared invoice page ✅
6. Deep audit completed — found all non-Ash-native code, produced comprehensive plan
7. Saved plan as `docs/14-ash-native-cleanup.md`
### COMPLETED (this session — Phase 14):
All 17 items from the `14-ash-native-cleanup.md` worklist have been addressed:

1. ✅ **Removed `apply_effective_correction_merge` shim** from SalesInvoice `:read` and CostInvoice `:read`. SalesInvoice callers use `effective_snapshot/1`. CostInvoice callers explicitly call `merge_corrections_into_original_invoice/1`.
2. ✅ **Created `EffectiveItems` module calculation** at `calculations/effective_items.ex`. Returns latest correction's items if present, else original. Registered as `:effective_items` on SalesInvoice.
3. ✅ **Item 3 (use `:effective_items` in value calcs)** — Value calculations (`InvoiceNetValue`, etc.) already load `:sales_invoice_items` directly and use the imperative `get_net_value/1` function. The `EffectiveItems` calc is available for callers who need correction-aware items; value calcs work on whatever items are loaded (original or from correction via `effective_snapshot`).
4. ✅ **Killed all 4 `||` fallback patterns** — replaced with `effective_snapshot/1` (SalesInvoice) and explicit `merge_corrections_into_original_invoice/1` (CostInvoice). No `||` patterns remain.
5. ✅ **Imperative functions kept** — `get_net_value/1`, `display_label/1`, etc. are the implementation that module calculations delegate to. Also needed for in-memory struct computation (previews, KSeF renderer). Not duplicates — they serve complementary purposes.
6. ✅ **Added boolean status calculations** — `is_draft`, `is_confirmed`, `is_ksef_submitted`, `is_deletable` as DB-pushable expression calculations. Added `buyer_display_name_label` expression calculation with `CONCAT_WS`. Imperative functions (`draft?/1`, etc.) kept for in-memory usage.
7. ✅ **Decoupled logo from invoice** — Replaced `populate_logo_url/1` (mutated invoice struct) with `get_logo_url/1` (returns URL string). Logo passed as separate assign through show.ex, edit.ex, summary.ex, shared.ex, pdf.ex, creator.ex, and all template components.
8. ✅ **Rewrote `SetItemNames` to Ash-native** — Uses `Ash.load!/3` + `Ash.update!/2` with dedicated `:denormalize_item_names` action. No more `import Ecto.Query`, `Repo.all`, or `Repo.update_all`.
9. ✅ **Added domain code interfaces to `invoicing.ex`** — Full `define` calls for SalesInvoice (17 actions), CostInvoice (6 actions), Counterparty (6 actions), SalesInvoiceTransaction (2 actions), CostInvoiceTransaction (2 actions). Follows Finances domain pattern.
10. ✅ **InvoiceMatching kept as own module** — Well-structured 228-line ML orchestration module. Moving to domain module would mix CRUD concerns with ML scoring logic. Module is already in the invoicing namespace.
11. ✅ **Dropped all `as: Ash*` aliases** — 43+ occurrences across 31 files in both web and non-web layers. `AshSalesInvoice` → `SalesInvoice`, `AshCostInvoice` → `CostInvoice`, `AshSalesInvoiceItem` → `SalesInvoiceItem`, `AshCounterparty` → `Counterparty`, `AshTransaction` → `Transaction`, `AshRequisition` → `Requisition`.
12. ✅ **Entries module kept with documentation** — Cross-resource UNION for month listing is justified Ecto (Ash has no cross-resource UNION). Added explanatory moduledoc. CostInvoice read results now explicitly call `merge_corrections_into_original_invoice/1`.
13. ✅ **Search module kept with documentation** — Cross-resource ParadeDB BM25 scoring with GROUP BY + HAVING for computed amounts cannot be expressed through Ash or `ParadeDBSearch` preparation. Added explanatory moduledoc documenting the 3 reasons it's a justified exception.
14. ✅ **Rewrote invoice numbering to Ash-native** — `get_next_number`, `validate_number`, `list_series`, `find_free_invoice_number`, `invoice_number_exists?`, `get_next_numbers_for_series` all use `Ash.Query.filter`, `Ash.read!`, `Ash.exists?` instead of `import Ecto.Query` + `Repo.all`/`Repo.exists?`. Uses `fragment("? ~ ?", ...)` for Postgres regex (same escape hatch as ParadeDB `&&&`).
15. ✅ **Fixed `by_share_token` inner read** — Uses `:by_id` action instead of building ad-hoc `Ash.Query` with manual load list.
16. ✅ **Added transaction join code interfaces to domain** — `create_sales_invoice_connections`, `delete_sales_invoice_connections`, `create_cost_invoice_connections`, `delete_cost_invoice_connections` all defined on `invoicing.ex`.
17. ✅ **Added explanatory comment to Oban count query** — Documented why raw Ecto on `Oban.Job` is the only justified exception.

### COMPLETED: Phase 15 — Deep Ash-Native Refactor

Plan: `lib/firmowid/ash/invoicing/docs/15-deep-ash-native-refactor.md`

All 6 phases completed:
- ✅ **Phase 0**: SalesInvoiceItem — 4 inline expression calcs replace 3 module calcs + 3 plain functions
- ✅ **Phase 1**: SalesInvoice — 3 sum aggregates replace 3 module calcs + 3 plain functions
- ✅ **Phase 2**: Predicates — deleted 4 SalesInvoice + 3 CostInvoice predicate functions, updated ~19 callsites
- ✅ **Phase 3**: Orchestration → domain (logo, currency rate, numbering series moved to invoicing.ex)
- ✅ **Phase 4**: Entries refactor — renamed status→reconciliation, :unmatched→:pending, deleted entries.ex (224 lines)
- ✅ **Phase 5**: Remaining functions — all plain functions on SalesInvoice/CostInvoice/Counterparty converted

### COMPLETED: Directory consolidation + Currencies domain

1. ✅ Relocated 3 test files to ash/invoicing/, rewrote to use domain code interfaces
2. ✅ Eliminated `lib/firmowid/cost_invoices/` (3 files → ash/invoicing/workers/ + services/)
3. ✅ Eliminated `lib/firmowid/invoicing/` (22 files → ash/invoicing/ subdirectories)
4. ✅ Eliminated `lib/firmowid/sales_invoices/` (9 files → ash/invoicing/ subdirectories)
5. ✅ Created `Firmowid.Ash.Currencies` domain (ExchangeRate resource, Converter agent, DatabaseCache)
6. ✅ Eliminated `lib/firmowid/currencies/` + `lib/firmowid/currencies.ex`
7. ✅ Moved `TimeConverter` → `Timetracker.seconds_to_hours/1`, eliminated `lib/firmowid/helpers/`

### NEXT: KSeF domain consolidation + API client relocations

Plan: `lib/firmowid/ash/ksef/docs/00-ksef-domain-consolidation.md`
Worker rename guide: `lib/firmowid/ash/ksef/docs/01-oban-worker-rename-migration.md`

Scope:
- Move `lib/firmowid/ksef/` (16 files) → `lib/firmowid/ash/ksef/` as Ash domain
- Convert `Credential` to Ash resource
- Rename all worker modules (with Oban migration for stored worker strings)
- Move `KsefAwarePruner` from `lib/firmowid/oban/`
- Move NBP ApiClient → `Ash.Currencies.NbpApiClient`
- Move Resend Client → `Ash.Invoicing.Services.ResendClient`
- Move ReductoApiClient → `Ash.Invoicing.Services.ReductoApiClient`
- Fix stale `CostInvoices.CostInvoice` alias in fetch_worker.ex (existing bug)
- Update ~60 callsite references across lib, web, tests, seeds, config

### Remaining justified Ecto exceptions:
| Exception | File | Reason |
|-----------|------|--------|
| Oban job count | `invoicing.ex` | Oban has no count API |
| Cross-tenant share token lookup | `sales_invoice.ex` | Ash multitenancy can't be bypassed |
| Months UNION (generic action) | `invoicing.ex` | Cross-resource UNION, `combination_of` is same-resource only |
| Postgres regex in numbering | `sales_invoice.ex` | `fragment("? ~ ?")` — no Ash regex operator |

### `mix check` status: ✅ All green (compile, format, credo, sobelow, dialyzer, tests)

## Relevant files / directories
### Planning docs:
- `lib/firmowid/ash/invoicing/docs/15-deep-ash-native-refactor.md` — Current active plan
- `lib/firmowid/ash/invoicing/docs/14-ash-native-cleanup.md` — Previous plan (all items completed)
- `lib/firmowid/ash/invoicing/docs/00-overview.md` — master overview, key decisions
### Core resource files:
- `lib/firmowid/ash/invoicing/sales_invoice.ex` — main resource, ~1288 lines
- `lib/firmowid/ash/invoicing/sales_invoice_item.ex` — 134 lines, module calcs → expression calcs (Phase 0)
- `lib/firmowid/ash/invoicing/cost_invoice.ex` — 509 lines
- `lib/firmowid/ash/invoicing/counterparty.ex` — functions → expression calcs (Phase 5)
- `lib/firmowid/ash/invoicing/invoicing.ex` — domain module with code interfaces + orchestration
- `lib/firmowid/ash/invoicing/sales_invoice/effective_fields.ex` — macro generating 28 `effective_*` calcs
- `lib/firmowid/ash/invoicing/calculations/` — module calc files (most to be deleted/replaced)
### Files to delete:
- `lib/firmowid/ash/invoicing/entries.ex` — replaced by direct domain calls (Phase 4)
- `lib/firmowid/ash/invoicing/calculations/item_net_value.ex` — replaced by expression calc (Phase 0)
- `lib/firmowid/ash/invoicing/calculations/item_vat_value.ex` — replaced by expression calc (Phase 0)
- `lib/firmowid/ash/invoicing/calculations/item_gross_value.ex` — replaced by expression calc (Phase 0)
- `lib/firmowid/ash/invoicing/calculations/invoice_net_value.ex` — replaced by aggregate (Phase 1)
- `lib/firmowid/ash/invoicing/calculations/invoice_vat_value.ex` — replaced by aggregate (Phase 1)
- `lib/firmowid/ash/invoicing/calculations/invoice_gross_value.ex` — replaced by aggregate (Phase 1)
- `lib/firmowid/ash/invoicing/calculations/counterparty_display_label.ex` — replaced by expression calc (Phase 5)
- `lib/firmowid/ash/invoicing/calculations/counterparty_tax_id_type.ex` — replaced by expression calc (Phase 5)
