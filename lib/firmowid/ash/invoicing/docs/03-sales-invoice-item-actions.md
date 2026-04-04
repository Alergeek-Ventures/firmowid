# Phase 3: SalesInvoiceItem Write Actions

## Goal

Add `:create`, `:update`, `:destroy` actions to the existing Ash SalesInvoiceItem resource.
These are needed for `manage_relationship(:sales_invoice_items, type: :direct_control)` on
SalesInvoice.

## Current state

`sales_invoice_item.ex` has:
- Attributes: id, index, name, quantity, unit, unit_price, vat_rate
- Relationships: belongs_to sales_invoice, belongs_to organization
- Actions: only `:read`
- Public functions: `get_net_value/1`, `get_vat_value/1`, `get_gross_value/1`

## Changes

Add to the `actions` block:

```elixir
actions do
  defaults [:read, :destroy]

  create :create do
    accept [:index, :name, :quantity, :unit, :unit_price, :vat_rate]
    validate {ValidateVatRate, []}
  end

  update :update do
    require_atomic? false
    accept [:index, :name, :quantity, :unit, :unit_price, :vat_rate]
    validate {ValidateVatRate, []}
  end
end
```

Add policies for write actions:

```elixir
policies do
  policy action_type(:read) do
    authorize_if always()
  end

  policy action_type([:create, :update, :destroy]) do
    authorize_if always()
  end
end
```

## Notes

- `organization_id` is handled by multitenancy — no need to set it explicitly
- `sales_invoice_id` is set by the relationship management from the parent SalesInvoice
- The legacy changeset set `organization_id` via `Repo.get_org_id()` and `index` via
  function argument — both handled differently in Ash:
  - `organization_id` → multitenancy
  - `index` → accepted attribute, passed by the parent form
- Virtual fields `net_value` and `gross_value` from the legacy schema are NOT attributes
  on the Ash resource — they're computed by the public functions
- `ValidateVatRate` from Phase 1 replaces `validate_inclusion(:vat_rate, VatRate.valid_rates())`

## Testing

1. Create item with valid vat_rate → success
2. Create item with invalid vat_rate → validation error
3. Create item with missing required fields → error
4. Update existing item → success
5. Destroy item → success
