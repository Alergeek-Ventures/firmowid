# Phase 4: SalesInvoice Write Actions

## Goal

Add all write actions to the existing Ash SalesInvoice resource. This is the largest
and most critical phase. After this, the Ash resource is feature-complete for writes.

## Implementation status

This phase covers two areas with different completion states:

| Area | Status | Details |
|------|--------|---------|
| Write actions (4a) | **Done** | All write actions, generic actions, PubSub, policies, code interfaces, seeds |
| Read consolidation + effective_* (4b) | **Not started** | 10 read actions still separate, `merge_corrections_after_read` still active, no `effective_*` calculations, no module calculations for reference_invoice |

## Actions to add

### :create

Full invoice creation. Used by the confirm-from-draft flow and by tests/seeds.

```elixir
create :create do
  accept [
    :invoice_type, :invoice_number, :sale_date, :issue_date, :due_date,
    :payment_method, :currency, :is_cash_account, :is_reverse_charge,
    :skip_invoicing, :ksef_invoice_kind, :correction_reason,
    :counterparty_id, :corrected_invoice_id,
    # Seller
    :seller_nip, :seller_display_name, :seller_address,
    :seller_name, :seller_surname, :seller_account_number,
    # Buyer
    :buyer_type, :buyer_id, :buyer_full_name, :buyer_given_name,
    :buyer_surname, :buyer_pesel, :buyer_display_name, :buyer_address,
    :buyer_country, :buyer_is_different_mail_address, :buyer_mail_address,
    :buyer_mail_country, :buyer_email, :buyer_phone, :buyer_description
  ]

  argument :sales_invoice_items, {:array, :map}, allow_nil?: false

  change manage_relationship(:sales_invoice_items, type: :direct_control)
  change {NormalizeReverseChargeVatRates, source: :argument, field: :sales_invoice_items}
  change {SetItemNames, []}
  change {SetIsCashAccount, []}
  change {ValidateCountryCode, field: :buyer_country}

  validate {ValidateTaxId,
    id_field: :buyer_id, country_field: :buyer_country,
    pesel_field: :buyer_pesel, type_field: :buyer_type}
  validate {ValidateNameFields,
    type_field: :buyer_type, full_name_field: :buyer_full_name,
    given_name_field: :buyer_given_name, surname_field: :buyer_surname}
  validate present([:issue_date, :currency])

  # invoice_number is NOT required — drafts don't have one
  # This action creates both drafts (no number) and confirmed invoices (with number)
end
```

### :update

Combined update for the edit view. Handles draft editing and confirmed invoice editing.

```elixir
update :update do
  require_atomic? false

  accept [
    :invoice_type, :invoice_number, :sale_date, :issue_date, :due_date,
    :payment_method, :currency, :is_cash_account, :is_reverse_charge,
    :ksef_invoice_kind, :correction_reason, :counterparty_id,
    :seller_nip, :seller_display_name, :seller_address,
    :seller_name, :seller_surname, :seller_account_number,
    :buyer_type, :buyer_id, :buyer_full_name, :buyer_given_name,
    :buyer_surname, :buyer_pesel, :buyer_display_name, :buyer_address,
    :buyer_country, :buyer_is_different_mail_address, :buyer_mail_address,
    :buyer_mail_country, :buyer_email, :buyer_phone, :buyer_description
  ]

  argument :sales_invoice_items, {:array, :map}

  change manage_relationship(:sales_invoice_items, type: :direct_control)
  change {NormalizeReverseChargeVatRates, source: :argument, field: :sales_invoice_items}
  change {SetItemNames, []}
  change {SetIsCashAccount, []}
  change {ValidateCountryCode, field: :buyer_country}

  validate {CheckIfLocked, []}
  validate {ValidateTaxId, ...}
  validate {ValidateNameFields, ...}
end
```

### :create_correction

Creates a correction invoice (KOR) from a VAT invoice.

```elixir
create :create_correction do
  accept [
    :invoice_number, :issue_date, :sale_date, :due_date, :correction_reason,
    :payment_method, :currency, :seller_account_number,
    # Buyer fields (can be edited in correction)
    :buyer_type, :buyer_id, :buyer_full_name, :buyer_given_name,
    :buyer_surname, :buyer_pesel, :buyer_display_name, :buyer_address,
    :buyer_country, :buyer_email, :buyer_phone, :buyer_description,
    :is_reverse_charge
  ]

  argument :original_invoice_id, :uuid_v7, allow_nil?: false
  argument :sales_invoice_items, {:array, :map}, allow_nil?: false

  change {PrepareCorrection, []}
  change manage_relationship(:sales_invoice_items, type: :direct_control)
  change {NormalizeReverseChargeVatRates, source: :argument, field: :sales_invoice_items}
  change {SetItemNames, []}

  validate present([:invoice_number, :issue_date])
  validate string_length(:correction_reason, max: 256)
end
```

PrepareCorrection reads the original invoice, copies seller/buyer fields that weren't
explicitly provided, sets `ksef_invoice_kind: :kor`, `corrected_invoice_id`.

### :cancel (generic action)

Cancels a KSeF-submitted invoice by creating a zero-quantity correction.

```elixir
action :cancel, :struct do
  constraints instance_of: __MODULE__
  argument :invoice_id, :uuid_v7, allow_nil?: false

  run fn input, context ->
    opts = Ash.Context.to_opts(context)
    invoice = Ash.get!(__MODULE__, input.arguments.invoice_id, opts)

    # Validate: must be VAT, must be KSeF submitted
    unless invoice.ksef_invoice_kind == :vat and invoice.ksef_number != nil do
      raise Ash.Error.Invalid, errors: [%{message: "can only cancel KSeF-submitted VAT invoices"}]
    end

    latest = get_latest_invoice_snapshot(invoice)
    issue_date = Date.utc_today()

    # Get next FK-series number via generic action
    invoice_number = ... # call :get_next_number with series: "FK"

    zeroed_items = Enum.map(latest.sales_invoice_items, fn item ->
      item
      |> Map.take([:index, :name, :unit, :unit_price, :vat_rate])
      |> Map.put(:quantity, Decimal.new(0))
    end)

    correction_reason = case latest.invoice_type do
      :foreign -> "Anulowanie faktury / Invoice cancellation"
      _ -> "Anulowanie faktury"
    end

    Ash.create!(__MODULE__, %{
      original_invoice_id: invoice.id,
      invoice_number: invoice_number,
      issue_date: issue_date,
      sale_date: latest.sale_date,
      due_date: latest.due_date,
      correction_reason: correction_reason,
      sales_invoice_items: zeroed_items
    }, Keyword.put(opts, :action, :create_correction))
  end
end
```

### :destroy

```elixir
destroy :destroy do
  validate {CheckIfLocked, []}
  # Also validate no ksef_number
  validate fn changeset, _context ->
    if Ash.Changeset.get_data(changeset, :ksef_number) do
      {:error, field: :base, message: "KSeF-submitted invoices cannot be deleted"}
    else
      :ok
    end
  end
end
```

### :toggle_skip

```elixir
update :toggle_skip do
  accept []
  change fn changeset, _context ->
    current = Ash.Changeset.get_data(changeset, :skip_invoicing)
    Ash.Changeset.change_attribute(changeset, :skip_invoicing, !current)
  end
end
```

### :generate_share_token

```elixir
update :generate_share_token do
  accept []
  change {GenerateShareToken, []}
end
```

### :lock_for_ksef / :unlock_for_ksef / :update_ksef_fields

```elixir
update :lock_for_ksef do
  accept []
  change set_attribute(:locked_at, &DateTime.utc_now/0)
end

update :unlock_for_ksef do
  accept []
  change set_attribute(:locked_at, nil)
end

update :update_ksef_fields do
  accept [:ksef_number, :ksef_session_reference_number, :ksef_invoice_checksum, :locked_at]
end
```

### Generic actions for invoice numbering

```elixir
action :get_next_number, :string do
  argument :date, :date, allow_nil?: false
  argument :series, :string
  argument :omit_invoice_id, :uuid

  run fn input, context ->
    # Port logic from SalesInvoices.get_next_invoice_number/2
    # Uses Ecto queries internally (Ash resource IS Ecto schema)
    ...
  end
end

action :validate_number, {:array, :term} do
  argument :invoice_number, :string, allow_nil?: false
  argument :issue_date, :date, allow_nil?: false
  argument :omit_invoice_id, :uuid

  run fn input, context ->
    # Port logic from SalesInvoices.validate_invoice_number/3
    ...
  end
end

action :list_series, {:array, :string} do
  run fn _input, context ->
    # Port logic from SalesInvoices.list_invoice_series/0
    ...
  end
end
```

## Code interfaces

Add to domain or update existing on resource:

```elixir
code_interface do
  # Existing reads...
  define :create, action: :create
  define :update, action: :update
  define :destroy, action: :destroy
  define :create_correction, action: :create_correction
  define :cancel, args: [:invoice_id], action: :cancel
  define :toggle_skip, action: :toggle_skip
  define :generate_share_token, action: :generate_share_token
  define :lock_for_ksef, action: :lock_for_ksef
  define :unlock_for_ksef, action: :unlock_for_ksef
  define :update_ksef_fields, action: :update_ksef_fields
  define :get_next_number, args: [:date, {:optional, :series}, {:optional, :omit_invoice_id}]
  define :validate_number, args: [:invoice_number, :issue_date, {:optional, :omit_invoice_id}]
  define :list_series, args: []
end
```

## Policies

Replace Bodyguard. Add write policies:

```elixir
policies do
  policy action_type(:read) do
    authorize_if always()
  end

  policy action_type(:action) do
    authorize_if always()
  end

  policy action_type([:create, :update, :destroy]) do
    authorize_if actor_attribute_equals(:role, :admin)
  end
end
```

**Note:** Multitenancy already handles org-level isolation. The policy just checks role.
The `actor: %{}` smell is a known issue — flag but don't fix here.

## PubSub — Use `Ash.Notifier.PubSub`

Follow the existing Transaction/Requisition pattern. Add `notifiers: [Ash.Notifier.PubSub]`
to `use Ash.Resource` and declare a `pub_sub do` block.

The legacy code has two separate broadcast channels consumed by `index.ex`:
1. `sales_invoice_broadcast_topic` — atom `:sales_invoice_list_updated` after create/update/delete/toggle_skip
2. `invoicing_broadcast` — tuple `{:cost_invoice_match, %{...}}` (handled in Phase 8/matching.ex)

Only channel 1 belongs to SalesInvoice. Channel 2 stays in matching.ex as a manual `Phoenix.PubSub.broadcast`.

```elixir
# In SalesInvoice resource:
use Ash.Resource,
  domain: Firmowid.Ash.Invoicing,
  data_layer: AshPostgres.DataLayer,
  authorizers: [Ash.Policy.Authorizer],
  notifiers: [Ash.Notifier.PubSub]

pub_sub do
  module FirmowidWeb.Core.Endpoint
  prefix "sales_invoice"

  publish :create, ["created", :_tenant]
  publish :update, ["updated", :_tenant]
  publish :destroy, ["destroyed", :_tenant]
  publish :toggle_skip, ["updated", :_tenant]
  publish :create_correction, ["created", :_tenant]
  publish :generate_share_token, ["updated", :_tenant]
end
```

The subscriber side in `index.ex` switches from:
```elixir
SalesInvoices.subscribe_sales_invoice_broadcast(organization_id)
# handle_info(:sales_invoice_list_updated, socket)
```
to:
```elixir
FirmowidWeb.Core.Endpoint.subscribe("sales_invoice:created:#{org_id}")
FirmowidWeb.Core.Endpoint.subscribe("sales_invoice:updated:#{org_id}")
FirmowidWeb.Core.Endpoint.subscribe("sales_invoice:destroyed:#{org_id}")
# handle_info(%Ash.Notifier.Notification{resource: SalesInvoice}, socket)
```

Use the existing `PubSubDebounce` module for batching (already used by Transaction notifications).

## Read action consolidation — NOT STARTED (Phase 4b)

Collapse the current 10 read actions into 3. This is part of Phase 4 because the write
actions depend on the read action shape (e.g. `cancel` reads via `by_id`).

**Current state:** All 10 original read actions still exist and are actively used.
Callers reference specific action names. This consolidation requires updating all
callsites (index.ex, entries.ex, matching.ex, etc.).

### Current → New mapping

| Old action | New | Notes |
|---|---|---|
| `:read` (default) | `:read` (primary) | Gains optional arguments |
| `:list_for_month` | `:read` + `date_from/date_to` + `date_field: :issue_date` + `kind: :vat` | |
| `:list_unmatched` | `:read` + `date_from/date_to` + `date_field: :due_date` + `status: :unmatched` | |
| `:list_by_sale_date` | `:read` + `date_from/date_to` + `date_field: :sale_date` | |
| `:list_by_ids` | `:read` + `ids` argument | |
| `:list_invoices_in_date_range` | `:read` + `date_from/date_to` + `date_field: :any` | |
| `:list_recent` | Caller computes 2-month range, passes to `:read` | |
| `:search` (generic, ILIKE) | `:read` + `query` argument with `ParadeDBSearch` preparation | Dead code today — zero callers |
| `:by_id` (get) | `:by_id` — kept as-is | 13 callers, heavy preloads |
| `:by_share_token` (generic) | `:by_share_token` — read action with `multitenancy :bypass` | Zero callers today of Ash version |

### Primary `:read` action

```elixir
read :read do
  primary? true

  argument :date_from, :date
  argument :date_to, :date
  argument :date_field, :atom do
    constraints one_of: [:issue_date, :sale_date, :due_date, :any]
    default :issue_date
  end
  argument :kind, :atom do
    constraints one_of: [:vat, :kor]
  end
  argument :status, :atom do
    constraints one_of: [:unmatched, :confirmed, :draft]
  end
  argument :ids, {:array, :uuid_v7}
  argument :query, :string

  # Date filtering — conditional on date_field
  prepare {FilterByDateField, []}

  # Kind filter
  prepare build(filter: expr(ksef_invoice_kind == ^arg(:kind))) do
    where present(:kind)
  end

  # Status: unmatched — no linked transactions, not skipped
  prepare build(
    filter: expr(
      not exists(transactions, true) and skip_invoicing == false
    )
  ) do
    where argument_equals(:status, :unmatched)
  end

  # Status: confirmed — has invoice_number
  prepare build(filter: expr(not is_nil(invoice_number))) do
    where argument_equals(:status, :confirmed)
  end

  # Status: draft — no invoice_number
  prepare build(filter: expr(is_nil(invoice_number))) do
    where argument_equals(:status, :draft)
  end

  # Filter by IDs
  prepare build(filter: expr(id in ^arg(:ids))) do
    where present(:ids)
  end

  # ParadeDB full-text search
  prepare {ParadeDBSearch,
    columns: ~w(invoice_number buyer_full_name buyer_given_name buyer_display_name
                buyer_surname buyer_address buyer_id buyer_pesel buyer_email buyer_description)}
end
```

`FilterByDateField` is a custom preparation that switches the date column based on the
`date_field` argument. For `:any`, it creates an OR filter on issue_date and sale_date.

### `:by_share_token` as read action

```elixir
read :by_share_token do
  multitenancy :bypass

  argument :token, :string, allow_nil?: false

  prepare {ParseShareToken, []}
  prepare build(load: [
    :organization, :sales_invoice_items, :transactions,
    corrections: :sales_invoice_items,
    corrected_invoice: :corrections
  ])
end
```

`ParseShareToken` parses the token (may contain correction ID suffix like `token.correction_id`),
filters by `share_token`, and optionally resolves to a correction invoice.

### Delete legacy read actions

- `list_for_month`, `list_unmatched`, `list_by_sale_date`, `list_by_ids`,
  `list_invoices_in_date_range`, `list_recent` — all replaced by `:read`
- `:search` generic action — dead code, delete
- `EctoSalesInvoice` alias (line 41) — delete
- `merge_corrections_after_read` after_action hook — replaced by `effective_*` calculations

### Code interface update

```elixir
code_interface do
  define :by_id, args: [:id], action: :by_id, get_by: [:id]
  define :read, action: :read
  define :by_share_token, args: [:token], action: :by_share_token
  # ... write actions below ...
end
```

Callers switch from e.g. `SalesInvoice.list_for_month!(from, to, scope: s)` to
`SalesInvoice.read!(date_from: from, date_to: to, date_field: :issue_date, kind: :vat, scope: s)`.

## Correction chain model

### Structure

All KORs (correction invoices) are **siblings** under a single VAT parent. The DB
model is flat — every KOR has `corrected_invoice_id` pointing to the original VAT
invoice. KOR→KOR chains are impossible: `create_correction_invoice` pattern matches
`%SalesInvoice{ksef_invoice_kind: :vat}` — only VAT invoices can be corrected.

```
VAT (original)
 ├── KOR1 (corrected_invoice_id = VAT.id, reference = VAT)
 ├── KOR2 (corrected_invoice_id = VAT.id, reference = KOR1)
 └── KOR3 (corrected_invoice_id = VAT.id, reference = KOR2)
```

Priority is determined by `locked_at/inserted_at` timestamp ordering. The latest
KOR represents the "current state" of the invoice.

### Reference resolution

Each KOR's "before state" (reference invoice) is the **previous sibling** in
timestamp order — or the original VAT for the first correction. This is how
`populate_reference_invoices` works today (line 533-575 of sales_invoice.ex):

For VAT:
```
corrections = sort_by(invoice.corrections, &locked_at)
references = [invoice | corrections]
zip(corrections, references) → [{KOR1, VAT}, {KOR2, KOR1}, {KOR3, KOR2}]
```

For KOR: find corrections on the parent VAT that were locked before this KOR,
take the latest one. If none exist, the reference is the original VAT.

### Constraints enforcing this model

- `create_correction_invoice(%SalesInvoice{ksef_invoice_kind: :vat} = ...)` — function head rejects non-VAT
- `cancel_sales_invoice(%SalesInvoice{ksef_invoice_kind: :vat} = ...)` — same guard
- `editable?` for VAT → `Enum.empty?(corrections)` — once corrected, edit via new KOR only
- `editable?` for KOR → `latest_correction.id == invoice.id` — only latest KOR is editable

## `populate_reference_invoices` → two module calculations — NOT STARTED (Phase 4b)

The legacy `populate_reference_invoices/1` function should be replaced by two module
calculations. These are pure — no internal `Ash.load!` calls. Callsite decides
what to load.

**Current state:** `populate_reference_invoices/1` still exists as a public function
on SalesInvoice (lines 999-1045). It's called from `show.ex`, `summary.ex`,
`invoice_renderer.ex`, and `shared.ex`.

### `:reference_invoice` (module calculation)

Returns the "before" snapshot for a KOR invoice. Returns `nil` for VAT.

```elixir
calculate :reference_invoice, :struct, ReferenceInvoiceCalculation do
  constraints instance_of: __MODULE__
end
```

`load/3`:
```elixir
[:corrected_invoice, corrected_invoice: [:corrections, corrections: :sales_invoice_items]]
```

`calculate/3` — pure, one-level load (chain is always flat):
- VAT → `nil`
- KOR → sort `corrected_invoice.corrections` by timestamp, find the one just before
  this KOR (reject self and later corrections), fall back to original VAT if first KOR

### `:annotated_corrections` (module calculation)

Returns the `corrections` list with each correction annotated with its `reference_invoice`.
Used by renderer/PDF.

```elixir
calculate :annotated_corrections, {:array, :struct}, AnnotatedCorrectionsCalculation do
  constraints items: [instance_of: __MODULE__]
end
```

`load/3`:
```elixir
[:corrections, corrections: :sales_invoice_items]
```

`calculate/3` — pure:
- Sort corrections by `locked_at/inserted_at`
- Zip with `[self | corrections]` to pair each correction with its "before" state

### Delete

- `populate_reference_invoices/1` — replaced by two calculations
- `get_reference_invoice/1` — replaced by `:reference_invoice` calculation
- All callsites switch from `SalesInvoice.populate_reference_invoices(invoice)` to
  `Ash.load!(invoice, [:reference_invoice])` or `Ash.load!(invoice, [:annotated_corrections])`

### Cleanup pass (post-Phase 4)

Convert `get_net_value/1`, `get_vat_value/1`, `get_gross_value/1` on both
SalesInvoice and SalesInvoiceItem from plain functions to Ash calculations.
Currently they require `sales_invoice_items` to be preloaded. As calculations
they become loadable, filterable, composable.

## Correction merging via `effective_*` calculations — NOT STARTED (Phase 4b)

### Problem

26 snapshot fields can be overridden by a correction invoice (KOR). 15 of these are used
in DB-level filters/sorts. A runtime merge (`after_action`) cannot fix DB-level filtering —
queries would return stale results.

**Current state:** `merge_corrections_after_read` runtime merge is still active on 4 read
actions in SalesInvoice and 2 in CostInvoice. The `@snapshot_fields` module attribute and
`merge_latest_correction/1` private function power this. No `has_one :latest_correction`
relationship or `effective_*` calculations exist yet.

### Solution

1. **`has_one :latest_correction`** — self-referential relationship, sorted by recency
2. **`effective_*` expression calculations** — generated by a macro, DB-pushable
3. **Macro in `SalesInvoice.EffectiveFields`** — colocated, not in shared `Ash.Resource`

### Relationship

```elixir
has_one :latest_correction, __MODULE__ do
  destination_attribute :corrected_invoice_id
  sort locked_at: :desc_nils_last, inserted_at: :desc
end
```

### Macro (in `lib/firmowid/ash/invoicing/sales_invoice/effective_fields.ex`)

```elixir
defmodule Firmowid.Ash.Invoicing.SalesInvoice.EffectiveFields do
  @moduledoc """
  Generates `effective_<field>` expression calculations for correction-aware field access.

  Each calculation resolves to:
    if is_nil(latest_correction), do: <field>, else: latest_correction.<field>

  These are expression calculations — pushed to the DB, filterable, sortable.
  """

  @effective_fields [
    invoice_type: :atom, sale_date: :date, due_date: :date,
    payment_method: :atom, currency: :string,
    seller_nip: :string, seller_display_name: :string, seller_address: :string,
    seller_name: :string, seller_surname: :string, seller_account_number: :string,
    buyer_type: :atom, buyer_id: :string, buyer_full_name: :string,
    buyer_given_name: :string, buyer_surname: :string, buyer_pesel: :string,
    buyer_display_name: :string, buyer_address: :string, buyer_country: :string,
    buyer_is_different_mail_address: :boolean, buyer_mail_address: :string,
    buyer_mail_country: :string, buyer_email: :string, buyer_phone: :string,
    buyer_description: :string, is_cash_account: :boolean, is_reverse_charge: :boolean
  ]

  defmacro effective_correction_calculations do
    for {field, type} <- @effective_fields do
      calc_name = :"effective_#{field}"
      quote do
        calculate unquote(calc_name), unquote(type),
          expr(
            if is_nil(latest_correction),
              do: ^ref(unquote(field)),
              else: ^ref([:latest_correction], unquote(field))
          ),
          public?: true
      end
    end
  end
end
```

### Usage in SalesInvoice

```elixir
require Firmowid.Ash.Invoicing.SalesInvoice.EffectiveFields, as: EffectiveFields

calculations do
  # ... existing calculations ...
  EffectiveFields.effective_correction_calculations()
end
```

### Callsite changes

Read actions that currently filter on snapshot fields switch to `effective_*` calculations:
- `date_from/date_to` on `sale_date` → filter on `effective_sale_date`
- `date_from/date_to` on `due_date` → filter on `effective_due_date`
- ParadeDB search on `buyer_full_name` etc. → search on `effective_buyer_full_name` etc.
- Templates displaying `invoice.buyer_full_name` → `invoice.effective_buyer_full_name`
  (or load `:effective_buyer_full_name` and keep template variable name)

### Delete

- `merge_corrections_after_read` after_action hook
- `@snapshot_fields` module attribute
- `get_latest_invoice_snapshot/1` public function (replaced by loading `:latest_correction`)

### References

- Zach Daniel on `after_action` vs calculations: https://elixirforum.com/t/ash-query-after-action-2-with-relationships/68963
- Module calculations with `load/3`: https://jaketrent.com/post/return-related-resource-calculation-ash/
- `has_one` with `sort:` in Ash docs: https://hexdocs.pm/ash/relationships.html
- Spark DSL macro generation: macros expand at compile time, each `calculate` call registers via process dict

## Seeds migration — Done

Seeds migrated to use `Ash.Seed.seed!` internally via `helpers.exs`. The
`get_or_create_sales_invoice/3` public API was preserved (callers unchanged) but its
implementation now uses `Ash.Seed.seed!` for the invoice + items seeded separately.
KSeF field mutations in `month_m0.exs` now use `Ash.Seed.seed!` with upsert by ID
instead of `Ecto.Changeset.change |> Repo.update!`.

**Note:** `get_or_create_cost_invoice/3` still uses `Repo.insert!` with a bare struct.
This is out of scope for the invoicing migration — flag for CostInvoice domain cleanup.

## Unique constraint

The legacy changeset has:
```elixir
unique_constraint([:invoice_number, :organization_id],
  name: :sales_invoices_invoice_number_organization_id_index)
```

In Ash, use an identity:

```elixir
identities do
  identity :invoice_number_per_org, [:invoice_number, :organization_id],
    nils_distinct?: false,
    message: "numer faktury już istnieje dla tej organizacji"
end
```

## Testing

1. Create full invoice → verify all fields persisted
2. Create draft (no invoice_number) → success
3. Update draft → success
4. Update locked invoice → error
5. Create correction → verify KOR kind, corrected_invoice_id set
6. Cancel → verify zero-quantity correction created
7. Destroy confirmed → success
8. Destroy KSeF-submitted → error
9. Toggle skip → verify flip
10. Generate share token → verify token generated, idempotent
11. Lock/unlock for KSeF → verify locked_at
12. Get next number → verify sequence
13. Validate number → verify warnings (duplicate, gap, format)
14. List series → verify distinct series
15. Unique invoice number constraint → verify error on duplicate
