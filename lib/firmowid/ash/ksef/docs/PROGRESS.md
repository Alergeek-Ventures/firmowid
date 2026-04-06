# KSeF Domain Consolidation — Progress

## Status: COMPLETE + VERIFIED (Pass 15 — Web Layer Consistency)

All steps from the execution plan in `00-ksef-domain-consolidation.md` have been
executed and verified. Eleven refinement passes completed.
`mix check` passes (compile, format, credo, sobelow, dialyzer, tests).
346 tests, 0 failures. Zero bare `raise` calls remain.

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

## Refinement Pass 7 (convention alignment + bug fixes)

47. **`@bridge_opts` convention adopted** — Added `@bridge_opts [authorize?: false,
    actor: %{}]` to `ksef.ex`, `InvoiceRenderer`, `FetchWorker`, and
    `FetchDispatcher`. All inline `authorize?: false, actor: %{}` patterns now use
    the module attribute, matching the codebase-wide convention (see `Invoicing`,
    `SubmissionWorker`, `DatabaseCache`, etc.).
48. **`get_credential/0` dead code removed** — The `{:error, %NotFound{}}` pattern
    at line 141 never matched because Ash always wraps NotFound inside
    `%Ash.Error.Invalid{errors: [%NotFound{} | _]}`. Verified via Tidewave eval.
    Removed the unreachable clause, keeping only the correct wrapped pattern.
49. **`unauthenticate/0` nil credential guard** — Previously, calling
    `unauthenticate/0` when no credential existed would crash with a
    `FunctionClauseError` on `Credential.destroy!(nil)`. Now returns
    `{:error, :not_connected}` instead. The web layer already handles
    `{:error, _}` gracefully. Added `:not_connected` to the `@spec`.
50. **`InvoiceParser` error messages improved** — `parse_invoice_type/1` and
    `parse_payment_method/1` now raise `ArgumentError` with the offending value
    included in the message (e.g., `"Unknown FA(3) invoice type: \"XYZ\""`),
    instead of generic `RuntimeError` with no context.

## Refinement Pass 8 (dead code removal + error path testing)

51. **Dead `backoff/1` overrides removed** — Both `SubmissionWorker.backoff/1` and
    `FetchWorker.backoff/1` implemented the formula `3 - (max_attempts - attempt)`
    which, with `max_attempts: 3`, simplifies to the identity function (`attempt`).
    Oban's default `backoff/1` already uses `attempt` directly when
    `max_attempts <= 20` (the clamped max). The custom overrides were no-ops.
    Verified by evaluating `3 - (3 - n) = n` for all valid attempts.
52. **Error fallback tests added** — `VatRate.summary_type/1` ArgumentError
    fallback now tested (ensures unknown rates raise with descriptive message).
    `InvoiceParser.parse/1` now tested for unknown invoice types and unknown
    payment method codes (ensures errors propagate with context).
    Total test count: 102 → 105.

## Refinement Pass 9 (final polish + convention alignment)

53. **Stale comment fixed** — `ksef.ex` `get_submission_info/1` had a comment
    referencing "Slice 7" (an internal development context). Replaced with a
    clear technical explanation: "Uses map patterns instead of %SalesInvoice{} to
    accept any struct with the required fields (avoids compile-time coupling)."
54. **`@bridge_opts` convention extended to all KSeF files** — All inline
    `authorize?: false, actor: %{}` patterns across `ksef_test_helpers.ex` (7 calls),
    `invoice_correction_test.exs` (7 calls), and `invoice_renderer_test.exs` (6 calls)
    now use `@bridge_opts` module attribute. Every file in the KSeF domain now
    consistently uses the convention — no inline authorization bypass patterns remain.

## Refinement Pass 10 (error safety + pattern matching)

55. **`SessionWorker` unsafe `raise reason` fixed** — In the `Cachex.fetch!` callback,
    `raise reason` was called where `reason` could be an atom, struct, or any term.
    `raise/1` requires a string or exception struct — passing an atom that's not an
    exception module would crash with `ArgumentError`. Wrapped in a string:
    `raise "KSeF session renewal failed: #{inspect(reason)}"`.
56. **`ApiClient.get_auth_status/2` catch-all fixed** — Replaced opaque `rest -> rest`
    with explicit `{:error, _reason} = error -> error`. The catch-all could silently
    pass through unexpected return values; the explicit pattern ensures only error
    tuples are forwarded.
57. **`InvoiceRenderer.seller_name/1` exception type** — Changed from `raise("...")`
    (raises `RuntimeError`) to `raise(ArgumentError, "...")`. A missing seller name
    is a data validation error, not a runtime error.
58. **`ksef.ex` `backfill_ksef_checksum!/1` exception enriched** — Changed from
    `raise "..."` to `raise RuntimeError, "..."` with the `ksef_number` included in
    the message for easier debugging when checksum backfill fails.

## Refinement Pass 11 (exception types + @spec completeness)

59. **Bare `raise "..."` → explicit exception types** — All remaining bare `raise`
    calls across the KSeF domain now use explicit exception types:
    - `ApiClient.parse_datetime!/1`: `raise` → `raise ArgumentError` (invalid input)
    - `ApiClient` Cachex callback: `raise` → `raise RuntimeError` (infrastructure failure)
    - `Encryption.unpad_pkcs7/1`: `raise` → `raise ArgumentError` (corrupted input, 2 clauses)
    - `FetchWorker`: `raise` → `raise RuntimeError` in 4 places (expired parts,
      unzip failures, checksum mismatches, download failures); checksum mismatch now
      includes part ordinal number for debugging
    - `SessionWorker` Cachex callback: `raise` → `raise RuntimeError` with improved message
    - `KsefTestHelpers.compile_ksef_schema!/0`: `raise` → `raise RuntimeError`
60. **`@spec perform/1` added to all Oban workers** — `SessionWorker`, `SubmissionWorker`,
    `FetchWorker`, and `FetchDispatcher` now have `@spec perform(Oban.Job.t()) ::
    Oban.Worker.result()` on their `@impl Oban.Worker` callbacks.
61. **`KsefAwarePruner.handle_info/2` catch-all documented** — Added `@doc false` to
    the unexpected-message catch-all clause to suppress missing-doc warnings.

## Refinement Pass 12 (final bare raise elimination + validation exception types)

62. **Last 3 bare `raise "..."` calls fixed** — Pass 11 missed 3 bare raise calls:
    - `SessionWorker` Cachex callback (line 132): `raise "KSeF session renewal
      failed..."` → `raise RuntimeError, "..."` (infrastructure failure, consistent
      with the other Cachex callback at line 128)
    - `InvoiceRenderer.validate_correction_buyer_tax_id!/1`: `raise "Buyer tax ID
      cannot change..."` → `raise ArgumentError, "..."` (data validation error,
      not a runtime error)
    - `InvoiceRenderer.validate_correction_seller_data!/1`: `raise "Seller data
      cannot change..."` → `raise ArgumentError, "..."` (data validation error)
    - `fa3_invoice_template.xml.eex` VAT summary fallback: `raise "Unexpected VAT
      rate..."` → `raise RuntimeError, "..."` (internal invariant violation)
    Tests updated: `InvoiceCorrectionTest` assertions changed from `RuntimeError` to
    `ArgumentError` for the two validation guard tests.
    **Zero bare `raise` calls remain** across the entire KSeF domain (verified with
    `rg '^\s+raise\s+"' lib/firmowid/ash/ksef/`).

## Refinement Pass 13 (DRY + bug fix)

63. **`tenant_opts/0` helper extracted** — Replaced 10 instances of the repeated
    `[tenant: Repo.get_org_id()] ++ @bridge_opts` pattern across `ksef.ex`,
    `submission_worker.ex` (7 occurrences), and `fetch_worker.ex` (2 occurrences)
    with a `defp tenant_opts/0` helper in each module.
64. **`gross_value` aggregate not loaded bug** — `@sales_invoice_loads` in
    `lib/firmowid_web/invoicing/views/index.ex` did not include `:gross_value`.
    The `entries_table.ex` component uses `invoice.gross_value` at line 226/293
    to render the amount column and for Decimal comparisons (color coding). This
    caused a `FunctionClauseError` in `Decimal.decimal/1` when viewing the
    invoicing page — `Decimal.gte?(#Ash.NotLoaded<:aggregate>, 0)`. Added
    `:gross_value` to `@sales_invoice_loads`. Manually verified fix in browser.
65. **Invoice-level aggregates missing in detail views** — `show.ex`, `summary.ex`,
    and `edit.ex` loaded item-level calcs (`sales_invoice_items: [:net_value,
    :vat_value, :gross_value]`) but not invoice-level aggregates (`:net_value`,
    `:vat_value`, `:gross_value`). The `template.ex` component uses these at lines
    498/508/517/535. Added top-level aggregate loads to all three views and the
    `search_invoices` function in `invoicing.ex`. Follows the pattern from `shared.ex`
    (PDF controller) which correctly loads both levels.
66. **`BadBooleanError` in summary.ex** — Line 109 used `@invoice.invoice_number and`
    which fails in newer Phoenix LiveView because `invoice_number` is a string, not
    a boolean. Changed to `not is_nil(@invoice.invoice_number) and`. This was
    introduced during refinement pass 5 when `@submission_info.status in [...]` was
    replaced with `SubmissionInfo.not_submitted?/1` helper calls.
67. **Manual testing passed** — KSeF settings page (`/ustawienia/organizacja`)
    shows "Połączono z KSeF" with token auth type. Invoicing page (`/fakturowanie`)
    renders all invoice rows with correct amounts, KSeF statuses (KOMPLET, BŁĄD
    WYSYŁANIA, POMIŃ), and color coding. Invoice summary (`/podsumowanie`) renders
    complete invoice preview with correct aggregates.

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

## Final Review (Pass 14)

68. **Comprehensive code review** — All 25 files in the KSeF domain reviewed
    line-by-line. No code issues found. Verified:
    - Zero stale module references in `lib/`, `config/`, `priv/` (only docs
      contain old names for historical context)
    - All public functions have `@doc` and `@spec`
    - All modules have accurate `@moduledoc`
    - Zero bare `raise` calls — all use explicit exception types
    - `@bridge_opts` + `tenant_opts/0` conventions consistently applied
    - Error handling tight — no catch-all patterns swallowing errors
    - 105 KSeF domain tests all green (unit, integration, XSD, correction chains)
    - `mix check` fully green (format, compile, credo, sobelow, dialyzer, tests)
    - Web layer consumers verified (LiveViews, components, templates) — all use
      correct module names and `SubmissionInfo` helpers appropriately
    - Cross-domain integration verified (Invoicing, Accounts, Currencies)

## Refinement Pass 15 (web layer consistency)

69. **`summary.ex` raw `.status` atom checks replaced** — The `case @submission_info.status`
    block in the render template (lines 71–91) was the only place in the web layer that
    bypassed `SubmissionInfo` helper functions. Replaced with `cond` using
    `SubmissionInfo.submitting?/1`, `SubmissionInfo.submitted?/1`, and
    `SubmissionInfo.failed?/1`. All web consumers now consistently use helpers.
70. **`summary.ex` struct update fixed** — `%{socket.assigns.submission_info | status: :submitting}`
    (generic map update syntax) replaced with `%SubmissionInfo{status: :submitting}`
    (proper struct construction). Consistent with `sales_invoice_details.ex` pattern.
71. **Full web layer audit** — All 12 web files consuming the KSeF domain reviewed:
    - Zero remaining raw `.status` comparisons against `SubmissionInfo`
    - All aliases used and correct
    - SubmissionInfo helpers consistently applied across entries_table, sales_invoice_details,
      summary, invoice_timeline
    - Manual testing verified: summary page renders correctly for `:not_submitted`,
      `:failed`, and `:submitted` states
    - `mix check` fully green after changes

## Justified Ecto Exceptions (Remaining)

| Exception | File | Reason |
|-----------|------|--------|
| Oban job queries | `ksef.ex`, `session_worker.ex` | Oban has no Ash interface; queries against `oban_jobs` table |
| `Repo.get_org_id()` / `Repo.put_org_id()` | All workers | Tenant context for worker processes |
| Oban job cancel query | `ksef.ex` | `Firmowid.Oban.cancel_all_jobs` with Ecto query |
| `from(ci in CostInvoice, ...)` | `fetch_dispatcher.ex` | Aggregate query for `max(ksef_permanent_storage_date)` — cross-domain, not worth adding CostInvoice aggregate for single KSeF use |
| `Repo.transaction` / `Repo.transact` | `submission_worker.ex`, `ksef.ex` | Atomic grouping of lock+schedule (submission) and cancel+destroy (unauthenticate) |
