# KSeF Domain Consolidation — Progress

## Status: COMPLETE

All steps from the execution plan in `00-ksef-domain-consolidation.md` have been
executed and verified. `mix check` passes (compile, format, credo, sobelow,
dialyzer, tests — 302 tests, 0 failures).

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
