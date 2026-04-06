# KSeF Domain Consolidation — Progress

## Status: COMPLETE + REFINED (Pass 6)

All steps from the execution plan in `00-ksef-domain-consolidation.md` have been
executed and verified. Six refinement passes completed.
`mix check` passes (compile, format, credo, sobelow, dialyzer, tests).

## Completed Steps

1. **Directories created** — `workers/`, `services/` under `lib/firmowid/ash/ksef/`
2. **Oban worker rename migration** — `20260405224914_rename_ksef_oban_workers.exs`
   with `oban.oban_jobs` prefix and existence guard for test env
3. **Ash domain `Firmowid.Ash.Ksef`** — registered in `config.exs` `ash_domains`,
   contains all orchestration functions from old `Firmowid.Ksef`
4. **Ash resource `Credential`** — converted from Ecto schema, `migrate?: false`,
   custom `EncryptedBinaryType` wrapping `Cloak.Ecto.Binary`, added to
   `@unscoped_tables` in Repo
5. **Workers moved** — SessionWorker, SubmissionWorker, FetchWorker, FetchDispatcher
   all under `Firmowid.Ash.Ksef.Workers.*`
6. **Services moved** — ApiClient, Encryption, InvoiceParser, InvoiceRenderer,
   FA(3) XML template all under `Firmowid.Ash.Ksef.Services.*`
7. **VatRate + SubmissionInfo moved** — to `Firmowid.Ash.Ksef.*`
8. **KsefAwarePruner moved** — to `Firmowid.Ash.Ksef.KsefAwarePruner`
9. **Tests + test helpers moved** — colocated under `lib/firmowid/ash/ksef/`,
   `@compile {:no_warn_undefined, [:erlsom]}` for test-only dep
10. **API clients relocated** — NBP → `Firmowid.Ash.Currencies.NbpApiClient`,
    Resend → `Firmowid.Ash.Invoicing.Services.ResendClient`,
    Reducto → `Firmowid.Ash.Invoicing.Services.ReductoApiClient`
11. **Config updated** — Oban pruner, cron, ash_domains list
12. **~25 external callsites updated** — LiveViews, components, HEEx templates,
    Ash domain layer, seeds
13. **Old files + directories deleted** — `lib/firmowid/ksef/`, `lib/firmowid/oban/`,
    `lib/firmowid/nbp/`, `lib/firmowid/resend/`, `lib/firmowid/reducto_api_client.ex`,
    `test/ksef_helpers.ex`
14. **Verified** — zero stale references via grep, `mix check` all green

## Post-Consolidation Refinement

15. **Credential code_interface** — added `code_interface` block exposing
    `:create`, `:destroy`, and `:get_by_organization` actions. Domain module
    (`ksef.ex`) updated to use `Credential.create/1`, `Credential.destroy!/1`,
    and `Credential.get_by_organization/1` instead of raw `Ash.Changeset`/`Ash.Query`.
16. **@moduledoc added** — `ApiClient`, `Encryption`, `InvoiceRenderer`, `FetchWorker`
    all received proper `@moduledoc` descriptions (previously `@moduledoc false`).
17. **@doc + @spec added** — all public functions in `ApiClient` and `Encryption`
    now have `@doc` and `@spec` annotations. `submit_sales_invoice/1` in the domain
    module received a full `@spec` with all error variants.
18. **Docs updated** — `01-oban-worker-rename-migration.md` checklist fully completed.

## Refinement Pass 2

19. **@spec added to InvoiceRenderer** — All public functions (`render_fa3/1`,
    `format_decimal/1`, `format_quantity/1`, `format_vat_rate/1`, `gross_value_delta/2`,
    `payment_method_code/1`, `seller_name/1`, `buyer_name/1`,
    `validate_correction_buyer_tax_id!/1`, `validate_correction_seller_data!/1`,
    `buyer_data_changed?/1,2`, `invoice_items_changed?/2`) now have `@spec`.
20. **@doc added to InvoiceRenderer** — `format_decimal/1`, `payment_method_code/1`,
    `seller_name/1`, `validate_correction_seller_data!/1` received `@doc`.
21. **@doc + @spec added to KsefTestHelpers** — All 11 public functions
    (`unique_invoice_number/1`, `ensure_schemas_cached!/0`, `compile_ksef_schema!/0`,
    `validate_xml/2`, `build_domestic_invoice/1`, `build_multi_rate_invoice/1`,
    `build_reverse_charge_invoice/1`, `build_eu_vat_invoice/1`, `build_other_id_invoice/1`,
    `build_no_id_invoice/1`, `simulate_ksef_submission/2`, `build_correction_invoice/2`)
    now have `@doc` and `@spec`.
22. **Repo.preload → Ash.load!** — Replaced `Repo.preload(invoice, :blob)` with
    `Ash.load!(invoice, [:blob], ...)` in `ksef.ex` `invoice_url!/1` for cost invoices.
    One fewer Ecto exception.
23. **Justified Ecto Exceptions table updated** — Removed `Repo.preload` entry,
    added `Repo.transaction`/`Repo.transact` and split `CostInvoice` queries by file.

## Refinement Pass 3

24. **Credential `:all_organization_ids` action** — Added read action + code
    interface on `Credential` to list all org IDs without raw Ecto. Replaced
    `Repo.all(from(c in Credential, ...), skip_organization_id: true)` in
    `FetchDispatcher` with `Credential.all_organization_ids(...)`.
25. **FetchWorker duplicate detection → Ash** — Replaced `CostInvoice |>
    where(...) |> select(...) |> Repo.all()` with `Ash.Query.filter` +
    `Ash.Query.select` + `Ash.read!`. Removed `import Ecto.Query` from
    `fetch_worker.ex` (no longer needed).
26. **Repo.delete! → Ash.destroy!** — Replaced `Repo.delete!(item)` in
    `invoice_correction_test.exs` with `Ash.destroy!(item, ...)`. Removed
    unused `alias Firmowid.Repo` from test.
27. **@moduledoc added** — `InvoiceParserTest` received a `@moduledoc`
    (previously missing).

## Refinement Pass 4

28. **DRY: `buyer_id_xml/1` helper** — Extracted buyer identification XML
    rendering from the EEx template into `InvoiceRenderer.buyer_id_xml/1`.
    The Podmiot2 and Podmiot2K sections previously duplicated the same 5-way
    `buyer_id_type` case statement (~20 lines each). Now both call the shared
    helper. Pattern-matching clauses avoid Credo complexity/nesting warnings.
29. **VatRate unit tests** — Added `vat_rate_test.exs` (19 tests) covering
    `valid?/1`, `to_numeric/1`, `label/1`, `short_label/1`, `available_rates/2`,
    `summary_type/1`, `select_options/1`, and `select_options_short/1`.
30. **`backoff/1` documented** — Both `SubmissionWorker.backoff/1` and
    `FetchWorker.backoff/1` now have `@doc` explaining the attempt-number
    normalization for exponential backoff.
31. **`EncryptedBinaryType.describe/1`** — Added `@impl Ash.Type` override
    returning `"an encrypted binary (Cloak AES-256-GCM)"` for better error
    messages when type validation fails.
32. **`buyer_data_changed?/1` documented** — The single-arity fallback clause
    (returns `false` for non-correction contexts) now has `@doc`.
33. **Architecture diagram updated** — `00-ksef-domain-consolidation.md` now
    includes `encrypted_binary_type.ex`, `PROGRESS.md`, `ksef_test_helpers.ex`,
    and `vat_rate_test.exs` in the file tree.

## Refinement Pass 5

34. **SubmissionInfo helper functions** — Added `submitted?/1`, `submitting?/1`,
    `failed?/1`, `not_submitted?/1`, and `attempted?/1` to `SubmissionInfo`.
    Updated 10+ callsites in web layer (`sales_invoice_details.ex`,
    `entries_table.ex`, `summary.ex`) to use helpers instead of raw
    `.status == :atom` checks. Added `submission_info_test.exs` (10 tests).
35. **Encryption unit tests** — Added `encryption_test.exs` (12 tests) covering
    AES-256-CBC encrypt/decrypt roundtrip, PKCS#7 padding, empty input,
    block-aligned input, large XML content, ciphertext properties (differs from
    plaintext, block-aligned output), and key/IV uniqueness.
36. **KsefAwarePruner @moduledoc fixed** — Updated stale reference to
    `Ksef.submission_failed?/1` (no longer exists) → `Ksef.get_submission_info/1`.
37. **Architecture diagram updated** — `00-ksef-domain-consolidation.md` now
    includes `encryption_test.exs` and `submission_info_test.exs` in the file tree.

## Refinement Pass 6 (bug fixes from deep review)

38. **`payment_method_code(:loan)` added** — InvoiceParser maps FA(3) code `"5"` →
    `:loan` (CostInvoice atom), but InvoiceRenderer only had `:credit` → `"5"`
    (SalesInvoice atom). Added `:loan` → `"5"` clause to prevent silent fallthrough
    to `"6"` (transfer) if the renderer is ever extended to handle cost invoices.
39. **`unauthenticate/0` now cancels SubmissionWorker jobs** — Previously only
    cancelled SessionWorker and FetchWorker. In-flight submission jobs would
    continue after disconnect, calling `get_access_token!()` on a deleted credential.
40. **`validate_invoice_state/1` reordered** — Now checks draft status before lock
    status. Also checks `locked_at` (in-progress submission) in addition to
    `ksef_number` (completed submission) to prevent resubmitting in-flight invoices.
41. **`invoice_url!/1` dead code eliminated** — Refactored to three explicit clauses:
    CostInvoice without ksef_number (raises), CostInvoice with ksef_number (blob
    checksum), and generic map with ksef_number (backfill checksum). Previously the
    first clause matched CostInvoice with ksef_number, making the second clause's
    `is_nil(ksef_number)` guard unreachable.
42. **`get_credential/0` error handling tightened** — Replaced catch-all `_ -> nil`
    with explicit pattern matching for Ash's NotFound error wrapping (`%Ash.Error.Invalid{
    errors: [%Ash.Error.Query.NotFound{} | _]}`). Unexpected errors now propagate
    instead of being silently treated as "not connected."
43. **`unpad_pkcs7/1` empty binary clause** — Added explicit `<<>>` clause returning
    empty binary instead of `FunctionClauseError` on corrupted/truncated ciphertext.
44. **`KsefAwarePruner.validate/1` @spec** — Added missing `@spec` for consistency
    with other `@impl Plugin` callbacks in the same module.
45. **`VatRate.summary_type/1` fallback** — Added ArgumentError fallback clause for
    unknown rates, preventing cryptic `FunctionClauseError` if a new rate is added
    to `@all_valid_rates` without updating `summary_type/1`.
46. **Correction chain comment** — Added explanatory comment to `Enum.zip/1` truncation
    in `annotate_correction_chain/1` clarifying the intentional N vs N+1 length mismatch.

## Bug Fixes Applied During Migration

- **`CostInvoices.CostInvoice` → `Firmowid.Ash.Invoicing.CostInvoice`** in FetchWorker
  (stale alias from a previous directory move — would crash at runtime during KSeF fetch)

## Deviations from Plan

- **Credential Ash type**: Plan assumed `Firmowid.Encrypted.Binary` works directly
  as an Ash attribute type. It doesn't — Ash validates types and Cloak.Ecto.Binary
  is an Ecto type, not an Ash type. Created `Firmowid.Ash.Ksef.EncryptedBinaryType`
  as a thin Ash.Type wrapper that delegates to the Ecto type.
- **Oban migration prefix**: Plan used `oban_jobs`, but Oban is configured with
  `prefix: "oban"` so the table is at `oban.oban_jobs`. Added existence guard
  for test env where the table may not exist.
- **Seed file**: Plan suggested `Ash.Seed.seed!` for credential in bytecraft seeds.
  Used `Ash.read` + `Ash.Seed.seed!` pattern matching the idempotent seed style.

## Justified Ecto Exceptions (Remaining)

| Exception | File | Reason |
|-----------|------|--------|
| Oban job queries | `ksef.ex`, `session_worker.ex` | Oban has no Ash interface; queries against `oban_jobs` table |
| `Repo.get_org_id()` / `Repo.put_org_id()` | All workers | Tenant context for worker processes |
| Oban job cancel query | `ksef.ex` | `Firmowid.Oban.cancel_all_jobs` with Ecto query |
| `from(ci in CostInvoice, ...)` | `fetch_dispatcher.ex` | Aggregate query for `max(ksef_permanent_storage_date)` — cross-domain, not worth adding CostInvoice aggregate for single KSeF use |
| `Repo.transaction` / `Repo.transact` | `submission_worker.ex`, `ksef.ex` | Atomic grouping of lock+schedule (submission) and cancel+destroy (unauthenticate) |
