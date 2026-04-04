# Phase 11: Delete Legacy Code

## Goal

Delete all legacy Ecto schemas, contexts, and the Cachex draft store.
Run `mix check` — all green. Manual test everything.

## Files to delete — status

### Ecto schemas — all DELETED
- ~~`lib/firmowid/sales_invoices/sales_invoice.ex`~~ — deleted
- ~~`lib/firmowid/sales_invoices/sales_invoice_item.ex`~~ — deleted
- ~~`lib/firmowid/sales_invoices/counterparty.ex`~~ — deleted
- ~~`lib/firmowid/sales_invoices/sales_invoices_transactions.ex`~~ — deleted
- ~~`lib/firmowid/cost_invoices/cost_invoice.ex`~~ — deleted
- ~~`lib/firmowid/cost_invoices/cost_invoices_transactions.ex`~~ — deleted
- ~~`lib/firmowid/cost_invoices/inbound_email.ex`~~ — deleted

### Contexts — all DELETED
- ~~`lib/firmowid/sales_invoices.ex`~~ — deleted
- ~~`lib/firmowid/invoicing.ex`~~ — deleted

### Draft store — DELETED
- ~~`lib/firmowid/sales_invoices/creator_draft_store.ex`~~ — deleted (replaced by WizardDraft ETS resource)

### Application supervisor — CLEANED UP
- ~~`Supervisor.child_spec({Cachex, name: :creator_drafts}, id: :creator_drafts_cache)`~~ — removed
  (WizardDraft ETS resource replaces Cachex-backed draft store)

### Ecto changeset layer in Ash resources — STILL ACTIVE (form building only, not persistence)
- `sales_invoice.ex`: ~650 lines of Ecto changeset functions (lines ~1239-1894: `changeset/2`,
  `step1/2/3_changeset`, `prepare_correction_invoice_changeset`, plus ~20 private helpers
  including `normalize_reverse_charge_item_vat_rate`, `cast_buyer_based_on_type`,
  `validate_country_code`, `validate_buyer_id`, `calculate_due_date_from_params`, etc.)
- `sales_invoice_item.ex`: `changeset/3` function (~20 lines)
- `import Ecto.Changeset` in both files
- `@snapshot_fields`, `merge_corrections_after_read`, `buyer_id_type(%Ecto.Changeset{})`

**Note:** These are used only for form building in LiveViews (creator.ex, edit.ex) and
tests (sales_invoices_test.exs). All write persistence goes through Ash actions.

### Dead code already removed
- `ksef_submission_changeset/1` — removed (0 callers)
- `validate_seller_name/1`, `validate_buyer_identification/1` — removed (only called from above)
- `CreatorDraftStore` — deleted (replaced by WizardDraft ETS resource)
- Cachex `:creator_drafts` supervisor entry — removed

## Test files — status

| Test file | Status | Notes |
|---|---|---|
| `lib/firmowid/sales_invoices_test.exs` | Uses step changeset functions — blocked by Phase 5+6 | Once Ecto changeset layer is removed, step tests should test WizardDraft actions |
| `lib/firmowid/invoicing_search_test.exs` | DONE — uses `Ash.Seed.seed!` | Fully migrated |
| `lib/firmowid/ksef/invoice_renderer_test.exs` | DONE — uses `Ash.Seed.seed!` via KsefTestHelpers | Fully migrated |
| `lib/firmowid/ksef/invoice_correction_test.exs` | DONE — uses `Ash.Seed.seed!` via KsefTestHelpers | Fully migrated |
| `test/ksef_helpers.ex` | DONE — rewritten to `Ash.Seed.seed!` | Stays in `test/` (depends on `:erlsom` test dep) |

### Test fixture patterns

Use `Ash.Seed` or Ash code interfaces for test fixture creation. Do NOT use `Repo.insert!`
with Ash resource structs — use `Ash.Seed.seed!` or `SalesInvoice.create!`.

**Established pattern** (from `finances_test.exs`):

```elixir
setup do
  user = user_fixture()
  org_id = user.organization_id
  seed_opts = [tenant: org_id]

  invoice = Ash.Seed.seed!(SalesInvoice, %{
    invoice_number: "TEST/01/2024",
    organization_id: org_id,
    ksef_invoice_kind: :vat,
    invoice_type: :poland,
    currency: "PLN",
    issue_date: ~D[2024-01-15],
    sale_date: ~D[2024-01-15],
    due_date: ~D[2024-01-29],
    payment_method: :transfer,
    seller_nip: "1234567890",
    seller_display_name: "Test Seller",
    seller_address: "Test Address",
    seller_account_number: "PL12345678901234567890123456",
    buyer_type: :company,
    buyer_full_name: "Test Buyer",
    buyer_address: "Buyer Address",
    buyer_country: "PL",
    buyer_id: "9876543210"
  }, seed_opts)

  # Items seeded separately:
  item = Ash.Seed.seed!(SalesInvoiceItem, %{
    sales_invoice_id: invoice.id,
    organization_id: org_id,
    index: 0,
    name: "Test item",
    quantity: Decimal.new("1"),
    unit: "szt.",
    unit_price: Decimal.new("100.00"),
    vat_rate: "23"
  }, seed_opts)

  %{user: user, org_id: org_id, invoice: invoice, item: item}
end
```

**When to use what:**

| Approach | When |
|---|---|
| `Ash.Seed.seed!` | Simple fixtures — record in DB, no side effects, no relationship management |
| `SalesInvoice.create!(attrs, authorize?: false, actor: %{}, tenant: org_id)` | When testing write actions or when items need `manage_relationship` |
| `AshPhoenix.Form.submit` | When testing form flows (wizard tests) |

### Step changeset tests → WizardDraft tests

`sales_invoices_test.exs` tests `step1_changeset`, `step2_changeset`, `step3_changeset`.
These test the same user paths that WizardDraft actions now handle. Move to Phase 2
test file (colocated with WizardDraft):

- `step1_changeset` buyer type switching, tax ID validation → `WizardDraft.update_counterparty` tests
- `step2_changeset` items + reverse charge VAT normalization → `WizardDraft.update_items` tests
- `step3_changeset` payment + due date calculation → `WizardDraft.update_payment` tests

Remaining tests in `sales_invoices_test.exs` (locked invoice, skip_invoicing toggle, VAT
rate normalization on confirmed invoices) → Phase 4 test file (colocated with SalesInvoice).

## Pre-deletion checklist

Before deleting each file, verify NO remaining references:

```bash
# For each file, search for references to its module
rg "Firmowid.SalesInvoices.SalesInvoice[^IT]" --type elixir
rg "Firmowid.SalesInvoices.SalesInvoiceItem" --type elixir
rg "Firmowid.SalesInvoices.Counterparty[^D]" --type elixir  # exclude CountryCodes
rg "Firmowid.CostInvoices.CostInvoice[^T]" --type elixir
rg "Firmowid.CostInvoices.InboundEmail" --type elixir
rg "Firmowid.SalesInvoices\." --type elixir  # context functions
rg "Firmowid.Invoicing\." --type elixir  # context functions (not Ash.Invoicing)
rg "CreatorDraftStore" --type elixir
```

Each search must return zero hits (or only the file being deleted).

## Post-deletion verification

1. `mix compile --warnings-as-errors` — no undefined references
2. `mix format --check-formatted`
3. `mix credo --strict`
4. `mix sobelow --config`
5. `mix test` — all pass
6. `mix check` — all green

## Manual testing checklist

### Creator wizard
- [ ] Start new wizard → drafts creates
- [ ] Select counterparty from list → step advances
- [ ] Add counterparty manually → validates, step advances
- [ ] Add items → nested forms work
- [ ] Add/remove items → form updates correctly
- [ ] VAT rate normalization → reverse charge forces "oo"
- [ ] Payment step → due date calculation works
- [ ] Preview → correct number suggested
- [ ] Series selection → number updates
- [ ] Confirm → invoice created, draft destroyed
- [ ] Save as draft → invoice without number
- [ ] Copy from invoice → draft populated
- [ ] Partial copy (invalid counterparty) → lands on counterparty step

### Edit view
- [ ] Edit draft → updates correctly
- [ ] Edit confirmed invoice → updates
- [ ] Edit KSeF-submitted → correction form shown
- [ ] Create correction → correction invoice created with KOR
- [ ] Auto correction reason → generates
- [ ] User-edited correction reason → preserved
- [ ] Bank account selection → updates
- [ ] Live PDF preview → updates on change

### Show view
- [ ] View invoice → all data correct
- [ ] Delete draft → deleted
- [ ] Delete confirmed → deleted
- [ ] Delete KSeF-submitted → error
- [ ] Cancel invoice → zero-correction created
- [ ] Toggle skip → flag flipped
- [ ] Share → token generated
- [ ] Public view via share link → works

### Invoicing dashboard
- [ ] Date navigation → entries load
- [ ] Filter: all / unmatched / invoices / transactions → works
- [ ] Search → results show
- [ ] Search with filters → works
- [ ] Matching sidebar → shows potential transactions
- [ ] Create connection → join created
- [ ] Auto-matching → works (via worker)

### KSeF
- [ ] Submit to KSeF → lock → submit → update fields
- [ ] KSeF failure → unlock
- [ ] KSeF credential missing → appropriate message

### PDF
- [ ] Download PDF → renders correctly
- [ ] PDF with correction → shows correction data
- [ ] PDF with currency rate → shows rate
