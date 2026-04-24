---
name: ash-policies
description: Project specific rules for creating and maintaining Ash authorization policies. Use this skill instead of searching in docs, whenever you touching policies in a resource
---

# Ash Policies

## Core Model

1. A policy has:
   - conditions (when the policy applies)
   - checks (how the policy decides)
2. Check results are `:authorized`, `:forbidden`, or `:unknown`.
3. Within a policy, checks are evaluated in logical top-to-bottom order; the first check that decides (`:authorized`/`:forbidden`) wins.
4. If all checks are `:unknown`, that policy fails (treated as forbidden).
5. Bypass policies are for early allow cases (for example, super admin).
6. Policy ordering can affect outcomes. Treat policy order as intentional control flow, not as cosmetic ordering.
7. If multiple regular policies apply, all applicable policies must pass.

## Authoring Workflow

1. Inventory actions and actor types
   - List each action (`read`, `create`, `update`, `destroy`, custom actions).
   - Define who should be allowed and denied for each action.
2. Add bypasses first (rare, explicit)
   - Use for global allow paths like super-admin.
   - Keep bypasses minimal and obvious.
3. Start with broad action-type policies
   - Use `action_type(:read)`/`action_type(:update)` where possible.
   - Add a `description` to complex policies with multiple conditions or checks.
4. Encode checks in decision order
   - Put definitive deny checks early when they should dominate.
   - Put fast, global allow checks early when safe.
5. Choose `access_type` intentionally
   - `:filter` (default): read actions filter data.
   - `:strict`: fail with forbidden when unauthorized.
   - `:runtime`: only when truly necessary.
6. Add field policies only when needed
   - If any field policies exist, all fields must be covered (or use `:*` catch-all).
   - If the resource only needs field policies, still add an explicit allow-all regular policy so actions remain authorized.
7. Validate behavior with real scenarios
   - Read list vs. single record.
   - Cross-user access.
   - Relationship loads.

## Non-Negotiables

- Do not assume check order is cosmetic.
- Do not split one coherent decision across multiple regular policies unless you want policy-to-policy interaction.
- Do not reference created record fields inside `expr(...)` checks for create policies.
- Do not add field policies without ensuring every field is covered.
- Do not reach for `:runtime` unless simpler `:strict` or `:filter` policies cannot express the rule.
- Do not put bypasses inside `policy_group`; policy groups cannot contain bypass policies.

## Policy Patterns

### 1) Super-admin bypass

```elixir
policies do
  bypass actor_attribute_equals(:super_user, true) do
    authorize_if always()
  end

  policy action_type(:read) do
    description "Users can read public records or records they own"
    authorize_if expr(public == true)
    authorize_if relates_to_actor_via(:owner)
  end
end
```

### 2) Ordered checks inside one policy

```elixir
policy action_type(:update) do
  description "Deactivated users cannot update, admins and owners can"

  forbid_if actor_attribute_equals(:active, false)
  authorize_if actor_attribute_equals(:admin, true)
  authorize_if relates_to_actor_via(:owner)
end
```

### 3) Create-action expression safety

For create policies, inline expressions must not reference the record being created.

```elixir
policy action_type(:create) do
  authorize_if expr(^actor(:admin) == true)  # valid
  # authorize_if expr(status == :active)     # invalid for create
end
```

If you need richer create-time logic, use a custom `Ash.Policy.SimpleCheck`.

### 4) Relationship checks with `exists`

Prefer `exists/2` in expressions involving related records to avoid unintended over-restriction when filters combine.

```elixir
authorize_if expr(exists(memberships, user_id == ^actor(:id)))
```

### 5) Field policy catch-all

```elixir
field_policies do
  field_policy [:email, :phone] do
    authorize_if actor_attribute_equals(:role, :manager)
  end

  field_policy :* do
    authorize_if always()
  end
end
```

If field policies are present and you are not otherwise restricting action access, add an explicit allow-all action policy:

```elixir
policies do
  policy always() do
    authorize_if always()
  end
end
```

## Read Behavior You Must Preserve

- Read actions are filtered by default, often yielding `NotFound`/missing records instead of `Forbidden`.
- Use `authorize_with: :error` only when explicit forbidden errors are required.
- Relationship loads may return `nil` or `%Ash.ForbiddenField{}` depending on relationship options and policy behavior.

## Debugging and Verification

When outcomes are surprising:

1. Check policy and check ordering first.
2. Confirm whether action is read (filter semantics) or mutation (forbidden semantics).
3. Inspect `access_type` on relevant policies.

## Protip

When working with policies, think of a short authorization matrix (actor x action x expected outcome).

## System Actor Roles

For resources with many system actors with different roles, consider grouping placing them in a separate `policy_group` with `SystemActorRole` checks. This keeps system actor logic organized and separate from human actor policies.

```elixir
policies do
  policy_group always() do
    policy {SystemActorRole, roles: [:role_a]} do
      # action checks
    end

    policy {SystemActorRole, roles: [:role_b]} do
      # action checks
    end

    policy {SystemActorRole, roles: [:role_c]} do
      # action checks
    end
  end

  # human actor policies here
end
```

## Examples

- `lib/firmowid/ash/timetracker/session.ex`
- Great example of using `SystemActorRole` checks and policy structure for non-human actors: `lib/firmowid/ash/invoicing/sales_invoice.ex`
