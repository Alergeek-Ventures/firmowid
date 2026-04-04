# Phase 12: Form Layer Migration (AshPhoenix.Form)

## Goal

Replace all Ecto changeset form building in creator.ex and edit.ex with
AshPhoenix.Form. Build preview structs from form values directly (Option B).
Delete ~650 lines of Ecto changeset code. Drift caught via manual 1:1
comparison against main branch (localhost:4000).

## Decision log

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Preview strategy | Option B: build struct from form values | Decoupled from AshPhoenix internals. Drift protection via manual testing, not coupling |
| Ordering | Form layer first, then Phase 4b | Unblocks deletion of changeset code immediately |
| `is_cash_account` in WizardDraft | Guard the change module (not add attribute) | WizardDraft is ephemeral, `is_cash_account` only matters on persisted SalesInvoice |

## Prerequisites — WizardDraft validation gaps

Found during planning: 3 gaps where WizardDraft actions are missing validations
that the Ecto step changesets have. Must fix before migrating forms.

### Gap 1: `validate_buyer_id_required_for_ksef` (HIGH)

**Missing from:** `:update_counterparty` action in WizardDraft

**What it does in `step1_changeset`:** looks at computed `tax_id_type` (from
`buyer_country + buyer_pesel + buyer_type`). If type is `:nip`, `:eu_vat`, or
`:other_id`, then `buyer_id` becomes `validate_required`. Without this, a Polish
company buyer can pass step 1 with no NIP.

**Fix:** Add a validation to `:update_counterparty` that enforces `buyer_id`
presence when tax ID type requires it. Can be a new shared validation module
or inline.

### Gap 2: `CastBasedOnInvoiceType` writes `is_cash_account` (MEDIUM)

**Problem:** `Changes.CastBasedOnInvoiceType` calls
`force_change_attribute(:is_cash_account, false)` for `:foreign` invoice type.
WizardDraft has no `is_cash_account` attribute → latent runtime bug.

**Fix:** Guard the change module — check if the resource has the attribute
before writing. `Ash.Resource.Info.attribute(changeset.resource, :is_cash_account)`
→ only write if present.

### Gap 3: Non-empty items validation (MEDIUM)

**Missing from:** `:update_items` action in WizardDraft

**What `step2_changeset` does:** `cast_assoc(:sales_invoice_items, required: true)`
rejects submissions with zero items.

**Fix:** Add validation to `:update_items` — either `validate present([:items])`
or a custom validation that checks list length > 0.

## creator.ex migration plan

### Current state

- `step1/2/3_changeset` called from creator.ex for form validation/casting
- WizardDraft ETS resource + `confirm_from_draft` already handle persistence
- Doc 05 has complete AshPhoenix.Form replacement code

### New flow (per step)

Step 1 (counterparty):
```
AshPhoenix.Form.for_update(draft, :update_counterparty) |> to_form()
```

Step 2 (items with nested forms):
```
AshPhoenix.Form.for_update(draft, :update_items,
  forms: [items: [type: :list, resource: WizardDraft.Item, ...]]
) |> to_form()
```

Step 3 (payment):
```
AshPhoenix.Form.for_update(draft, :update_payment) |> to_form()
```

### What to remove from creator.ex

- All `AshSalesInvoice.step1_changeset` / `step2_changeset` / `step3_changeset` calls
- All `Ecto.Changeset.apply_action` calls
- All bare `struct(AshSalesInvoice)` construction for form seeding

### What to keep

- Counterparty selection flow (select_counterparty event → `WizardDraft.update_counterparty!`)
- Copy from invoice flow
- Preview + confirm flow (already uses `confirm_from_draft`)

## edit.ex migration plan

### Current state

Single `changeset/2` helper chains all 3 step changesets on the invoice struct.
Used for:
1. `to_form()` → HTML form
2. `apply_action(:update)` → plain struct for live PDF preview

Correction flow adds `prepare_correction_invoice_changeset` which pre-populates
a blank `%SalesInvoice{}` from the reference invoice.

### New flow

Regular edit:
```
AshPhoenix.Form.for_update(invoice, :update) |> to_form()
```

Correction:
```
AshPhoenix.Form.for_create(SalesInvoice, :create_correction, ...) |> to_form()
```

### Preview strategy (Option B)

Build preview struct from form values directly:

```elixir
defp build_preview_from_form(form) do
  values = AshPhoenix.Form.values(form)
  struct(AshSalesInvoice, values)
  # For correction: manually attach corrected_invoice from assigns
end
```

Drift protection: manual 1:1 comparison of PDF preview against localhost:4000
after every change.

### Correction flow specifics

- `prepare_correction_invoice_changeset` logic moves into the `:create_correction`
  action's initial values / arguments
- Correction preview must re-attach `corrected_invoice` association (original
  invoice) for PDF rendering — handle in `build_preview_from_form`

## Execution order with manual test gates

| # | Task | Test gate |
|---|------|-----------|
| 1 | Fix WizardDraft validation gaps (3 items) | Wizard: Polish company + empty NIP → reject. Foreign invoice type. Compare vs main |
| 2 | Migrate creator.ex to AshPhoenix.Form | Full wizard flow: new, copy, partial copy, add/remove items, reverse charge, series, draft, confirm. 1:1 vs main |
| 3 | Migrate edit.ex to AshPhoenix.Form | Edit draft, confirmed, KSeF-submitted (correction), PDF preview on every field change, bank account, correction reason. 1:1 vs main |
| 4 | KSeF end-to-end | Get token from ap-test portal. Submit → lock → update fields. Failure → unlock. Correction of submitted → KOR + submit. 1:1 vs main |
| 5 | Delete Ecto changeset layer (~650 lines) | Repeat full creator + edit + KSeF flows |
| 6 | Migrate tests | `mix check` all green |

## Field name mapping

| SalesInvoice (Ecto changeset) | WizardDraft (Ash) | Notes |
|------|------|-------|
| `sales_invoice_items` (association) | `items` (embedded attribute) | Intentional — different data layers |
| All buyer/seller/payment fields | Same names | Identical |
| `is_cash_account` | NOT present in WizardDraft | Only matters on persisted invoice |

## References

- Doc 05 (creator-wizard.md): complete AshPhoenix.Form code for each step
- Doc 06 (edit-view.md): edit view architecture
- Doc 04 (sales-invoice-write-actions.md): Phase 4b effective_* plan
- Doc 11 (delete-legacy.md): cleanup checklist
- AshPhoenix.Form docs: nested forms, for_update, for_create
