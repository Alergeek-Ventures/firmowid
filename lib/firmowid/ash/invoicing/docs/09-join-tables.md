# Phase 9: Clean Up Join Tables

## Goal

Rewrite `SalesInvoiceTransaction.create_connections` and `CostInvoiceTransaction.create_connections`
to use Ash instead of internal Ecto.Multi with legacy join schemas.

## Current state

Both resources have a generic action `:create_connections` that:
1. Accepts `invoice_ids`, `transaction_ids`, `organization_id`
2. Uses `Ecto.Multi` to insert join table rows
3. References legacy Ecto join schemas (`SalesInvoicesTransactions`, `CostInvoicesTransactions`)
4. Updates transaction `skip_invoicing` to false

## Target state

Replace `Ecto.Multi` with Ash `bulk_create` on proper Ash resources for the join table.

The join resources already exist as Ash resources but only for the generic action. They
need `:create` and `:destroy` actions for proper Ash usage.

### Add to join resources:

```elixir
# SalesInvoiceTransaction
actions do
  defaults [:read, :destroy]

  create :create do
    accept [:sales_invoice_id, :transaction_id]
  end

  action :create_connections do
    # Rewrite: use Ash.bulk_create instead of Ecto.Multi
    argument :invoice_ids, {:array, :uuid_v7}
    argument :transaction_ids, {:array, :uuid_v7}

    run fn input, context ->
      opts = Ash.Context.to_opts(context)

      pairs = for invoice_id <- input.arguments.invoice_ids,
                  transaction_id <- input.arguments.transaction_ids do
        %{sales_invoice_id: invoice_id, transaction_id: transaction_id}
      end

      Ash.bulk_create(SalesInvoiceTransaction, :create, pairs, opts ++ [return_errors?: true])
      # Also update transactions to clear skip_invoicing
      ...
    end
  end
end
```

Same pattern for `CostInvoiceTransaction`.

## Delete legacy join schemas

After rewrite:
- Delete `lib/firmowid/sales_invoices/sales_invoices_transactions.ex`
- Delete `lib/firmowid/cost_invoices/cost_invoices_transactions.ex`

## Testing

1. Create connections → verify join rows created
2. Duplicate connection → verify idempotent (or error, depending on constraint)
3. Verify transaction skip_invoicing updated
