# Phase 1: Shared Validation & Change Modules

## Goal

Extract validation and change logic from the monolithic `ValidateCounterparty` change
and from legacy Ecto changesets into composable, configurable Ash modules. These modules
are the foundation — used by WizardDraft, SalesInvoice, AND Counterparty.

## Directory structure

```
lib/firmowid/ash/invoicing/
  validations/
    validate_country_code.ex
    validate_tax_id.ex       # dispatches to NIP/EU_VAT/optional based on context
    validate_name_fields.ex
    validate_vat_rate.ex
    check_if_locked.ex
  changes/
    clear_irrelevant_buyer_fields.ex   # was: cast_buyer_based_on_type
    cast_based_on_invoice_type.ex      # was: cast_based_on_type
    normalize_reverse_charge_vat_rates.ex
    calculate_due_date.ex
    set_item_names.ex
    set_is_cash_account.ex
    prepare_correction.ex
    generate_share_token.ex
    validate_counterparty.ex           # REFACTORED: thin wrapper composing shared modules
```

## Validation modules — spec

### ValidateCountryCode

**Source:** `sales_invoice.ex:440`, `counterparty.ex:80`, `ValidateCounterparty:24`

**Options:**
- `:field` — atom, the attribute to validate (e.g. `:buyer_country`, `:country`)

**Logic:**
1. Read attribute value via `Ash.Changeset.get_attribute(changeset, field)`
2. If nil → skip (allow_nil is handled by attribute constraints)
3. Normalize: `CountryCodes.normalize(value)` — upcases, trims
4. If normalized differs → `force_change_attribute(changeset, field, normalized)`
5. Validate: `CountryCodes.valid_country?(normalized)` → add error if false

**Error:** `field: field, message: "musi być prawidłowym kodem ISO kraju"`

**Type:** `use Ash.Resource.Validation` (pure validation with side effect of normalization —
technically a change, but logically a validation. Use `Ash.Resource.Change` since it
modifies the changeset.)

Actually — since it normalizes (modifies the changeset), it MUST be a Change, not a Validation.
Validations cannot modify changesets.

**Decision: Make it a Change module.** Move to `changes/normalize_and_validate_country_code.ex`.
Or keep the validation pure and add a separate normalization change? Two modules for one field
is over-engineering. Keep as one Change.

**Final location:** `changes/validate_country_code.ex` (it's a change that also validates)

### ValidateTaxId

**Source:** `sales_invoice.ex:490`, `counterparty.ex:104`, `ValidateCounterparty:50`

**Options:**
- `:id_field` — atom, the tax ID field (`:buyer_id` or `:tax_id`)
- `:country_field` — atom (`:buyer_country` or `:country`)
- `:pesel_field` — atom (`:buyer_pesel` or `:pesel`)
- `:type_field` — atom, optional (`:buyer_type` or `:type`). If nil, not used in dispatch.

**Logic:**
1. Read country, pesel, type from changeset via configured field names
2. Determine `tax_id_type` via `CountryCodes.tax_id_type(country, pesel, type)`
3. Read tax_id value
4. Dispatch:
   - `:nip` → regex `^[1-9]((\d[1-9])|([1-9]\d))\d{7}$`
   - `:eu_vat` → regex `^(\d|[A-Z]|\+|\*){1,12}$`
   - `:optional_id` / `:other_id` → max length 50
   - `:no_id` → skip
5. Validate format only if value is present (non-nil, non-empty)

**Error messages:**
- NIP: `"musi być numerem NIP"`
- EU VAT: `"musi być numerem VAT-EU"`
- Optional: `"musi mieć maksymalnie 50 znaków"`

**Type:** `use Ash.Resource.Validation` (pure validation, no modification)

### ValidateNameFields

**Source:** `sales_invoice.ex:472`, `counterparty.ex:154`, `ValidateCounterparty:95`

**Options:**
- `:type_field` — atom (`:buyer_type` or `:type`)
- `:full_name_field` — atom (`:buyer_full_name` or `:full_name`)
- `:given_name_field` — atom (`:buyer_given_name` or `:given_name`)
- `:surname_field` — atom (`:buyer_surname` or `:surname`)

**Logic:**
- If type == `:company` → require `full_name_field` non-nil, non-empty
- If type == `:individual` → require `given_name_field` AND `surname_field`

**Type:** `use Ash.Resource.Validation`

### ValidateVatRate

**Source:** `sales_invoice_item.ex:60`

**Options:** none (or `:field`, default `:vat_rate`)

**Logic:** `validate_inclusion(vat_rate, VatRate.valid_rates())`

**Error:** `"nieprawidłowa stawka VAT"`

**Type:** `use Ash.Resource.Validation`

### CheckIfLocked

**Source:** `sales_invoice.ex:749`

**Options:** none

**Logic:** If `locked_at` is not nil → add error

**Error:** `field: :base, message: "faktura jest zablokowana i nie może być modyfikowana"`

**Type:** `use Ash.Resource.Validation`

## Change modules — spec

### ClearIrrelevantBuyerFields

**Source:** `sales_invoice.ex:452`, `counterparty.ex:133`, `ValidateCounterparty:131`

**Options:**
- `:type_field` — atom (`:buyer_type` or `:type`)
- `:company_fields` — list of atoms to clear when switching to individual
  - SalesInvoice: `[:buyer_id, :buyer_full_name]`
  - Counterparty: `[:tax_id, :full_name]`
- `:individual_fields` — list of atoms to clear when switching to company
  - SalesInvoice: `[:buyer_pesel, :buyer_given_name, :buyer_surname]`
  - Counterparty: `[:pesel, :given_name, :surname]`

**Logic:**
1. Check if `type_field` has CHANGED (not just current value — only clear on type switch)
2. If changed to `:individual` → `force_change_attribute` each company_field to nil
3. If changed to `:company` → `force_change_attribute` each individual_field to nil

**Important:** Use `Ash.Changeset.changing_attribute?(changeset, type_field)` to detect change.
Only clear on actual type transitions, not on every update.

### CastBasedOnInvoiceType

**Source:** `sales_invoice.ex:529`

**Options:** none (field names are fixed — `invoice_type`, `currency`, `is_reverse_charge`, `is_cash_account`)

**Logic:**
1. If `invoice_type` changed to `:poland` → force `currency: "PLN"`, `is_reverse_charge: false`
2. If `invoice_type` changed to `:foreign` → force `is_cash_account: false`
3. Only act on change, not on every update

### NormalizeReverseChargeVatRates

**Source:** `sales_invoice.ex:267`

**Dual mode** — works on both WizardDraft (items as attribute) and SalesInvoice (items
as argument for `manage_relationship`). See doc 02 for full implementation with
`:source` and `:field` options.

**Options:**
- `:source` — `:attribute` or `:argument` (where to read/write items)
- `:field` — atom (`:items` for WizardDraft, `:sales_invoice_items` for SalesInvoice)

**Logic:**
1. Read `is_reverse_charge` from changeset attribute
2. Read items from attribute or argument (based on `:source`)
3. If nil → skip
4. Determine target_rate:
   - If `is_reverse_charge` → `"oo"`
   - Else → compute fallback from `VatRate.available_rates(buyer_country, buyer_id_type)`
5. For each item (handle both structs from attributes and maps from arguments):
   - If `is_reverse_charge` → force `vat_rate: target_rate`
   - If not reverse charge AND current rate is `"oo"` → force `vat_rate: target_rate`
   - Otherwise → keep current rate
6. Write back via attribute or argument (based on `:source`)

**Note on buyer_id_type computation:** Needs `buyer_country`, `buyer_pesel`, `buyer_type`
from the changeset. On WizardDraft these are attributes. On SalesInvoice they're also
attributes. Use `Ash.Changeset.get_attribute/2`.

### CalculateDueDate

**Source:** `sales_invoice.ex:394`

**Options:** none (uses fixed field names: `sale_date`, `due_date`, `due_date_days`)

**Logic:**
1. Read `sale_date` from changeset (attribute or argument — check both)
2. Read `due_date_days` from argument
3. If both present → `force_change_attribute(:due_date, Date.add(sale_date, due_date_days))`

**Note:** `due_date_days` is an action argument, not a persisted attribute. It's used
by the wizard payment step and the edit view for UX convenience.

### SetItemNames

**Source:** implicit in `changeset/2` — denormalizes item names into `item_names` field

**Options:** none

**Logic:**
1. After SalesInvoice create/update, read the persisted items
2. Concatenate all item names with space separator
3. Set `item_names` attribute

**Implementation:** Use `after_action` hook since items are created via `manage_relationship`
and aren't available as attributes during the changeset phase.

### SetIsCashAccount

**Source:** implicit

**Logic:** `force_change_attribute(:is_cash_account, payment_method == :cash)`

### PrepareCorrection

**Source:** `sales_invoice.ex:592`

**Options:** none

**Logic:**
1. Read `original_invoice_id` argument
2. Load original invoice (or latest snapshot)
3. Copy seller/buyer/payment fields from reference invoice to changeset
4. Set `ksef_invoice_kind: :kor`, `corrected_invoice_id: original_invoice.id`
5. Set `organization_id` from original

### GenerateShareToken

**Source:** `sales_invoices.ex:622`

**Logic:**
1. If `share_token` already set → skip
2. Generate: `:crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)`
3. Set `share_token` attribute

## Refactoring ValidateCounterparty

The existing `ValidateCounterparty` change becomes a thin composition:

```elixir
def change(changeset, _opts, _context) do
  changeset
  |> ValidateCountryCode.change(:country)
  |> ValidateCountryCode.change(:mail_country)
  |> ValidateTaxId.validate(changeset, id_field: :tax_id, country_field: :country, pesel_field: :pesel)
  |> ValidateNameFields.validate(changeset, ...)
  |> ClearIrrelevantBuyerFields.change(changeset, ...)
end
```

Or better: remove `ValidateCounterparty` entirely and compose directly in the action:

```elixir
create :create do
  ...
  change {ValidateCountryCode, field: :country}
  change {ValidateCountryCode, field: :mail_country}
  validate {ValidateTaxId, id_field: :tax_id, country_field: :country, pesel_field: :pesel}
  validate {ValidateNameFields, type_field: :type, ...}
  change {ClearIrrelevantBuyerFields, type_field: :type, ...}
end
```

This is more explicit, composable, and follows Ash conventions. Delete `ValidateCounterparty`.

## Testing

Each module gets a unit test. Since these are pure functions on changesets:

```elixir
# test inline in the module file (colocated tests per codebase convention)
test "ValidateCountryCode normalizes and validates" do
  changeset = Ash.Changeset.for_create(SalesInvoice, :create, %{buyer_country: "pl"})
  result = ValidateCountryCode.change(changeset, [field: :buyer_country], %{})
  assert Ash.Changeset.get_attribute(result, :buyer_country) == "PL"
end
```

## Execution order

1. Create `changes/validate_country_code.ex` — simplest, used most widely
2. Create `validations/validate_tax_id.ex`
3. Create `validations/validate_name_fields.ex`
4. Create `changes/clear_irrelevant_buyer_fields.ex`
5. Create `changes/cast_based_on_invoice_type.ex`
6. Create `validations/validate_vat_rate.ex`
7. Create `validations/check_if_locked.ex`
8. Create `changes/normalize_reverse_charge_vat_rates.ex`
9. Create `changes/calculate_due_date.ex`
10. Create `changes/set_item_names.ex`
11. Create `changes/set_is_cash_account.ex`
12. Create `changes/prepare_correction.ex`
13. Create `changes/generate_share_token.ex`
14. Refactor Counterparty actions to use shared modules (delete ValidateCounterparty)
15. Test all modules
