# Invoicing Migration Plan

Migration of SalesInvoices + CostInvoices + Invoicing contexts into a single `Firmowid.Ash.Invoicing` domain.

## Domain Structure

Single domain: `Firmowid.Ash.Invoicing` — all invoice-related resources live here.

## Migration Slices

### Slice 1: Counterparty (move + upgrade) — IN PROGRESS

**Goal:** Move `Firmowid.Ash.Core.Counterparty` read-only wrapper to `Firmowid.Ash.Invoicing.Counterparty` with full CRUD + search + validations + calculations.

#### New files (4)

1. **`lib/firmowid/ash/invoicing/invoicing.ex`** — Domain module
   - Registers `Firmowid.Ash.Invoicing.Counterparty`
   - Authorization: `authorize :by_default`, `require_actor? true`

2. **`lib/firmowid/ash/invoicing/counterparty.ex`** — Full resource
   - Table: `counterparties`, multitenancy via `organization_id`, `migrate? false`
   - **Attributes:** type, tax_id, full_name, given_name, surname, pesel, display_name, address, country, is_different_mail_address, mail_address, mail_country, email, phone, description
   - **Actions:**
     - `defaults [:read]`
     - `:by_id` — read, `get_by [:id]`, `not_found_error? true`
     - `:list_all` — read, sorted by `COALESCE(display_name, surname)` asc
     - `:create` — accept all public attributes, changes: validate_country_codes, validate_tax_id, validate_name_fields, cast_based_on_type
     - `:update` — same changes as create
     - `:destroy` — default
     - `:search` — generic action. Args: `search_term` (string), `type` (atom, optional), `sort_by` (atom, optional), `sort_order` (atom, optional). Runs raw ParadeDB Ecto query. Returns list of Counterparty structs.
   - **Calculations:**
     - `:display_label` — string. Logic: display_name if present, else full_name for company, else "given_name surname" for individual.
     - `:tax_id_type` — atom (`:nip | :eu_vat | :other_id | :optional_id | :no_id`). Logic: `CountryCodes.tax_id_type(country, pesel, type)`.
   - **Public functions on module:** `validate_nip/2`, `validate_eu_vat/2`, `validate_optional_id/2` — reused by SalesInvoice Ecto schema via import.
   - **Relationships:** `belongs_to :organization, Firmowid.Ash.Core.Organization`
   - **Policies:** `authorize_if always()` for all action types
   - **Code interface:** `list_all!`, `get!`, `create`, `update`, `destroy!`, `search`

3. **`lib/firmowid/ash/invoicing/calculations/counterparty_display_label.ex`**
4. **`lib/firmowid/ash/invoicing/calculations/counterparty_tax_id_type.ex`**

#### Deleted files (1)

- `lib/firmowid/ash/core/counterparty.ex`

#### Modified files (8)

| File | Change |
|------|--------|
| `config/config.exs` | Add `Firmowid.Ash.Invoicing` to `ash_domains` |
| `lib/firmowid/ash/core/core.ex` | Remove `resource Firmowid.Ash.Core.Counterparty` |
| `lib/firmowid/ash/timetracker/project.ex` | `belongs_to :counterparty` → `Firmowid.Ash.Invoicing.Counterparty` |
| `creator.ex` (sales invoices LiveView) | Replace `SalesInvoices.list_counterparties()` → `Counterparty.list_all!(scope: scope)`. Replace `SalesInvoices.search_counterparties(...)` → `Counterparty.search(...)`. Replace `SalesInvoices.get_counterparty!(id)` → `Counterparty.get!(id, scope: scope)` + `Ash.load!(c, [:tax_id_type])`. Update alias. |
| `edit.ex` (sales invoices LiveView) | Replace `SalesInvoices.list_counterparties()` → `Counterparty.list_all!(scope: scope)`. Add alias. |
| `project.ex` (management view) | Alias → `Firmowid.Ash.Invoicing.Counterparty`. `Counterparty.display_label(...)` → `project.counterparty.display_label` (loaded calculation). Ensure Project read loads `counterparty: [:display_label]`. |
| `projects.ex` (management view) | Same as project.ex. |
| `lib/firmowid/sales_invoices.ex` | Delete ~100 LOC: `list_counterparties`, `get_counterparty/!`, `create_counterparty`, `update_counterparty`, `delete_counterparty`, `search_counterparties`, `change_counterparty`, private helpers. |

#### Kept as-is (dies in Slice 7)

- `lib/firmowid/sales_invoices/counterparty.ex` — Ecto schema. Needed because:
  - `SalesInvoice` Ecto schema has `belongs_to :counterparty, Counterparty`
  - `SalesInvoice` imports `validate_nip/2`, `validate_eu_vat/2`, `validate_optional_id/2` from it
  - Validation functions exist in both modules until SalesInvoice migrates

#### Verification

- `mix check` passes
- Creator: counterparty search works, selection populates buyer fields
- Edit: counterparty list loads
- Management: project pages show counterparty display names
- Timetracker: projects with counterparties still function

---

### Slice 2: InboundEmail

**Goal:** New `Firmowid.Ash.Invoicing.InboundEmail` resource. Replace context functions.

- Actions: `:read`, `:create`, `:mark_processed` (update — sets `processed_at` + `failure_reason`)
- Delete from `CostInvoices` context: `list_inbound_emails`, `get_inbound_email!`, `create_inbound_email`, `mark_inbound_email_processed`
- Update call sites: `inbound_email_worker.ex`, `inbox.ex` view, `cost_invoices/worker.ex`
- Ecto schema `CostInvoices.InboundEmail` stays (referenced by CostInvoice Ecto schema `belongs_to`)

---

### Slice 3: Transaction connections (unified)

**Goal:** Both join tables as Ash resources with shared pattern.

- `Firmowid.Ash.Invoicing.SalesInvoiceTransaction` on `sales_invoices_transactions`
- `Firmowid.Ash.Invoicing.CostInvoiceTransaction` on `cost_invoices_transactions`
- Actions: `:create_connection` (takes invoice_id + transaction_id), `:delete_for_invoice` (generic — delete all for an invoice)
- Replaces `Ecto.Multi` pattern in both contexts
- Update ~8 call sites (show views, invoicing matching, assistants)
- Delete from both contexts: `create_*_transactions_connection`, `delete_*_transactions_connections`

---

### Slice 4: CostInvoice reads

**Goal:** Ash resource on `cost_invoices` table with read actions.

- `Firmowid.Ash.Invoicing.CostInvoice`
- Read actions: `:read`, `:by_id`, `:list_by_date_range`, `:list_unmatched`, `:list_by_sale_date`, `:list_by_ids`, `:list_invoices_in_date_range`
- `blob_url` as calculation (replaces `AshBlob.get_url!/2` bridge)
- Relationships: `belongs_to :blob` (Ash.Blobs.Blob), `many_to_many :transactions` (via Ash join), `has_many :correction_invoices`, `belongs_to :original_invoice`, `has_many :entity_tags`, `belongs_to :inbound_email`
- Correction merging logic as post-read function or calculation
- Ecto schema stays for writes (Slice 6)

---

### Slice 5: SalesInvoice reads

**Goal:** Ash resource on `sales_invoices` table with read actions.

- `Firmowid.Ash.Invoicing.SalesInvoice`
- Read actions: `:read`, `:by_id`, `:list_by_date_range`, `:list_unmatched`, `:list_by_sale_date`, `:list_by_ids`, `:list_recent`, `:search`, `:by_share_token`
- Calculations: `gross_value`, `net_value`, `vat_value`, `buyer_display_name`, `logo_url`, `currency_rate`
- Relationships: `belongs_to :counterparty` (Ash.Invoicing.Counterparty), `many_to_many :transactions`, `has_many :corrections`, `belongs_to :corrected_invoice`, `has_many :sales_invoice_items`, `has_many :entity_tags`
- Correction chain logic (`populate_reference_invoices`, `get_latest_invoice_snapshot`) as resource functions or generic actions
- Ecto schema stays for writes (Slice 7)

---

### Slice 6: CostInvoice mutations

**Goal:** Add write actions to CostInvoice Ash resource. Delete CostInvoices context.

- Actions: `:create_from_metadata`, `:destroy` (with blob cleanup + billing decrement), `:toggle_skip`, `:upload` (generic — blob + extraction job), `:hydrate_with_fa3_blob`
- Move `CostInvoices.Worker` to `Firmowid.Ash.Invoicing.CostInvoiceWorker`
- PubSub: explicit broadcasts or Ash notifier
- Delete `lib/firmowid/cost_invoices.ex` context module
- Bodyguard removed from cost invoices

---

### Slice 7: SalesInvoice mutations

**Goal:** Add write actions to SalesInvoice Ash resource. Delete SalesInvoices context.

- Actions: `:create`, `:update`, `:create_correction`, `:cancel`, `:delete`, `:toggle_skip`, `:create_share_token`
- **Wizard step actions (Option A):** `:validate_step1`, `:validate_step2`, `:validate_step3` — separate Ash actions for multi-step Creator form validation. AshPhoenix.Form drives the LiveView.
- Invoice number series logic — module functions on the resource (pure query + format logic)
- `SalesInvoiceItem` — embedded resource or managed relationship
- Delete `lib/firmowid/sales_invoices.ex` context module
- Delete `lib/firmowid/sales_invoices/counterparty.ex` Ecto schema (no longer needed)
- Bodyguard removed from sales invoices

---

### Slice 8: Invoicing dissolution

**Goal:** Dissolve Invoicing context. Move orchestration to Ash domain.

- `search_invoices` → generic action on domain or utility module (raw ParadeDB, stays Ecto)
- `get_invoicing_entries` + `order_entries_for_display` → utility module under `Firmowid.Ash.Invoicing`
- `get_all_months_with_invoicing_entries` → generic action or utility
- `get_potential_transactions_for_invoice` → utility
- Auto-matching (`match_cost_invoice`, `match_sales_invoice`) → worker calls Ash code interfaces
- PubSub → Ash notifiers on resources or explicit broadcast calls
- Delete `lib/firmowid/invoicing.ex` context module
- **Bodyguard dep removal check:** after this slice, verify remaining Bodyguard usage (BankData, Accounts still pending from other migration tracks)

---

## Decisions Made

- **Domain structure:** Option A — single `Firmowid.Ash.Invoicing` domain for all resources
- **Wizard changesets:** Option A — separate Ash actions per step (`:validate_step1`, etc.) when we reach Slice 7
- **Calculations:** Option A — Ash calculations for `display_label` and `tax_id_type`, loaded explicitly at call sites. Also exposed as public functions on the module for imperative use.
- **ParadeDB search:** stays as raw Ecto in generic actions (Ash filter DSL has no ParadeDB predicate)

## Conventions

- Callers explicitly load calculations — no `prepare build(load: [...])` on actions
- LiveViews use `scope: socket.assigns.ash_scope`
- Workers/un-migrated contexts use `[authorize?: false, actor: %{}]` with `# TODO: replace authorize?: false + actor: %{} with system actor once available`
- `migrate? false` on all resources — all migrations hand-written
- Ecto schemas kept alive until all their dependents migrate (die by starvation)

## Discoveries

- Management views (`project.ex`, `projects.ex`) alias `Firmowid.SalesInvoices.Counterparty` but only use `Counterparty.display_label/1` in templates — called on structs loaded through Ash Project's `belongs_to :counterparty`
- `SalesInvoice` Ecto schema imports `validate_nip/2`, `validate_eu_vat/2`, `validate_optional_id/2` from Counterparty — these must remain available until Slice 7
- Creator LiveView calls `Counterparty.tax_id_type/1` on a freshly-fetched struct — needs the calculation loaded or a direct function call
- The two transaction join tables (`SalesInvoicesTransactions`, `CostInvoicesTransactions`) have identical shape and usage patterns — strong deduplication candidate in Slice 3
- CostInvoice correction chain uses `original_invoice_ksef_number` ↔ `ksef_number` (string FK), while SalesInvoice uses `corrected_invoice_id` (UUID FK) — different mechanisms, same concept
