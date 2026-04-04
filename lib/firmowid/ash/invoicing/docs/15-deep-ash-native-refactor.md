# Phase 15 — Deep Ash-Native Refactor

Eliminate ALL remaining imperative functions from invoicing resources. No
"justified keeps" — every function gets an Ash-native replacement or gets
deleted. Align all resources with the Transaction reference pattern.

## Guiding principles

- **Transaction is the reference implementation** — its `:read` action with
  `reconciliation` argument and declarative `prepare build...where
  argument_equals` pattern is the standard.
- **Calculations replace functions** — `Ash.load!/3` and `Ash.calculate/3`
  work on plain structs without DB. No need for duplicate imperative functions.
- **Expression calcs over module calcs** — inline `expr()` is preferred. Module
  calcs only when relationship traversal or external API calls are required.
- **Aggregates over computed functions** — `sum`, `first` aggregates are
  SQL-pushable, filterable, sortable.
- **Domain is the public API** — orchestration lives on the domain module.
- **View logic stays in views** — sort comparators, form-specific helpers.

## Key discoveries (this session)

- **`Ash.calculate/3` works on plain structs** — no DB needed. Leaf expression
  calcs evaluate in Elixir when given a record.
- **`Ash.load!/3` resolves calc dependency chains on plain structs** — even
  `gross_value` (depends on `net_value` + `vat_value`) resolves correctly on a
  fabricated `SalesInvoiceItem` struct.
- **Ash `cond` translates to SQL `CASE WHEN`** — no `fragment` needed for the
  VAT rate conversion. Pure `expr(cond do ... end)` is both SQL-pushable and
  Elixir-evaluable.
- **Expression calcs can reference other expression calcs** — dependencies are
  resolved automatically. Confirmed in Ash docs: "calculations that reference
  other calculations (including other `:auto` calculations — dependencies are
  resolved automatically)."
- **`Ash.Query.combination_of` exists but is same-resource only** — cannot
  replace cross-resource UNION. Keep raw Ecto for months query, wrap in generic
  action.
- **`first` aggregate with `sort:` gets latest related record's field** —
  `first :latest_correction_currency, :correction_invoices, :currency do sort
  ksef_permanent_storage_date: :desc end`. DB-pushable.
- **`exists` in expressions handles "has corrections" / "has transactions"** —
  `expr(exists(corrections, true))` for boolean checks.
- **`AshPhoenix.Form.value/2` is the canonical API** — no form-level calcs
  exist. Form-specific logic belongs in the LiveView.

## Phase 0: SalesInvoiceItem — pure expression calcs

Replace module calcs + `gross_value_sql` with inline expression calcs:

```elixir
calculations do
  calculate :vat_rate_numeric, :decimal, expr(
    cond do
      vat_rate == "23" -> 0.23
      vat_rate == "22" -> 0.22
      vat_rate == "8" -> 0.08
      vat_rate == "7" -> 0.07
      vat_rate == "5" -> 0.05
      vat_rate == "4" -> 0.04
      vat_rate == "3" -> 0.03
      true -> 0
    end
  )

  calculate :net_value, :decimal, expr(quantity * unit_price)
  calculate :vat_value, :decimal, expr(net_value * vat_rate_numeric)
  calculate :gross_value, :decimal, expr(net_value + vat_value)
end
```

All SQL-pushable. All work on plain structs via `Ash.load!/3`. No modules, no
fragments, no plain functions.

### Actions

1. Replace 4 calcs (3 module + gross_value_sql) with 4 inline expression calcs
2. Delete `get_net_value/1`, `get_vat_value/1`, `get_gross_value/1`
3. Delete `calculations/item_net_value.ex`, `item_vat_value.ex`, `item_gross_value.ex`
4. Update SalesInvoice aggregate: `gross_value_sql` → `gross_value`
5. Update ~16 callsites: `SalesInvoiceItem.get_net_value(item)` → `item.net_value`

## Phase 1: SalesInvoice — aggregates replace module calcs

Replace module calcs with `sum` aggregates:

```elixir
aggregates do
  sum :net_value, :sales_invoice_items, :net_value
  sum :vat_value, :sales_invoice_items, :vat_value
  sum :gross_value, :sales_invoice_items, :gross_value
end
```

Rounding is a display concern — `Money.new(currency, value)` at callsites
handles it. Aggregates give raw precision, which is correct.

Delete `buyer_display_name/1` — use existing `buyer_display_name_label` calc.
Add description to the calc noting future schema alignment is planned.

### Actions

1. Replace 3 module calcs with 3 sum aggregates
2. Remove `gross_total` aggregate (now redundant)
3. Update search action to use `:gross_value`
4. Delete `get_net_value/1`, `get_vat_value/1`, `get_gross_value/1`
5. Delete `calculations/invoice_net_value.ex`, `invoice_vat_value.ex`, `invoice_gross_value.ex`
6. Delete `buyer_display_name/1`, update ~10 callsites to `buyer_display_name_label`
7. Update ~30 callsites: `SalesInvoice.get_gross_value(x)` → `x.gross_value`

## Phase 2: Predicates — use calc fields

Expression calcs already exist (`is_draft`, `is_confirmed`, `is_ksef_submitted`,
`is_deletable`, `is_ksef_imported`). Delete the duplicate functions, update
callsites to use loaded calc fields.

### Actions

1. Delete SalesInvoice `draft?/1`, `confirmed?/1`, `ksef_submitted?/1`, `deletable?/1`
2. Update ~19 callsites to use `.is_draft`, `.is_confirmed`, etc.
3. Delete CostInvoice `ksef_imported?/1`, `deletable?/1`
4. Update 2 callsites

## Phase 3: Orchestration → domain

Move from SalesInvoice to `Invoicing` domain:

- `get_logo_url/1` — crosses to Accounts context
- `get_currency_rate/1` + `get_currency_conversion_date/2` — external NBP API
- `get_next_numbers_for_series/3` — fans out multiple Ash action calls

### Actions

1. Move 3 functions (+1 private helper) to `invoicing.ex`
2. Update all callsites

## Phase 4: Entries refactor — align with Transaction reference

### Argument alignment

Rename `status` → `reconciliation` across all three resources. Uniform values:
`:pending`, `:matched`, `:skipped`. Use declarative `prepare build...where
argument_equals` pattern (Transaction is the reference).

SalesInvoice gets a separate `submission` argument: `:draft`, `:confirmed`.

**Transaction** (reference — rename only):
- `status` → `reconciliation`
- Values stay: `:pending`, `:matched`, `:skipped`

**CostInvoice** (expand + align):
- `status` → `reconciliation`
- `:unmatched` → `:pending`
- Add `:matched`, `:skipped`
- Replace inline `prepare fn` with declarative `prepare build...where argument_equals`

**SalesInvoice** (expand + split):
- `status` → `reconciliation`
- `:unmatched` → `:pending`
- Add `:matched`, `:skipped`
- Split `:confirmed` into separate `submission` argument with `:draft`/`:confirmed`
- Replace inline `prepare fn` with declarative pattern

### View refactor

`index.ex` calls domain list functions directly — no `Entries` middleman.
Sort logic moves to view as private helpers reading loaded fields/calcs.

### Months query

Wrap UNION in a generic action on the domain.

### Actions

1. Align CostInvoice `:read` action
2. Align SalesInvoice `:read` action
3. Rename Transaction `status` → `reconciliation`
4. Update all callsites (entries.ex, invoice_matching.ex, analysis.ex, index.ex)
5. View layer calls domain list functions directly
6. Sort as private view helpers using loaded calcs
7. Wrap months UNION in generic action
8. Delete `entries.ex`

## Phase 5: Remaining functions

### Dead code — delete

- `SalesInvoice.buyer_from_eu?/1` — zero callers
- `SalesInvoice.buyer_region/1` — zero callers
- `CostInvoice.correction_invoice?/1` — zero callers

### Counterparty — inline expression calcs

**`display_label/1`** → expression calc:

```elixir
calculate :display_label, :string, expr(
  cond do
    not is_nil(display_name) and display_name != "" -> display_name
    type == :company -> full_name
    true -> given_name <> " " <> surname
  end
)
```

Delete `CounterpartyDisplayLabel` module calc + plain function.

**`tax_id_type/1`** → expression calc:

```elixir
calculate :tax_id_type, :atom, expr(
  cond do
    not is_nil(pesel) and pesel != "" -> :no_id
    country == "PL" -> :nip
    country in ~w(AT BE BG CY CZ DK EE FI FR DE EL HR HU IE IT LV LT LU MT NL PT RO SK SI ES SE XI) -> :eu_vat
    not is_nil(country) -> :other_id
    true -> :no_id
  end
)
```

Delete `CounterpartyTaxIdType` module calc + plain function.

### SalesInvoice.effective_snapshot/1 → module calc

Returns latest correction or self. Module calc because it returns a full struct:

```elixir
calculate :effective_snapshot, :struct, EffectiveSnapshot do
  constraints instance_of: __MODULE__
end
```

Module loads `[:latest_correction]`, returns `latest_correction || record`.

### SalesInvoice.editable?/1 → is_editable module calc

Complex predicate with relationship traversal. KOR "is latest correction"
branch cannot be expressed in pure `expr()` — needs
`max(corrected_invoice.corrections).id == id`.

Module calc loads `[:corrections, corrected_invoice: :corrections]`.

### SalesInvoice.buyer_id_type/1 → split

Struct clause → expression calc (same `cond` as Counterparty's `tax_id_type`
but with `buyer_country`, `buyer_pesel`, `buyer_type`).

Form clause (`AshPhoenix.Form`) → move to LiveView as private helper.
`AshPhoenix.Form.value/2` is view logic.

### CostInvoice.merge_corrections_into_original_invoice/1 → aggregates + calcs

Use `first` aggregates for latest snapshot fields, `sum` for total:

```elixir
aggregates do
  sum :corrections_total_amount, :correction_invoices, :total_amount
  first :latest_correction_currency, :correction_invoices, :currency do
    sort ksef_permanent_storage_date: :desc
  end
  first :latest_correction_seller, :correction_invoices, :seller do
    sort ksef_permanent_storage_date: :desc
  end
  # ... per field needed by callers
end

calculations do
  calculate :effective_total_amount, :decimal,
    expr(total_amount + (corrections_total_amount || 0))
  calculate :effective_currency, :string,
    expr(latest_correction_currency || currency)
  # ...
end
```

DB-pushable, filterable. Delete plain function, update 3 callsites.

### Invoice numbering helpers — stay as-is for now

`parse_invoice_number/1`, `format_invoice_number/4`, and private helpers are
action infrastructure. Revisit later.

### Actions

1. Delete dead code (3 functions)
2. Counterparty `display_label` → expression calc, delete module + function
3. Counterparty `tax_id_type` → expression calc, delete module + function
4. `effective_snapshot` → module calc
5. `editable?` → `is_editable` module calc
6. `buyer_id_type` → expression calc + move Form clause to LiveView
7. `merge_corrections_into_original_invoice` → aggregates + effective calcs

## Justified Ecto exceptions (remaining)

| Exception | File | Reason |
|-----------|------|--------|
| Oban job count | `invoicing.ex` | Oban has no count API |
| Cross-tenant share token lookup | `sales_invoice.ex` | Ash multitenancy can't be bypassed |
| Months UNION (generic action) | `invoicing.ex` | Cross-resource UNION, Ash `combination_of` is same-resource only |
| Postgres regex in numbering | `sales_invoice.ex` | `fragment("? ~ ?")` — no Ash regex operator |

## References

- Ash expressions (exists, first, parent, cond): https://hexdocs.pm/ash/expressions.html
- Ash calculations guide: https://hexdocs.pm/ash/calculations.html
- Ash aggregates (first with sort, sum): https://hexdocs.pm/ash/aggregates.html
- Combination queries (same-resource UNION): https://hexdocs.pm/ash/combination-queries.html
- AshPhoenix.Form.value/2: https://hexdocs.pm/ash_phoenix/AshPhoenix.Form.html#value/2
- Forum: relationship references in calcs: https://elixirforum.com/t/referring-to-relationships-in-calculations/60717
- Forum: complex joins with parent: https://elixirforum.com/t/aggregate-that-requires-complex-joins/69741
