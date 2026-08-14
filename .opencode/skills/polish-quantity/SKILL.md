---
name: polish-quantity
description: Polish pluralization and count labels using PolishQuantity.quantity/4. Use when adding or changing Polish user-facing text that combines an integer with a declined noun.
---

# Polish Quantity Labels

Use this skill when adding or changing a Polish user-facing quantity label,
such as a count of invoices, accounts, transactions, employees, or plan limits.

## Shared Utility

Use `FirmowidWeb.Infrastructure.Utilities.PolishQuantity.quantity/4`:

```elixir
alias FirmowidWeb.Infrastructure.Utilities.PolishQuantity

PolishQuantity.quantity(count, "transakcja", "transakcje", "transakcji")
```

The arguments are, in order:

1. integer quantity
2. singular noun form
3. paucal noun form
4. plural noun form

The function returns the number and correctly declined noun as one string.

## Rules Applied By The Utility

1. `1` and `-1` use the singular form.
2. Values ending in `12`, `13`, or `14` use the plural form.
3. Other values ending in `2`, `3`, or `4` use the paucal form.
4. All other values use the plural form.

The rules use the absolute value, so negative integers follow the same forms.

Examples with `"faktura"`, `"faktury"`, and `"faktur"`:

```elixir
PolishQuantity.quantity(1, "faktura", "faktury", "faktur")
# => "1 faktura"

PolishQuantity.quantity(22, "faktura", "faktury", "faktur")
# => "22 faktury"

PolishQuantity.quantity(12, "faktura", "faktury", "faktur")
# => "12 faktur"
```

## Constraints

- Pass an integer. The utility does not support decimal quantities.
- Supply the correct three noun forms for the specific Polish phrase; do not
  duplicate pluralization logic at the call site.
- Keep surrounding label text outside the utility result when needed, for
  example `"#{PolishQuantity.quantity(count, ...)} / mies."`.
