# KSeF Domain Consolidation

Move the entire KSeF integration from `lib/firmowid/ksef/` into a proper Ash
domain at `lib/firmowid/ash/ksef/`. Convert `Credential` to an Ash resource.
Move the KSeF-aware Oban pruner. Relocate stray API clients (NBP, Resend,
Reducto) into their consuming domains.

## Context

KSeF (Krajowy System e-Faktur) is Poland's national e-invoicing system. Our
integration handles:
- Authentication (token-based, per-organization)
- Cost invoice fetching (encrypted export → XML parsing → CostInvoice creation)
- Sales invoice submission (XML rendering → encryption → send → poll for confirmation)
- Session management (access token caching via Cachex, refresh token rotation)
- Submission status tracking (Oban job queries → SubmissionInfo struct)

## Architecture after consolidation

```
lib/firmowid/ash/ksef/
├── docs/
│   ├── 00-ksef-domain-consolidation.md    # this file
│   └── 01-oban-worker-rename-migration.md # worker rename migration guide
├── ksef.ex                    # Ash domain + orchestration functions
├── credential.ex              # Ash resource (ksef_credentials table)
├── ksef_aware_pruner.ex       # Custom Oban pruner (preserves submission jobs)
├── submission_info.ex         # Plain struct — submission status
├── vat_rate.ex                # KSeF FA(3) VAT rate codes (shared with Invoicing)
├── workers/
│   ├── session_worker.ex      # Oban — auth + session renewal
│   ├── submission_worker.ex   # Oban — send invoice + verify
│   ├── fetch_worker.ex        # Oban — export + download + parse
│   └── fetch_dispatcher.ex    # Oban — cron: schedule fetch for all orgs
├── services/
│   ├── api_client.ex          # HTTP client for KSeF API
│   ├── encryption.ex          # AES-256-CBC + RSA for KSeF
│   ├── invoice_parser.ex      # FA(3) XML → CostInvoice attrs
│   ├── invoice_renderer.ex    # SalesInvoice → FA(3) XML
│   ├── invoice_renderer_test.exs
│   ├── invoice_parser_test.exs
│   ├── invoice_correction_test.exs
│   └── fa3_invoice_template.xml.eex
└── ksef_test_helpers.ex       # Test fixtures (seeded invoices, XSD validation)
```

## Module rename mapping

| Old module | New module |
|-----------|-----------|
| `Firmowid.Ksef` | `Firmowid.Ash.Ksef` |
| `Firmowid.Ksef.Credential` | `Firmowid.Ash.Ksef.Credential` |
| `Firmowid.Ksef.SessionWorker` | `Firmowid.Ash.Ksef.Workers.SessionWorker` |
| `Firmowid.Ksef.SubmissionWorker` | `Firmowid.Ash.Ksef.Workers.SubmissionWorker` |
| `Firmowid.Ksef.FetchWorker` | `Firmowid.Ash.Ksef.Workers.FetchWorker` |
| `Firmowid.Ksef.FetchDispatcher` | `Firmowid.Ash.Ksef.Workers.FetchDispatcher` |
| `Firmowid.Ksef.ApiClient` | `Firmowid.Ash.Ksef.Services.ApiClient` |
| `Firmowid.Ksef.Encryption` | `Firmowid.Ash.Ksef.Services.Encryption` |
| `Firmowid.Ksef.InvoiceParser` | `Firmowid.Ash.Ksef.Services.InvoiceParser` |
| `Firmowid.Ksef.InvoiceRenderer` | `Firmowid.Ash.Ksef.Services.InvoiceRenderer` |
| `Firmowid.Ksef.VatRate` | `Firmowid.Ash.Ksef.VatRate` |
| `Firmowid.Ksef.SubmissionInfo` | `Firmowid.Ash.Ksef.SubmissionInfo` |
| `Firmowid.Oban.KsefAwarePruner` | `Firmowid.Ash.Ksef.KsefAwarePruner` |
| `Firmowid.KsefTestHelpers` | `Firmowid.Ash.Ksef.KsefTestHelpers` |

## API client relocations (non-KSeF)

| Old module | New module | Consuming domain |
|-----------|-----------|-----------------|
| `Firmowid.Nbp.ApiClient` | `Firmowid.Ash.Currencies.NbpApiClient` | Currencies |
| `Firmowid.Resend.Client` | `Firmowid.Ash.Invoicing.Services.ResendClient` | Invoicing |
| `Firmowid.ReductoApiClient` | `Firmowid.Ash.Invoicing.Services.ReductoApiClient` | Invoicing |

## Credential as Ash resource

The only DB-backed schema in the KSeF integration. Currently a plain Ecto
schema, converted to Ash resource:

- Table: `ksef_credentials`
- **No multitenancy** — queried by explicit `organization_id` filter, not
  tenant. Global table (one credential per org, looked up during auth).
- Added to `@unscoped_tables` in Repo.
- `Firmowid.Encrypted.Binary` works as an Ash attribute type — Ash uses Ecto
  under the hood via AshPostgres.
- Actions: `:read`, `:create`, `:destroy`, `:by_organization` (read with filter)
- `migrate?: false` — table already exists.

## Worker module renaming — critical notes

**Oban stores worker names as strings in the `oban_jobs` table.** Renaming
worker modules means:

1. In-flight jobs with old worker names become unresolvable
2. String-based Oban job queries must be updated
3. Config cron entries must be updated
4. Seed data SQL strings should be updated for consistency

See `01-oban-worker-rename-migration.md` for the full migration guide.

## Justified Ecto exceptions

| Exception | File | Reason |
|-----------|------|--------|
| Oban job queries | `ksef.ex`, `session_worker.ex` | `oban_jobs: true` — Oban has no Ash interface |
| `Repo.get_org_id()` / `Repo.put_org_id()` | All workers | Tenant context for worker processes |
| Oban job cancel query | `ksef.ex` | `Firmowid.Oban.cancel_all_jobs` with Ecto query |

## Cross-domain dependencies

- **KSeF → Accounts**: `Accounts.get_organization(org_id)` for NIP lookup during auth
- **KSeF → Invoicing**: `SalesInvoice.by_id`, `SalesInvoice.update_ksef_fields!`,
  `Invoicing.create_cost_invoice`, `Blobs.create_blob`
- **Invoicing → KSeF**: `Ksef.VatRate` for validation, `Ksef.get_submission_info`
  for timeline, `Ksef.invoice_url!` for links, `Ksef.subscribe_ksef_status` for
  PubSub

## Config keys

- `:firmowid, :ksef` — unchanged (base_url, qr_code_base_url)
- Oban queues: `ksef_submissions`, `ksef_sessions`, `ksef_fetch` — unchanged
- Oban cron: `FetchDispatcher` string updated to new module name

## Directories eliminated

- `lib/firmowid/ksef/` — gone
- `lib/firmowid/oban/` — gone (only had KsefAwarePruner)
- `lib/firmowid/nbp/` — gone
- `lib/firmowid/resend/` — gone
- `lib/firmowid/reducto_api_client.ex` — gone

---

# Execution Plan

## Step 1: Create directories

```
mkdir -p lib/firmowid/ash/ksef/workers
mkdir -p lib/firmowid/ash/ksef/services
```

## Step 2: Create Oban worker rename migration

Create `priv/repo/migrations/TIMESTAMP_rename_ksef_oban_workers.exs`:

```elixir
defmodule Firmowid.Repo.Migrations.RenameKsefObanWorkers do
  use Ecto.Migration

  @worker_renames %{
    "Firmowid.Ksef.SessionWorker" => "Firmowid.Ash.Ksef.Workers.SessionWorker",
    "Firmowid.Ksef.SubmissionWorker" => "Firmowid.Ash.Ksef.Workers.SubmissionWorker",
    "Firmowid.Ksef.FetchWorker" => "Firmowid.Ash.Ksef.Workers.FetchWorker",
    "Firmowid.Ksef.FetchDispatcher" => "Firmowid.Ash.Ksef.Workers.FetchDispatcher"
  }

  def up do
    for {old_name, new_name} <- @worker_renames do
      execute "UPDATE oban_jobs SET worker = '#{new_name}' WHERE worker = '#{old_name}'"
    end
  end

  def down do
    for {old_name, new_name} <- @worker_renames do
      execute "UPDATE oban_jobs SET worker = '#{old_name}' WHERE worker = '#{new_name}'"
    end
  end
end
```

## Step 3: Create Ash domain shell — `lib/firmowid/ash/ksef/ksef.ex`

New file: `Firmowid.Ash.Ksef` domain module.

- `use Ash.Domain`
- `resources do` block with `resource Firmowid.Ash.Ksef.Credential`
- Move ALL functions from old `lib/firmowid/ksef.ex` into this module
- Update all internal aliases:
  - `alias Firmowid.Ksef.ApiClient` → `alias Firmowid.Ash.Ksef.Services.ApiClient`
  - `alias Firmowid.Ksef.Credential` → `alias Firmowid.Ash.Ksef.Credential`
  - `alias Firmowid.Ksef.FetchWorker` → `alias Firmowid.Ash.Ksef.Workers.FetchWorker`
  - `alias Firmowid.Ksef.SessionWorker` → `alias Firmowid.Ash.Ksef.Workers.SessionWorker`
  - `alias Firmowid.Ksef.SubmissionInfo` → `alias Firmowid.Ash.Ksef.SubmissionInfo`
  - `alias Firmowid.Ksef.SubmissionWorker` → `alias Firmowid.Ash.Ksef.Workers.SubmissionWorker`
- Update Oban job query strings (3 places):
  - `"Firmowid.Ksef.SessionWorker"` → `"Firmowid.Ash.Ksef.Workers.SessionWorker"` (line 124)
  - `"Firmowid.Ksef.FetchWorker"` → `"Firmowid.Ash.Ksef.Workers.FetchWorker"` (line 124)
  - `"Firmowid.Ksef.SubmissionWorker"` → `"Firmowid.Ash.Ksef.Workers.SubmissionWorker"` (line 389)
- Replace `Repo.get_by(Credential, ...)` with Ash domain code interface call
  (`by_organization` action) in `get_credential/0` and `validate_no_existing_credential/0`
- Replace `Repo.insert` / `Repo.delete` of Credential with Ash `create!` / `destroy!`
- Delete old `lib/firmowid/ksef.ex`

## Step 4: Create Ash resource — `lib/firmowid/ash/ksef/credential.ex`

New file: `Firmowid.Ash.Ksef.Credential` Ash resource.

```elixir
defmodule Firmowid.Ash.Ksef.Credential do
  use Ash.Resource,
    domain: Firmowid.Ash.Ksef,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "ksef_credentials"
    repo Firmowid.Repo
    migrate? false
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:organization_id, :auth_type, :credentials]
    end

    read :by_organization do
      argument :organization_id, :uuid, allow_nil?: false
      get? true
      filter expr(organization_id == ^arg(:organization_id))
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :auth_type, :atom, constraints: [one_of: [:token, :certificate]], allow_nil?: false, public?: true
    attribute :credentials, Firmowid.Encrypted.Binary, allow_nil?: false, public?: true

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :organization, Firmowid.Ash.Core.Organization do
      allow_nil? false
      attribute_writable? true
    end
  end

  identities do
    identity :unique_organization, [:organization_id]
  end
end
```

Add `"ksef_credentials"` to `@unscoped_tables` in `lib/firmowid/repo.ex`.

Delete old `lib/firmowid/ksef/credential.ex`.

## Step 5: Move workers (4 files)

For each worker: move file, rename `defmodule`, update internal aliases, update
Oban job query strings.

### 5a: SessionWorker

- Move `lib/firmowid/ksef/session_worker.ex` → `lib/firmowid/ash/ksef/workers/session_worker.ex`
- `defmodule Firmowid.Ksef.SessionWorker` → `defmodule Firmowid.Ash.Ksef.Workers.SessionWorker`
- Update aliases:
  - `alias Firmowid.Ksef` → `alias Firmowid.Ash.Ksef`
  - `alias Firmowid.Ksef.ApiClient` → `alias Firmowid.Ash.Ksef.Services.ApiClient`
  - `alias Firmowid.Ksef.Credential` → `alias Firmowid.Ash.Ksef.Credential`
- Update Oban job query string at line 84:
  - `j.worker == "Firmowid.Ksef.SessionWorker"` → `j.worker == "Firmowid.Ash.Ksef.Workers.SessionWorker"`

### 5b: SubmissionWorker

- Move `lib/firmowid/ksef/submission_worker.ex` → `lib/firmowid/ash/ksef/workers/submission_worker.ex`
- `defmodule Firmowid.Ksef.SubmissionWorker` → `defmodule Firmowid.Ash.Ksef.Workers.SubmissionWorker`
- Update aliases:
  - `alias Firmowid.Ksef` → `alias Firmowid.Ash.Ksef`
  - `alias Firmowid.Ksef.ApiClient` → `alias Firmowid.Ash.Ksef.Services.ApiClient`
  - `alias Firmowid.Ksef.InvoiceRenderer` → `alias Firmowid.Ash.Ksef.Services.InvoiceRenderer`
  - `alias Firmowid.Ksef.SessionWorker` → `alias Firmowid.Ash.Ksef.Workers.SessionWorker`

### 5c: FetchWorker

- Move `lib/firmowid/ksef/fetch_worker.ex` → `lib/firmowid/ash/ksef/workers/fetch_worker.ex`
- `defmodule Firmowid.Ksef.FetchWorker` → `defmodule Firmowid.Ash.Ksef.Workers.FetchWorker`
- Update aliases:
  - `import Firmowid.Ksef.ApiClient` → `import Firmowid.Ash.Ksef.Services.ApiClient`
  - `alias Firmowid.Ksef.ApiClient` → `alias Firmowid.Ash.Ksef.Services.ApiClient`
  - `alias Firmowid.Ksef.Encryption` → `alias Firmowid.Ash.Ksef.Services.Encryption`
  - `alias Firmowid.Ksef.InvoiceParser` → `alias Firmowid.Ash.Ksef.Services.InvoiceParser`
  - `alias Firmowid.Ksef.SessionWorker` → `alias Firmowid.Ash.Ksef.Workers.SessionWorker`
- **FIX BUG** at line 198: `CostInvoices.CostInvoice` → `Firmowid.Ash.Invoicing.CostInvoice`
  (stale alias from previous directory move — will crash at runtime during KSeF fetch)

### 5d: FetchDispatcher

- Move `lib/firmowid/ksef/fetch_dispatcher.ex` → `lib/firmowid/ash/ksef/workers/fetch_dispatcher.ex`
- `defmodule Firmowid.Ksef.FetchDispatcher` → `defmodule Firmowid.Ash.Ksef.Workers.FetchDispatcher`
- Update aliases:
  - `alias Firmowid.Ksef` → `alias Firmowid.Ash.Ksef`
  - `alias Firmowid.Ksef.Credential` → `alias Firmowid.Ash.Ksef.Credential`

## Step 6: Move services (4 files + 1 template)

### 6a: ApiClient

- Move `lib/firmowid/ksef/api_client.ex` → `lib/firmowid/ash/ksef/services/api_client.ex`
- `defmodule Firmowid.Ksef.ApiClient` → `defmodule Firmowid.Ash.Ksef.Services.ApiClient`
- Update alias: `alias Firmowid.Ksef.Encryption` → `alias Firmowid.Ash.Ksef.Services.Encryption`

### 6b: Encryption

- Move `lib/firmowid/ksef/encryption.ex` → `lib/firmowid/ash/ksef/services/encryption.ex`
- `defmodule Firmowid.Ksef.Encryption` → `defmodule Firmowid.Ash.Ksef.Services.Encryption`
- Update alias: `alias Firmowid.Ksef.ApiClient` → `alias Firmowid.Ash.Ksef.Services.ApiClient`

### 6c: InvoiceParser

- Move `lib/firmowid/ksef/invoice_parser.ex` → `lib/firmowid/ash/ksef/services/invoice_parser.ex`
- `defmodule Firmowid.Ksef.InvoiceParser` → `defmodule Firmowid.Ash.Ksef.Services.InvoiceParser`
- Update `@moduledoc` — iex example references old module name

### 6d: InvoiceRenderer

- Move `lib/firmowid/ksef/invoice_renderer.ex` → `lib/firmowid/ash/ksef/services/invoice_renderer.ex`
- `defmodule Firmowid.Ksef.InvoiceRenderer` → `defmodule Firmowid.Ash.Ksef.Services.InvoiceRenderer`
- Update alias: `alias Firmowid.Ksef.VatRate` → `alias Firmowid.Ash.Ksef.VatRate`
- **Update EEx path** at line 64:
  `"lib/firmowid/ksef/fa3_invoice_template.xml.eex"` → `"lib/firmowid/ash/ksef/services/fa3_invoice_template.xml.eex"`

### 6e: XML template

- Move `lib/firmowid/ksef/fa3_invoice_template.xml.eex` → `lib/firmowid/ash/ksef/services/fa3_invoice_template.xml.eex`

## Step 7: Move VatRate + SubmissionInfo

### 7a: VatRate

- Move `lib/firmowid/ksef/vat_rate.ex` → `lib/firmowid/ash/ksef/vat_rate.ex`
- `defmodule Firmowid.Ksef.VatRate` → `defmodule Firmowid.Ash.Ksef.VatRate`

### 7b: SubmissionInfo

- Move `lib/firmowid/ksef/submission_info.ex` → `lib/firmowid/ash/ksef/submission_info.ex`
- `defmodule Firmowid.Ksef.SubmissionInfo` → `defmodule Firmowid.Ash.Ksef.SubmissionInfo`

## Step 8: Move KsefAwarePruner

- Move `lib/firmowid/oban/ksef_aware_pruner.ex` → `lib/firmowid/ash/ksef/ksef_aware_pruner.ex`
- `defmodule Firmowid.Oban.KsefAwarePruner` → `defmodule Firmowid.Ash.Ksef.KsefAwarePruner`
- Update example in `@moduledoc`:
  `{Firmowid.Oban.KsefAwarePruner, max_age: ...}` → `{Firmowid.Ash.Ksef.KsefAwarePruner, max_age: ...}`

## Step 9: Move tests + test helpers

### 9a: Test files (3 files)

- Move `lib/firmowid/ksef/invoice_parser_test.exs` → `lib/firmowid/ash/ksef/services/invoice_parser_test.exs`
  - `defmodule Firmowid.Ksef.InvoiceParserTest` → `defmodule Firmowid.Ash.Ksef.Services.InvoiceParserTest`
  - `alias Firmowid.Ksef.InvoiceParser` → `alias Firmowid.Ash.Ksef.Services.InvoiceParser`

- Move `lib/firmowid/ksef/invoice_renderer_test.exs` → `lib/firmowid/ash/ksef/services/invoice_renderer_test.exs`
  - `defmodule Firmowid.Ksef.InvoiceRendererTest` → `defmodule Firmowid.Ash.Ksef.Services.InvoiceRendererTest`
  - `import Firmowid.KsefTestHelpers` → `import Firmowid.Ash.Ksef.KsefTestHelpers`
  - `alias Firmowid.Ksef.InvoiceRenderer` → `alias Firmowid.Ash.Ksef.Services.InvoiceRenderer`

- Move `lib/firmowid/ksef/invoice_correction_test.exs` → `lib/firmowid/ash/ksef/services/invoice_correction_test.exs`
  - `defmodule Firmowid.Ksef.InvoiceCorrectionTest` → `defmodule Firmowid.Ash.Ksef.Services.InvoiceCorrectionTest`
  - `import Firmowid.KsefTestHelpers` → `import Firmowid.Ash.Ksef.KsefTestHelpers`
  - `alias Firmowid.Ksef.InvoiceRenderer` → `alias Firmowid.Ash.Ksef.Services.InvoiceRenderer`

### 9b: Test helpers

- Move `test/ksef_helpers.ex` → `lib/firmowid/ash/ksef/ksef_test_helpers.ex`
- `defmodule Firmowid.KsefTestHelpers` → `defmodule Firmowid.Ash.Ksef.KsefTestHelpers`
- Update aliases:
  - `alias Firmowid.Ash.Invoicing.SalesInvoice, as: AshSalesInvoice` → `alias Firmowid.Ash.Invoicing.SalesInvoice`
  - `alias Firmowid.Ash.Invoicing.SalesInvoiceItem, as: AshSalesInvoiceItem` → `alias Firmowid.Ash.Invoicing.SalesInvoiceItem`
  - Fix all `AshSalesInvoice` → `SalesInvoice` and `AshSalesInvoiceItem` → `SalesInvoiceItem` in body

## Step 10: Move API clients to consuming domains

### 10a: NBP → Currencies

- Move `lib/firmowid/nbp/api_client.ex` → `lib/firmowid/ash/currencies/nbp_api_client.ex`
- `defmodule Firmowid.Nbp.ApiClient` → `defmodule Firmowid.Ash.Currencies.NbpApiClient`
- Update 2 callsites:
  - `lib/firmowid/ash/invoicing/invoicing.ex:30`: `alias Firmowid.Nbp.ApiClient` → `alias Firmowid.Ash.Currencies.NbpApiClient` (and update usage)
  - `lib/firmowid_web/invoicing/sales_invoices/components/invoice_items.ex:11`: `alias Firmowid.Nbp.ApiClient, as: NbpApiClient` → `alias Firmowid.Ash.Currencies.NbpApiClient`
- Delete `lib/firmowid/nbp/` directory

### 10b: Resend → Invoicing

- Move `lib/firmowid/resend/client.ex` → `lib/firmowid/ash/invoicing/services/resend_client.ex`
- `defmodule Firmowid.Resend.Client` → `defmodule Firmowid.Ash.Invoicing.Services.ResendClient`
- Update 1 callsite:
  - `lib/firmowid/ash/invoicing/workers/inbound_email_worker.ex:17`: `alias Firmowid.Resend.Client` → `alias Firmowid.Ash.Invoicing.Services.ResendClient` (and update usage from `Client.` to `ResendClient.`)
- Delete `lib/firmowid/resend/` directory

### 10c: Reducto → Invoicing

- Move `lib/firmowid/reducto_api_client.ex` → `lib/firmowid/ash/invoicing/services/reducto_api_client.ex`
- `defmodule Firmowid.ReductoApiClient` → `defmodule Firmowid.Ash.Invoicing.Services.ReductoApiClient`
- Update 1 callsite:
  - `lib/firmowid/ash/invoicing/workers/cost_invoice_worker.ex:16`: `alias Firmowid.ReductoApiClient` → `alias Firmowid.Ash.Invoicing.Services.ReductoApiClient` (and update usage)

## Step 11: Update config files

### 11a: `config/config.exs`

- Line 108: `{Firmowid.Oban.KsefAwarePruner, max_age: ...}` → `{Firmowid.Ash.Ksef.KsefAwarePruner, max_age: ...}`
- Line 113: `Firmowid.Ksef.FetchDispatcher` → `Firmowid.Ash.Ksef.Workers.FetchDispatcher`
- Add `Firmowid.Ash.Ksef` to `ash_domains` list (after `Firmowid.Ash.Invoicing`, line ~133)

### 11b: No changes needed

- `config/prod.exs` — only has `:firmowid, :ksef` config key (unchanged)
- `config/test.exs` — only has `:firmowid, :ksef` config key (unchanged)
- `config/dev.exs` — only has `:firmowid, :ksef` config key (unchanged)

## Step 12: Update external callsites (~20 files)

Every file below needs alias updates from `Firmowid.Ksef` → `Firmowid.Ash.Ksef`.

### Web layer — LiveViews (6 files)

| File | Current reference | New reference |
|------|------------------|---------------|
| `lib/firmowid_web/invoicing/views/index.ex:17` | `alias Firmowid.Ksef` | `alias Firmowid.Ash.Ksef` |
| `lib/firmowid_web/invoicing/sales_invoices/views/edit.ex:21` | `alias Firmowid.Ksef` | `alias Firmowid.Ash.Ksef` |
| `lib/firmowid_web/invoicing/sales_invoices/views/creator.ex:19` | `alias Firmowid.Ksef` | `alias Firmowid.Ash.Ksef` |
| `lib/firmowid_web/invoicing/sales_invoices/views/summary.ex:14` | `alias Firmowid.Ksef` | `alias Firmowid.Ash.Ksef` |
| `lib/firmowid_web/invoicing/sales_invoices/views/show.ex:9` | `alias Firmowid.Ksef` | `alias Firmowid.Ash.Ksef` |
| `lib/firmowid_web/settings/views/index.ex:14` | `alias Firmowid.Ksef` | `alias Firmowid.Ash.Ksef` |

### Web layer — Components (6 files)

| File | Current reference | New reference |
|------|------------------|---------------|
| `lib/firmowid_web/invoicing/components/entries_table.ex:11` | `alias Firmowid.Ksef` | `alias Firmowid.Ash.Ksef` |
| `lib/firmowid_web/invoicing/components/invoice_timeline.ex:11` | `alias Firmowid.Ksef.SubmissionInfo` | `alias Firmowid.Ash.Ksef.SubmissionInfo` |
| `lib/firmowid_web/invoicing/components/cost_invoice_details.ex:6` | `alias Firmowid.Ksef` | `alias Firmowid.Ash.Ksef` |
| `lib/firmowid_web/invoicing/components/sales_invoice_details.ex:7-8` | `alias Firmowid.Ksef` + `alias Firmowid.Ksef.SubmissionInfo` | `alias Firmowid.Ash.Ksef` + `alias Firmowid.Ash.Ksef.SubmissionInfo` |
| `lib/firmowid_web/invoicing/sales_invoices/components/invoice_items.ex:10` | `alias Firmowid.Ksef.VatRate` | `alias Firmowid.Ash.Ksef.VatRate` |
| `lib/firmowid_web/invoicing/sales_invoices/components/template.ex:289,392,764` | `Firmowid.Ksef.VatRate.label(...)` + `Firmowid.Ksef.invoice_url!()` | `Firmowid.Ash.Ksef.VatRate.label(...)` + `Firmowid.Ash.Ksef.invoice_url!()` |

### Web layer — HEEx templates (1 file)

| File | Current reference | New reference |
|------|------------------|---------------|
| `lib/firmowid_web/invoicing/sales_invoices/components/shared_page/show.html.heex:84` | `Firmowid.Ksef.invoice_url!(invoice)` | `Firmowid.Ash.Ksef.invoice_url!(invoice)` |

### Ash domain layer (4 files)

| File | Current reference | New reference |
|------|------------------|---------------|
| `lib/firmowid/ash/invoicing/invoicing.ex:325` | `Firmowid.Ksef.get_invoice_xml_by_ksef_number(...)` | `Firmowid.Ash.Ksef.get_invoice_xml_by_ksef_number(...)` |
| `lib/firmowid/ash/invoicing/services/timeline.ex:10-11` | `alias Firmowid.Ksef` + `alias Firmowid.Ksef.SubmissionInfo` | `alias Firmowid.Ash.Ksef` + `alias Firmowid.Ash.Ksef.SubmissionInfo` |
| `lib/firmowid/ash/invoicing/changes/normalize_reverse_charge_vat_rates.ex:24` | `alias Firmowid.Ksef.VatRate` | `alias Firmowid.Ash.Ksef.VatRate` |
| `lib/firmowid/ash/invoicing/validations/validate_vat_rate.ex:11` | `alias Firmowid.Ksef.VatRate` | `alias Firmowid.Ash.Ksef.VatRate` |

### Seeds (2 files)

| File | Current reference | New reference |
|------|------------------|---------------|
| `priv/repo/seeds/bytecraft.exs:14` | `alias Firmowid.Ksef.Credential` | `alias Firmowid.Ash.Ksef.Credential` — and update usage to use Ash seed: `Ash.Seed.seed!(Credential, %{...})` instead of `%Credential{} \|> Credential.changeset(...) \|> Repo.insert(...)` |
| `priv/repo/seeds/month_m0.exs:406,467` | `'Firmowid.Ksef.SubmissionWorker'` | `'Firmowid.Ash.Ksef.Workers.SubmissionWorker'` |

## Step 13: Delete old files and directories

Delete in order (files first, then empty directories):

```
rm lib/firmowid/ksef.ex
rm lib/firmowid/ksef/credential.ex
rm lib/firmowid/ksef/session_worker.ex
rm lib/firmowid/ksef/submission_worker.ex
rm lib/firmowid/ksef/fetch_worker.ex
rm lib/firmowid/ksef/fetch_dispatcher.ex
rm lib/firmowid/ksef/api_client.ex
rm lib/firmowid/ksef/encryption.ex
rm lib/firmowid/ksef/invoice_parser.ex
rm lib/firmowid/ksef/invoice_renderer.ex
rm lib/firmowid/ksef/vat_rate.ex
rm lib/firmowid/ksef/submission_info.ex
rm lib/firmowid/ksef/fa3_invoice_template.xml.eex
rm lib/firmowid/ksef/invoice_parser_test.exs
rm lib/firmowid/ksef/invoice_renderer_test.exs
rm lib/firmowid/ksef/invoice_correction_test.exs
rm test/ksef_helpers.ex
rm lib/firmowid/oban/ksef_aware_pruner.ex
rm lib/firmowid/nbp/api_client.ex
rm lib/firmowid/resend/client.ex
rm lib/firmowid/reducto_api_client.ex
rmdir lib/firmowid/ksef
rmdir lib/firmowid/oban
rmdir lib/firmowid/nbp
rmdir lib/firmowid/resend
```

## Step 14: Verify

```bash
mix check
```

Must pass: compile, format, credo, sobelow, tests.

Additionally verify:
- `grep -r "Firmowid.Ksef" lib/ config/ priv/ test/` returns zero hits (except docs)
- `grep -r "Firmowid.Oban.KsefAwarePruner" lib/ config/` returns zero hits (except docs)
- `grep -r "Firmowid.Nbp" lib/` returns zero hits
- `grep -r "Firmowid.Resend" lib/` returns zero hits
- `grep -r "Firmowid.ReductoApiClient" lib/` returns zero hits
- `grep -r "CostInvoices.CostInvoice" lib/` returns zero hits (bug fix verified)
