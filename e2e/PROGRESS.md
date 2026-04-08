# E2E Progress — Ash Refactor Branch

Date: 2026-04-08

## Manual status summary

- S01 ✅ PASS (authentication)
- S02 ✅ PASS (KSeF token connect/disconnect)
- S03 ✅ PASS after fixes (status lifecycle + accessibility labels)
- S04 ⚠️ PARTIAL (core flow works; transient KSeF token expiry/retry observed)
- S05 ✅ PASS (send to KSeF works)
- S06 ⏸️ DEFERRED (cost upload flow known broken; scheduled for pairing)
- S07 ✅ PASS
- S08 ✅ SCRIPTED PASS (deterministic previous-month aggregate assistant match + acceptance path)
- S09 ✅ PASS (accepted as-is)
- S10 ✅ PASS
- S11 ✅ PASS after fix (edit flow no longer crashes with Money.Invalid)
- S12 ✅ SCRIPTED PASS after fixes (month ZIP selection + download contract)
- S13 ✅ PASS (feature present)
- S14 ✅ PASS
- S15 ✅ PASS after fix
- S16 ✅ PASS after fix (archive/unarchive stable)
- S17 ✅ PASS after fix
- S18 ✅ PASS after fix (invite flow updates employee list without manual refresh)
- S19 ✅ PASS
- S20 ✅ PASS
- S21 ✅ PASS
- S22 ✅ PASS after fix (submit flow + role consistency)
- S23 ⚠️ ACCEPTED AS-IS (deferred polish)
- S24 ⚠️ PARTIAL after fix (project CSV schema corrected; global route without params now redirects safely)
- S25 ✅ PASS
- S26 ✅ PASS
- S27 ✅ PASS after fix (security page render no longer crashes)
- S28 ✅ PASS after fix (malformed tags no crash)
- S29 ✅ PASS after fix (invoicing role permissions aligned)
- S30 ✅ PASS after fix (route reachable, data blocked for employee)

## Implemented fixes

### S03 — GoCardless sync/status lifecycle

- Requisition state machine converged to `status` as single source of truth.
- Added converged migration to drop legacy `requisitions.state` if present.
- `check_status` now maps GoCardless `:not_found` to `:reject` transition.
- Added explicit lifecycle semantics in settings:
  - red failure overrides waiting,
  - accepted+no successful sync -> blue waiting,
  - successful sync -> green connected.
- Added status `aria-label`/`title` for icon semantics.

Validation:
- Manual S03: PASS (blue -> green transition observed, rename/default verified)
- Scripted: `mix e2e e2e/test/s03_sandbox_bank_account_test.exs` PASS

### S11 — Edit invoice crash (`Money.Invalid`)

- Fixed preview data contract in sales invoice edit flow by computing item and invoice monetary totals from form values before rendering template.
- Eliminated nil amounts reaching `Money.new!/2` in foreign preview path during edit/validate rerender.

Validation:
- Manual S11: PASS (save draft from edit works, totals update, no crash)
- Scripted regression test added: `lib/firmowid_web/invoicing/sales_invoices/views/edit_test.exs`

### S15/S17 — Project form crashes

- Fixed user-list loading path in project form to avoid invalid tenantless Blob queries.
- Project create and edit forms now render and submit.

Validation:
- Manual S15: PASS
- Manual S17: PASS

### S16 — Unarchive flow instability

- Added proper error handling in LiveView handlers (avoid crashing on action errors).
- Unarchive action now runs non-atomically where required by hooks.
- Verified archive -> unarchive removes item from archive and returns it to active list.

Validation:
- Manual S16 final retest: PASS
- Resource + view tests: PASS

### S24 — CSV project export schema

- Project CSV (`/czasosledz/projekty/:id/csv`) now exports session rows with columns:
  - `Użytkownik,Data,Czas trwania,Tytuł`
- Global CSV without required params no longer crashes; redirects with user-facing message.

Validation:
- Manual S24 project CSV with params: PASS
- Manual S24 global route without params: safe redirect PASS
- Scripted controller test added: `lib/firmowid_web/timetracker/controllers/csv_test.exs`

### S27 — Security settings crash

- Fixed missing `@trigger_submit` assign in settings security view.
- Replaced stale `@current_user.google_provider_id` usage with explicit `@google_connected?` derived from `UserIdentity`.
- Password confirmation field marked required in UI.

Validation:
- Manual S27 render + submit path: PASS
- Scripted regression test added: `lib/firmowid_web/settings/views/security_test.exs`

### S28 — Analysis dashboard crash (`FunctionClauseError`)

- Made tag key decoder total; unknown tag keys are safely ignored during query param parsing.

Validation:
- Manual malformed URL `/analiza?tags=company,foo,project`: PASS
- Scripted regression test added: `lib/firmowid_web/analysis/views/dashboard_test.exs`

### S30 — Employee management access behavior

- Preserved route accessibility for employee role.
- Blocked management data loading for non-admin in employees list/details.
- Prevented detail data disclosure via direct URL for employee role.

Validation:
- Manual S30: PASS (list empty, direct detail blocked)
- Scripted regression test added: `lib/firmowid_web/management/views/access_test.exs`

### S18 — Employee invite flow deferred refresh fixed

- Fixed data-flow root cause of deferred visibility in `/zarzadzanie/pracownicy`:
  employees LiveView now subscribes to user organization-join events and refetches
  immediately when an invite is consumed.
- Added `User` pub-sub publication for `:set_organization` action:
  `user:joined_org:<organization_id>`.
- Kept consistency with existing Ash notifier architecture (no polling/no UI-only hacks).
- Fixed invite resource action internals discovered during deterministic coverage:
  - consume validation now uses `attribute_equals(:consumed_at, nil)`
  - consume `after_action` callback arity updated to 3 (`changeset, result, context`)

Validation:
- Scripted deterministic tests added: `lib/firmowid_web/management/views/employees_test.exs`
  - invite consumption makes new employee visible in admin list without refresh
  - admin can set hourly rate for newly joined employee
- Nearby regressions:
  - `mix test lib/firmowid_web/management/views/access_test.exs lib/firmowid_web/management/views/projects_test.exs` PASS
  - `mix test lib/firmowid_web/invoicing/views/role_access_test.exs` PASS
  - `mix test lib/firmowid_web/hours_record/views/index_test.exs` PASS

### S22 — Submit hours record + role consistency

- Fixed Hours Record index data refetch to always pass Ash scope when reading monthly totals.
  This removed an actor-less authorization failure path in LiveView.
- Hardened `/czasosledz/ewidencja/:id` download action:
  unauthorized/not-found record access now redirects safely to `/czasosledz`
  with a user-facing error instead of raising.
- Added deterministic LiveView coverage for employee S22 flow:
  month breakdown render, PDF link presence, signed upload submit, and `WYSŁANO` status.

Validation:
- Scripted: `mix test lib/firmowid_web/hours_record/views/index_test.exs lib/firmowid_web/hours_record/controllers/record_test.exs` PASS
- Nearby regressions: `mix test lib/firmowid/ash/timetracker/hours_record_test.exs lib/firmowid/ash/timetracker_payroll_policies_test.exs lib/firmowid_web/management/views/access_test.exs lib/firmowid_web/timetracker/views/index_test.exs` PASS

### S29 — Invoicing role access behavior

- Added dedicated admin-only route guard for `/zarzadzanie/*` LiveViews using `RequireAdmin` on-mount hook.
- Preserved invoicing-role access to `/fakturowanie` and `/czasosledz`.
- Hardened sales invoice creator access for non-accountant roles:
  - UI remains hidden for non-admin on invoicing hub.
  - Direct `/sprzedazowe` access now redirects to `/fakturowanie` with a user-facing permission flash instead of crashing.
- Fixed invoicing hub render path for non-admin users by removing unconditional `@uploads` usage in template and making upload counters safe when uploads are unavailable.
- Extended `HoursRecord` read policy to allow `:invoicing` users to read only their own monthly record, unblocking `/czasosledz` mount for that role.

Validation:
- Scripted: `mix test lib/firmowid_web/management/views/access_test.exs lib/firmowid_web/invoicing/views/role_access_test.exs lib/firmowid_web/management/views/projects_test.exs lib/firmowid_web/invoicing/sales_invoices/views/summary_test.exs` PASS
- Additional focused regressions:
  - `mix test lib/firmowid/ash/timetracker/hours_record_test.exs lib/firmowid_web/timetracker/views/index_test.exs lib/firmowid_web/invoicing/views/index_test.exs` PASS

### S12 — Download invoices for a month

- Fixed download modal attr contract for month assign (LiveView passes `Date`, component now accepts generic assign type).
- Enabled `include_sales` by default in month download modal so the default ZIP includes sales invoices (matching S12 expectation for invoices of selected month).
- Extracted monthly ZIP entry selection to dedicated service `MonthDownloadEntries` to make month/type rules deterministic and testable.
- Service now uses Ash read with explicit actor/tenant opts and loads required sales display calculation (`:buyer_display_name_label`) to avoid runtime `Ash.NotLoaded` failures.
- Controller remains responsible for stream transport (`Packmatic.Conn.send_chunked`), delegating selection logic to service.

Validation:
- Scripted deterministic coverage added:
  - `lib/firmowid/ash/invoicing/services/month_download_entries_test.exs`
    - month selection uses `date_field: :any` (issue/sale/due date semantics)
    - file-type include filters (pdf/xml/photos)
    - sales toggle behavior
  - `lib/firmowid_web/invoicing/components/download_modal_test.exs`
    - modal rendered on invoicing page when month has entries
    - generated download href contains `include_sales=true` by default
- Nearby regressions:
  - `mix test lib/firmowid_web/invoicing/views/index_test.exs lib/firmowid_web/timetracker/controllers/csv_test.exs` PASS
  - `mix test lib/firmowid/ash/invoicing/invoicing_test.exs` PASS

### S08 — Link invoice to transaction via AI assistant (deterministic)

- Added deterministic S08 seed setup for previous-month aggregate matching case:
  - 5 incoming PLN transactions from one party (`Aurora Retail Sp. z o.o.`) in M-1
  - amounts sum exactly to 1,230.00 PLN (`+250 +300 +180 +200 +300`)
- Added root-cause assistant data-flow enhancement for deterministic suggestion path:
  - when sales invoice has a strict previous-month aggregate candidate (5..10 txns, same party, same currency, exact sum),
    assistant emits `link_sales_invoice_to_transaction` suggestion immediately
  - user acceptance path reuses existing `accept_linking/1` behavior (no sleeps/hacks)
- Added scripted coverage for assistant action path (suggestion -> accept -> linked + matched):
  - `lib/firmowid/ash/invoicing/matching/sales_invoice_assistant_test.exs`

Validation:
- `mix test lib/firmowid/ash/invoicing/matching/sales_invoice_assistant_test.exs` PASS
- Nearby invoicing regressions:
  - `mix test lib/firmowid/ash/invoicing/invoicing_test.exs lib/firmowid/ash/invoicing/sales_invoice_test.exs lib/firmowid_web/invoicing/sales_invoices/views/summary_test.exs` PASS

## Scripted test coverage added/updated in this pass

- `e2e/test/s03_sandbox_bank_account_test.exs` (updated for deterministic assertions)
- `lib/firmowid/ash/finances/requisition_test.exs`
- `lib/firmowid_web/invoicing/sales_invoices/views/edit_test.exs`
- `lib/firmowid_web/analysis/views/dashboard_test.exs`
- `lib/firmowid_web/management/views/projects_test.exs`
- `lib/firmowid_web/management/views/access_test.exs`
- `lib/firmowid_web/management/views/employees_test.exs`
- `lib/firmowid_web/invoicing/views/role_access_test.exs`
- `lib/firmowid_web/settings/views/security_test.exs`
- `lib/firmowid_web/timetracker/controllers/csv_test.exs`
- `lib/firmowid_web/hours_record/views/index_test.exs`
- `lib/firmowid_web/hours_record/controllers/record_test.exs`
- `lib/firmowid/ash/invoicing/services/month_download_entries_test.exs`
- `lib/firmowid_web/invoicing/components/download_modal_test.exs`
- `lib/firmowid/ash/invoicing/matching/sales_invoice_assistant_test.exs`

## Outstanding / deferred items

- S06: cost invoice upload pipeline (deferred for paired fix)
- S22: done in this pass

## Commands used for targeted validation

- `mix test lib/firmowid/ash/finances/requisition_test.exs`
- `mix test lib/firmowid/ash/finances/finances_test.exs`
- `mix test lib/firmowid/ash/timetracker/project_test.exs`
- `mix test lib/firmowid_web/analysis/views/dashboard_test.exs`
- `mix test lib/firmowid_web/management/views/projects_test.exs`
- `mix test lib/firmowid_web/management/views/access_test.exs`
- `mix test lib/firmowid_web/invoicing/views/role_access_test.exs`
- `mix test lib/firmowid/ash/timetracker/hours_record_test.exs`
- `mix test lib/firmowid_web/timetracker/views/index_test.exs`
- `mix test lib/firmowid_web/invoicing/views/index_test.exs`
- `mix test lib/firmowid_web/settings/views/security_test.exs`
- `mix test lib/firmowid_web/timetracker/controllers/csv_test.exs`
- `mix test lib/firmowid_web/invoicing/sales_invoices/views/edit_test.exs`
- `mix test lib/firmowid_web/invoicing/sales_invoices/views/summary_test.exs`
- `mix e2e e2e/test/s03_sandbox_bank_account_test.exs`
- `mix test lib/firmowid_web/hours_record/views/index_test.exs lib/firmowid_web/hours_record/controllers/record_test.exs`
- `mix test lib/firmowid/ash/timetracker/hours_record_test.exs lib/firmowid/ash/timetracker_payroll_policies_test.exs lib/firmowid_web/management/views/access_test.exs lib/firmowid_web/timetracker/views/index_test.exs`
- `mix test lib/firmowid_web/management/views/employees_test.exs`
- `mix test lib/firmowid_web/management/views/access_test.exs lib/firmowid_web/management/views/projects_test.exs`
- `mix test lib/firmowid_web/invoicing/views/role_access_test.exs`
- `mix test lib/firmowid_web/hours_record/views/index_test.exs`
- `mix test lib/firmowid/ash/invoicing/services/month_download_entries_test.exs lib/firmowid_web/invoicing/components/download_modal_test.exs`
- `mix test lib/firmowid_web/invoicing/views/index_test.exs lib/firmowid_web/timetracker/controllers/csv_test.exs`
- `mix test lib/firmowid/ash/invoicing/invoicing_test.exs`
