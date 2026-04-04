# Invoicing Domain Migration — Overview

## Goal

Migrate the Invoicing domain fully to idiomatic Ash. No `Repo.insert/update/delete`,
no Ecto changesets for persistence, no Bodyguard. Proper Ash actions, validations,
changes, policies, code interfaces. Application shouldn't change in any way. As
in, same exact user stories should happen in exact same way. Commit after each
phase, following commit order. Test with mix check or with playwright.

## Architecture

### Write path

```
WizardDraft (ETS, ephemeral)         SalesInvoice (Postgres, persistent)
├── :create                          ├── :create (full data from draft)
├── :update_counterparty             ├── :update (edit view)
├── :update_items                    ├── :create_correction
├── :update_payment                  ├── :cancel (generic, zero-correction)
├── :destroy                         ├── :destroy
│                                    ├── :toggle_skip
Confirm flow:                        ├── :generate_share_token
  read draft                         ├── :lock_for_ksef / :unlock_for_ksef
  → SalesInvoice :create             ├── :update_ksef_fields
  → destroy draft                    └── :get_next_number / :validate_number / :list_series
```

### Shared modules

Validation and change modules live in `lib/firmowid/ash/invoicing/validations/` and
`lib/firmowid/ash/invoicing/changes/`. They are composable — used by WizardDraft,
SalesInvoice, AND Counterparty with configurable field names.

### What gets deleted — status

- ~~`lib/firmowid/sales_invoices/sales_invoice.ex`~~ — deleted
- ~~`lib/firmowid/sales_invoices/sales_invoice_item.ex`~~ — deleted
- ~~`lib/firmowid/sales_invoices/counterparty.ex`~~ — deleted
- ~~`lib/firmowid/sales_invoices/sales_invoices_transactions.ex`~~ — deleted
- ~~`lib/firmowid/sales_invoices/creator_draft_store.ex`~~ — deleted (replaced by WizardDraft ETS resource)
- ~~`lib/firmowid/sales_invoices.ex`~~ — deleted
- ~~`lib/firmowid/cost_invoices/cost_invoice.ex`~~ — deleted
- ~~`lib/firmowid/cost_invoices/cost_invoices_transactions.ex`~~ — deleted
- ~~`lib/firmowid/cost_invoices/inbound_email.ex`~~ — deleted
- ~~`lib/firmowid/invoicing.ex`~~ — deleted

### What stays (updated references only)

- `lib/firmowid/sales_invoices/pdf.ex`
- `lib/firmowid/sales_invoices/correction_reason.ex`
- `lib/firmowid/sales_invoices/country_codes.ex`
- `lib/firmowid/sales_invoices/vat_eu_api_client.ex` + response schemas
- `lib/firmowid/sales_invoices/nip_api_client.ex` + response schemas
- `lib/firmowid/invoicing/matching/` (entire directory)
- `lib/firmowid/invoicing/timeline.ex`
- `lib/firmowid/invoicing/transaction_group.ex`
- `lib/firmowid/invoicing/worker.ex`
- `lib/firmowid/cost_invoices/worker.ex`
- `lib/firmowid/cost_invoices/inbound_email_worker.ex`
- `lib/firmowid/cost_invoices/openai_enrichment.ex`
- `lib/firmowid/ksef/` (entire directory)
- `lib/firmowid/currencies/`, `lib/firmowid/nbp/`

### Out of scope

- KSeF domain (API client, workers, XML rendering) — just update struct references
- Currencies / NBP — independent
- Core (User/Org) — separate migration, after invoicing

## Phase summary

| Phase | What | Risk | Size | Status |
|-------|------|------|------|--------|
| 1 | Shared validation/change modules | Low | Medium | Done |
| 2 | WizardDraft resource (ETS) | Low | Medium | Done (ETS resource + Item embedded resource + confirm_from_draft action) |
| 3 | SalesInvoiceItem write actions | Low | Small | Done |
| 4a | SalesInvoice write actions | Medium | Large | Done (all write actions, generic actions, PubSub, policies, code interfaces) |
| 4b | Read consolidation + effective_* | Medium | Medium | Done — EffectiveFields macro (28 calculations), `has_one :latest_correction`, value calculations (6), `populate_reference_invoices` → 2 module calculations, read consolidation (10→3 actions), `search` action deleted, all callers updated, `FilterByDateField` preparation created |
| 5 | Rewrite creator wizard | High | Large | Done (WizardDraft ETS + AshPhoenix.Form for all 3 steps + preview + confirm) |
| 6 | Rewrite edit view | Medium | Medium | Done (AshPhoenix.Form for update + correction flows, preview from form values) |
| 7 | Rewrite remaining views + KSeF | Low | Medium | Done |
| 8 | Move Invoicing context | Medium | Medium | Done |
| 9 | Clean up join tables | Low | Small | Done |
| 10 | Refactor Counterparty | Low | Small | Done |
| 11 | Delete legacy code | Low | Small | Done (~550 lines of Ecto changeset code deleted from sales_invoice.ex + sales_invoice_item.ex, `import Ecto.Changeset` removed, step changeset functions removed, invoice_items.ex Ecto clauses removed) |
| 12 | Form layer migration (AshPhoenix.Form) | Medium | Large | Done (creator.ex + edit.ex fully rewritten to AshPhoenix.Form, preview built from form values) |

### Remaining work summary

All phases are **complete**. The invoicing domain is fully migrated to idiomatic Ash.

#### Phase 4b — DONE

- `EffectiveFields` macro: 28 `effective_*` expression calculations (DB-pushable)
- `has_one :latest_correction` on SalesInvoice + CostInvoice
- Value calculations: `ItemNetValue`, `ItemVatValue`, `ItemGrossValue` (item-level),
  `InvoiceNetValue`, `InvoiceVatValue`, `InvoiceGrossValue` (invoice-level)
- `populate_reference_invoices` → `ReferenceInvoice` + `AnnotatedCorrections` calculations
- SalesInvoice read consolidation: 10 → 3 actions (`:read`, `:by_id`, `:by_share_token`)
- CostInvoice read consolidation: 8 → 3 actions (`:read`, `:by_id`, `:by_checksum`)
- `FilterByDateField` preparation reused by both SalesInvoice and CostInvoice
- `search` generic action deleted (zero callers)
- All callers updated to use consolidated `:read` with args map + opts keyword list
- Backward-compat `apply_effective_correction_merge` shim kept for callers
  that access plain field names

#### Bug fixes — DONE

- Polish validation messages on WizardDraft (currency, payment fields) and SalesInvoice
- Currency display fix in `invoice_payment.ex` (was showing empty parentheses)
- `get_error_message` in creator.ex now returns proper Polish messages from Ash errors

#### Form layer (Phases 5, 6, 11, 12) — DONE

- Creator.ex fully migrated to AshPhoenix.Form (all 3 steps + preview + confirm)
- Edit.ex fully migrated to AshPhoenix.Form (update + correction flows)
- ~550 lines of Ecto changeset code deleted from sales_invoice.ex + sales_invoice_item.ex
- `import Ecto.Changeset` removed from both Ash resources
- invoice_items.ex: all Ecto changeset clauses removed
- Tests migrated to use Ash actions (one intentional Ecto.Changeset test remains
  for DB trigger verification)

## Key decisions

| Decision | Choice | Rationale | Implemented? |
|----------|--------|-----------|--------------|
| Wizard form strategy | AshPhoenix.Form per step action | Each step maps 1:1 to action | Yes (creator.ex + edit.ex fully use AshPhoenix.Form) |
| Wizard state | ETS via Ash.DataLayer.Ets | Ephemeral, no schema maintenance, dies on restart | Yes (WizardDraft ETS resource) |
| Draft validation | Validate per step (Option A) | Immediate feedback, guided data entry | Yes (WizardDraft actions: update_counterparty, update_items, update_payment) |
| Matching location | `ash/invoicing/invoice_matching.ex` | Clear legacy/migrated boundary | Yes |
| Search location | `ash/invoicing/search.ex` | Standalone module, raw SQL for ParadeDB | Yes |
| Bodyguard replacement | Ash policies | `authorize_if always()` for now (multitenancy handles org isolation) | Yes (invoicing domain) |
| Repo access | None — all through Ash | Consistency, policies, notifications | Yes (all persistence + form building via Ash) |
| PubSub | `Ash.Notifier.PubSub` (`pub_sub do` block) | Follow Transaction/Requisition pattern | Yes |
| Read consolidation | One primary `:read` with optional args | Like Transaction — caller decides filters | Yes (10→3 actions: `:read`, `:by_id`, `:by_share_token`) |
| Correction merging | `has_one :latest_correction` + `effective_*` expression calculations | DB-pushable, filterable, sortable — via macro | Yes (EffectiveFields macro, latest_correction relationship, backward-compat shim for callers) |
| Invoice numbering race | Unique constraint sufficient | Port as-is, constraint blocks form, user bumps number | Yes |
| WizardDraft policies | `authorize_if always()` + authorizer | Match domain pattern, prevent silent breakage if authorizer added later | Yes |
| Seeds/tests | Use Ash code interfaces / `Ash.Seed` | Migrate alongside each phase, not deferred | Yes |
| Seeds | `Ash.Seed` directly, no `get_or_create` wrappers | Match existing pattern (transactions, bank accounts, blobs) | Yes |
| Step changeset tests | Move to WizardDraft tests (Phase 2) | Same user paths, new implementation | Yes (tests use Ash actions; one intentional Ecto.Changeset test for DB trigger) |
| CreatorDraftStore → WizardDraft | No `partial_copy_changeset` needed | AshPhoenix.Form survives push_patch in socket assigns | Yes (CreatorDraftStore deleted, WizardDraft active) |
| ETS scoping | Multitenancy + policies, NOT process-private | ETS `private? true` = app-private, not process-private | Yes (WizardDraft uses multitenancy) |
| `populate_reference_invoices` | Two module calculations: `:reference_invoice` + `:annotated_corrections` | Callsite decides what to load. Pure — no internal loads. | Yes (8 callers updated, public function deleted) |
| `get_net_value`/`get_vat_value`/`get_gross_value` | Convert to Ash calculations | DB-pushable values from item-level calculations | Yes (6 module calculations created) |
| KSeF lock + Oban | `Ash.DataLayer.transaction` wrapping both | App crash between lock and schedule would lose data integrity | Yes |
| KsefTestHelpers | Rewrite to `Ash.Seed`, keep in `test/` (depends on `:erlsom` test dep) | Phase 7 prereq — done | Yes |
| Correction chain model | Flat siblings in DB, ordered chain in logic | All KORs point to same VAT parent. Priority by timestamp. See doc 04. | Yes (model, not calculations) |

## Discoveries (from planning)

- Ash resources ARE Ecto schemas: `Ecto.Changeset.cast/3` works on Ash structs
- Ash relationships set `on_replace: :raise` — `cast_assoc` would fail, but irrelevant since we use `manage_relationship`
- `Ash.Changeset.get_argument/2` + `set_argument/3` allows changes to normalize items argument before `manage_relationship` processes it
- `Ash.DataLayer.Ets` supports full CRUD, filtering, sorting — perfect for wizard drafts
- Embedded resources work as `{:array, EmbeddedResource}` attributes
- AshPhoenix.Form supports `_sort_*`, `_drop_*`, `_add_*` for nested form management
- `multitenancy :bypass` on a read action allows tenant-free reads (for `by_share_token`)
- `for` loops inside Spark DSL blocks don't work — use macros or transformers to generate entities
- 15 of 26 snapshot fields are used in DB-level filters/sorts — runtime merging would break those queries
- `after_action` on reads runs BEFORE relationship loading — can't see loaded data (Zach Daniel confirmed)
- Module calculations with `load/3` are the idiomatic replacement for `after_action` data transformation
- ETS `private? true` means the table isn't publicly accessible outside the OTP app, but ALL processes in the app share it — NOT per-LiveView-process scoped
- Correction chain is flat: `create_correction_invoice` pattern matches `%SalesInvoice{ksef_invoice_kind: :vat}` — only VAT can be corrected, all KORs are siblings under one VAT parent
- `Ash.DataLayer.transaction` shares the same Repo connection — Oban `insert!` within it participates in the same Postgres transaction
- `partial_copy_changeset` workaround from legacy Cachex is eliminated by AshPhoenix.Form — form state survives `push_patch` in socket assigns
