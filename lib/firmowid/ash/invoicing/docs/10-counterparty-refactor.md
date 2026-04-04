# Phase 10: Refactor Counterparty to Shared Modules

## Goal

Replace the monolithic `ValidateCounterparty` change with shared validation/change
modules from Phase 1. Delete the legacy Ecto counterparty schema.

## Current state

`Firmowid.Ash.Invoicing.Counterparty` uses `ValidateCounterparty` change which inlines
all validation logic. The legacy `Firmowid.SalesInvoices.Counterparty` Ecto schema
still exists and exports `validate_nip/2`, `validate_eu_vat/2`, `validate_optional_id/2`
which are imported by the legacy SalesInvoice changeset.

## Changes

### Replace ValidateCounterparty in Counterparty actions

Before:
```elixir
create :create do
  accept [...]
  change {ValidateCounterparty, []}
end
```

After:
```elixir
create :create do
  accept [...]
  change {ValidateCountryCode, field: :country}
  change {ValidateCountryCode, field: :mail_country}
  change {ClearIrrelevantBuyerFields,
    type_field: :type,
    company_fields: [:tax_id, :full_name],
    individual_fields: [:pesel, :given_name, :surname]}
  validate {ValidateTaxId,
    id_field: :tax_id, country_field: :country, pesel_field: :pesel, type_field: :type}
  validate {ValidateNameFields,
    type_field: :type, full_name_field: :full_name,
    given_name_field: :given_name, surname_field: :surname}
end
```

Same for `:update` action.

### Remove from Counterparty module

- `validate_nip/2`, `validate_eu_vat/2`, `validate_optional_id/2` — no longer needed
  as public Ecto changeset functions once legacy SalesInvoice schema is deleted
- `import Ecto.Changeset` — no longer needed
- `tax_id_type/1` Ecto.Changeset variant — no longer needed

### Keep on Counterparty module

- `display_label/1` — pure function, still used by templates
- `tax_id_type/1` struct variant — still used by templates and logic
- Calculations: `:display_label`, `:tax_id_type`, `:list_all_order`

### Delete

- `lib/firmowid/ash/invoicing/changes/validate_counterparty.ex`
- `lib/firmowid/sales_invoices/counterparty.ex` (legacy Ecto schema)

### Update callers

Any remaining imports of `validate_nip/2` etc. from legacy counterparty → removed
(SalesInvoice legacy schema deletion in Phase 11 removes the last importer)

## Testing

1. Create counterparty with NIP → valid
2. Create counterparty with invalid NIP → error
3. Create counterparty with EU VAT → valid
4. Switch type individual→company → verify fields cleared
5. Verify all existing counterparty tests pass
