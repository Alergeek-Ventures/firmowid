# Phase 4b: Read Consolidation + effective_* Calculations

## Status: COMPLETE

All work in this phase is done. Verified via `mix check` (all green) and
manual 1:1 comparison of localhost:19335 vs localhost:4000.

## What was done

### 1. EffectiveFields macro + has_one :latest_correction (done earlier)

- `lib/firmowid/ash/invoicing/sales_invoice/effective_fields.ex` — 28 `effective_*`
  expression calculations, DB-pushable via `if is_nil(latest_correction)` pattern
- `has_one :latest_correction` on SalesInvoice + `has_one :latest_correction_invoice`
  on CostInvoice
- `@snapshot_fields` deleted, `get_latest_invoice_snapshot` deleted
- `merge_corrections_after_read` replaced by `apply_effective_correction_merge`
  using `latest_correction` relationship

### 2. Value calculations (done earlier)

- `ItemNetValue`, `ItemVatValue`, `ItemGrossValue` on SalesInvoiceItem
- `InvoiceNetValue`, `InvoiceVatValue`, `InvoiceGrossValue` on SalesInvoice
- All match existing functions exactly

### 3. populate_reference_invoices → calculations (done earlier)

- `ReferenceInvoice` + `AnnotatedCorrections` module calculations
- 8 callers updated (show, edit, pdf, pdf controller, shared, details, summary,
  invoice_renderer)

### 4. Read action consolidation: 10 → 3

Consolidated `SalesInvoice` from 10 read actions to 3:

| Kept | Purpose |
|------|---------|
| `:read` | Primary — optional filters: `date_from`, `date_to`, `date_field`, `kind`, `status`, `ids` |
| `:by_id` | Single record by ID, preloads all relationships |
| `:by_share_token` | Cross-tenant share token lookup |

**Deleted actions:** `list_for_month`, `list_unmatched`, `list_by_sale_date`,
`list_by_ids`, `list_invoices_in_date_range`, `list_recent`, `search`

**Deleted helpers:** `filter_unmatched/2` (logic moved into `:read` inline prepare)

**Updated callers:**
- `entries.ex` — 3 calls (`:all`, `:unmatched`, `:invoices` filters)
- `invoice_matching.ex` — 1 call (unmatched sales invoices)
- `analysis.ex` — 1 call (by sale_date range)
- `search.ex` — 1 call (hydrate search results by IDs)
- `file_download.ex` — 1 call (date range with `:any` date field)
- `creator.ex` — 1 call (`recent_invoices/1` private function computes 2-month range)

**Key fix:** All callers corrected to use `read!(args_map, opts)` two-argument form.
Previous session had incorrectly merged action arguments into the opts keyword list.

### 5. Bonus fix: analysis.ex entity_tags

Fixed `KeyError: key :entity_tags not found` crash on `/analiza` page. The
`filter_entities/4` function used struct update `%{entity | entity_tags: tags}`
which failed for `Transaction` structs (no `entity_tags` relationship). Changed
to `Map.put(entity, :entity_tags, tags)`.

### 6. FilterByDateField preparation

`lib/firmowid/ash/invoicing/preparations/filter_by_date_field.ex` — reusable
preparation supporting `date_field` values `:issue_date`, `:sale_date`,
`:due_date`, `:any` (OR filter on issue_date + sale_date).

## Test gate results

Manual 1:1 comparison of localhost:19335 vs localhost:4000:

| Page | Result |
|------|--------|
| `/fakturowanie` FAKTURY tab | ✅ Identical (6 invoices) |
| `/fakturowanie` NIEPRZYPISANE tab | ✅ Identical (11 items) |
| `/fakturowanie` TRANSAKCJE tab | ✅ Identical |
| `/analiza` | ✅ Identical (11 916,13 zł / -25,00 zł / 11 891,13 zł) |
| Search modal | ✅ Works correctly |
| `mix check` | ✅ All green (compile, format, credo, sobelow, dialyzer, tests) |

### 7. CostInvoice read consolidation: 8 → 3

Same pattern as SalesInvoice. Consolidated from 8 read actions to 3:

| Kept | Purpose |
|------|---------|
| `:read` | Primary — optional filters: `date_from`, `date_to`, `date_field`, `status`, `ids`, `include_blob` |
| `:by_id` | Single record by ID, preloads all relationships including blob URLs |
| `:by_checksum` | Cross-blob checksum lookup |

**Deleted actions:** `list_for_month`, `list_unmatched`, `list_by_sale_date`,
`list_by_ids`, `list_invoices_in_date_range`

**Deleted generic action:** `get_with_blob_url` (replaced by `:by_id` with full preloads)

**Deleted helpers:** `filter_unmatched/2` (logic moved into `:read` inline prepare)

**Updated callers:**
- `entries.ex` — 3 calls (`:all`, `:unmatched`, `:invoices` filters)
- `invoice_matching.ex` — 1 call (unmatched cost invoices)
- `analysis.ex` — 1 call (by sale_date range)
- `file_download.ex` — 1 call (date range with `:any` + `include_blob: true`)
- `show.ex` (cost invoice) — 3 calls (`get_with_blob_url!` → `by_id!`)
- `cost_invoices_test.exs` — 2 calls (list_for_month, list_unmatched → read!)

### 8. Bug fixes: validation messages + currency display

- Added Polish `message:` to all `validate present/match/string_length` in WizardDraft
  and SalesInvoice actions
- Fixed `invoice_payment.ex` currency display: `@payment_form[:currency].value` → `Map.get(@invoice, :currency)`
- Fixed `get_error_message` in creator.ex to deduplicate and properly surface Ash error messages

### 9. KSeF integration fixes

- **template.ex logo_url crash**: Changed `@sales_invoice.logo_url` to `Map.get(@sales_invoice, :logo_url)` —
  `logo_url` is a virtual field added via `Map.put`, not part of the Ash struct
- **summary.ex missing populate_logo_url**: Added `populate_logo_url` call in mount and KSeF status handler
- **creator.ex preview missing logo_url**: Added `get_organization_with_avatar` + `Map.put(:logo_url, ...)` in preview setup
- **creator.ex reset_bank_account crash**: Currency change in Step 2 tried `WizardDraft.update_payment`
  which validates all payment fields (not yet set). Created `:reset_bank_account` action on WizardDraft
  that only clears `seller_account_number` without validation
- **WizardDraft currency nil default**: Manual entry ("Wprowadź ręcznie") created drafts with `currency: nil`,
  crashing `Money.new(nil, ...)` in invoice_items component. Added `default: "PLN"` to WizardDraft currency
- **confirm_from_draft missing :index**: Item index was taken from WizardDraft items which don't have `:index`.
  Changed to `Enum.with_index` to generate sequential indices
- **KSeF seed checksum**: Added `ksef_invoice_checksum` to BC/02 seed data so `invoice_url!` doesn't try
  to backfill from real KSeF API (which fails without authentication)

## References

- Doc 04 lines 592-695: original plan
- FilterByDateField: `lib/firmowid/ash/invoicing/preparations/filter_by_date_field.ex`
- EffectiveFields: `lib/firmowid/ash/invoicing/sales_invoice/effective_fields.ex`
