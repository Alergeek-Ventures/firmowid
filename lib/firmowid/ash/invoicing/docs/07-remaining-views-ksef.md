# Phase 7: Rewrite Remaining Views + KSeF Workers

## Goal

Swap all remaining legacy context/schema references in views, controllers, and KSeF workers
to use Ash code interfaces.

## Views

### show.ex

Replace:
- `SalesInvoices.delete_sales_invoice(invoice)` → `SalesInvoice.destroy!(invoice, scope:)`
- `SalesInvoices.cancel_sales_invoice(invoice)` → `SalesInvoice.cancel!(invoice.id, scope:)`
- `SalesInvoices.toggle_skip_invoicing(id)` → `SalesInvoice.toggle_skip!(invoice, scope:)`
- `SalesInvoices.create_or_get_share_token(invoice)` → `SalesInvoice.generate_share_token!(invoice, scope:)`
- `SalesInvoices.populate_logo_url(invoice)` → `SalesInvoice.populate_logo_url(invoice)` (already on Ash module)
- `SalesInvoices.populate_reference_invoices(invoice)` → `SalesInvoice.populate_reference_invoices(invoice)` (already on Ash module)
- Bodyguard checks → removed (Ash policies)

### summary.ex

Replace:
- `SalesInvoices.get_currency_rate(invoice)` → `SalesInvoice.get_currency_rate(invoice)` (already)
- `SalesInvoices.populate_logo_url` → already on Ash module
- Any remaining `SalesInvoices` context calls

### invoice_items.ex component

Replace:
- `alias Firmowid.SalesInvoices.SalesInvoice` → `alias Firmowid.Ash.Invoicing.SalesInvoice`
- `alias Firmowid.SalesInvoices.SalesInvoiceItem` → `alias Firmowid.Ash.Invoicing.SalesInvoiceItem`
- `SalesInvoice.get_net_value/1` etc. → already on Ash module

### template.ex component

Same alias swaps.

### pdf.ex controller

Replace:
- `SalesInvoices.get_sales_invoice!(id)` → `SalesInvoice.by_id!(id, scope:)`
- `SalesInvoices.populate_logo_url` → `SalesInvoice.populate_logo_url`
- `SalesInvoices.get_currency_rate` → `SalesInvoice.get_currency_rate`
- Bodyguard check → Ash policy (or keep simple role check inline)

### shared.ex controller (public invoice view)

Replace:
- `SalesInvoices.get_invoice_by_share_token(token)` → `SalesInvoice.by_share_token(token, scope:)` (already exists)
- `SalesInvoices.populate_logo_url` → already on Ash module

## Bodyguard removal in `.heex` templates

These inline `Bodyguard.permit?` calls in templates are easy to miss during migration.
They must be replaced with whatever naive authorization check the codebase uses
(currently `authorize_if always()` means every authenticated user passes).

| File | Line | Current | Replacement |
|---|---|---|---|
| `invoicing/views/index.html.heex` | 42 | `permit?(SalesInvoices, :create_sales_invoice, @current_user)` | Remove conditional (always true) or use Ash `can?` |
| `invoicing/views/index.html.heex` | 60 | `permit?(Invoicing, :upload, @current_user)` | Same |
| `invoicing/views/index.html.heex` | 190 | `permit?(Invoicing, :read, @current_user)` | Same |
| `invoicing/views/index.html.heex` | 209 | `permit?(Invoicing, :upload, @current_user)` | Same |
| `infrastructure/layouts/app.html.heex` | 29 | `permit?(Firmowid.Invoicing, :show, @current_user)` | Same |

Also remove Bodyguard in `.ex` files (38 callsites across 8 files — see grilling audit).
With `authorize_if always()` policies, Ash actions succeed for any authenticated user.
The `Bodyguard.permit!` calls become unnecessary — Ash policies enforce authorization
automatically when actions are called with an actor.

For views that call `Bodyguard.permit!` in `mount` or `handle_event`, simply remove the call.
The Ash action itself will raise `Ash.Error.Forbidden` if the policy denies.

## KSeF Workers

### submission_worker.ex

This worker locks an invoice, renders XML, submits to KSeF, and updates KSeF fields.
**Not just alias swaps** — the `ksef_update_changeset` calls are Ecto changeset operations
that must become Ash action calls:

| Legacy call | Ash replacement | Notes |
|---|---|---|
| `SalesInvoices.get_sales_invoice!(id)` | `SalesInvoice.by_id!(id, scope:)` | Alias swap |
| `SalesInvoices.get_sales_invoice(id)` | `SalesInvoice.by_id(id, scope:)` | Alias swap |
| `SalesInvoice.ksef_update_changeset(invoice, %{locked_at: now}) \|> Repo.update!()` | `SalesInvoice.lock_for_ksef!(invoice, scope:)` | Changeset → Ash action |
| `SalesInvoice.ksef_update_changeset(invoice, %{locked_at: nil}) \|> Repo.update!()` | `SalesInvoice.unlock_for_ksef!(invoice, scope:)` | Changeset → Ash action |
| `SalesInvoice.ksef_update_changeset(invoice, %{ksef_number: ..., ...}) \|> Repo.update!()` | `SalesInvoice.update_ksef_fields!(invoice, %{...}, scope:)` | Changeset → Ash action |
| `SalesInvoice.ksef_submission_changeset(invoice)` | Validate via Ash validation or keep as standalone check | Pre-submission validation |
| `SalesInvoice.draft?(invoice)` | `SalesInvoice.draft?(invoice)` | Already on Ash module |
| `SalesInvoice.ksef_submitted?(invoice)` | `SalesInvoice.ksef_submitted?(invoice)` | Already on Ash module |

#### Repo.transaction → Ash.DataLayer.transaction

The lock + schedule flow is currently wrapped in `Repo.transaction`. An app crash
between lock and schedule would leave the invoice locked with no submission queued.
Use `Ash.DataLayer.transaction` — it shares the same Repo connection, and Oban's
`insert!` within it participates in the same Postgres transaction:

```elixir
Ash.DataLayer.transaction(SalesInvoice, fn ->
  invoice = SalesInvoice.lock_for_ksef!(invoice, scope: scope)
  Oban.insert!(SubmissionWorker.new(%{sales_invoice_id: invoice.id}))
  invoice
end, tenant: org_id)
```

### invoice_renderer.ex

Uses `%SalesInvoice{}` struct to render XML. Since Ash structs have the same fields,
this is primarily alias swaps:

| Legacy call | Ash replacement | Status |
|---|---|---|
| `alias Firmowid.SalesInvoices.SalesInvoice` | `alias Firmowid.Ash.Invoicing.SalesInvoice` | Alias swap |
| `alias Firmowid.SalesInvoices.SalesInvoiceItem` | `alias Firmowid.Ash.Invoicing.SalesInvoiceItem` | Alias swap |
| `SalesInvoices.populate_reference_invoices(invoice)` | `Ash.load!(invoice, [:reference_invoice])` | Function → calculation. Callsite loads. |
| `Repo.preload(invoice, [...])` | Callsite loads via `:by_id` action or explicit `Ash.load!` | Callsite decides. |
| `SalesInvoice.get_gross_value(invoice)` | `SalesInvoice.get_gross_value(invoice)` | ✅ Already on Ash module |
| `SalesInvoice.buyer_id_type(invoice)` | `SalesInvoice.buyer_id_type(invoice)` | ✅ Already on Ash module |
| `SalesInvoiceItem.get_net_value(item)` | `SalesInvoiceItem.get_net_value(item)` | ✅ Already on Ash module |
| `SalesInvoiceItem.get_vat_value(item)` | `SalesInvoiceItem.get_vat_value(item)` | ✅ Already on Ash module |
| `Map.from_struct/1` on structs | Works the same on Ash structs | No change |

The renderer's callsite (submission_worker) must ensure the invoice is loaded with:
`[:sales_invoice_items, :reference_invoice, corrected_invoice: :sales_invoice_items]`

### ksef.ex context

Replace:
- `SalesInvoices.get_sales_invoice!(id)` → `SalesInvoice.by_id!(id, scope:)`
- `SalesInvoice.ksef_update_changeset(invoice, %{ksef_invoice_checksum: checksum}) |> Repo.update!()` → `SalesInvoice.update_ksef_fields!(invoice, %{ksef_invoice_checksum: checksum}, scope:)` (in `backfill_ksef_checksum!/1`)
- Any other context calls

### KsefTestHelpers — rewritten (Done)

Rewritten to use `Ash.Seed.seed!` for all fixture creation. Stays in `test/ksef_helpers.ex`
because it depends on `:erlsom` (test-only dependency) — cannot be compiled in `lib/`.

All fixture functions use `Ash.Seed.seed!` + separate item seeding. No legacy context calls.

## Testing

Primarily manual testing:
1. View invoice → verify all data displays correctly
2. Delete invoice → verify deletion
3. Cancel invoice → verify correction created
4. Toggle skip → verify flag toggled
5. Share invoice → verify token generated, public view works
6. PDF download → verify PDF renders
7. KSeF submission → verify lock → submit → update fields flow
8. KSeF submission failure → verify unlock
