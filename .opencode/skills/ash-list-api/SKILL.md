---
name: ash-list-api
description: Use when adding or changing Ash resource read/list actions, filters, or list callsites.
---

# Ash List API

- Keep the primary `:read` basic (`defaults [:read]`): no arguments, filters, or preparations. It is the stable default for framework reads, relationship loading, and authorization; it still enforces policies and multitenancy.
- Put application listing behavior in a separate, non-primary `read :list` action. Expose it through resource/domain list code interfaces; keep single-record interfaces and framework reads on the basic `:read` or an explicit get action.
- Provide one reusable list action per resource with rich, composable optional filters; do not add workflow-specific lists.
- Extend generic filter arguments for new caller needs; keep reusable query mechanics in the resource and business-specific filter combinations at the call site.
- Use resource/domain list code interfaces; never call `Ash.read` or `Ash.read!` directly, including after building a query.
- Keep resource authorization independent of supplied filters.
- When splitting `:read` and `:list`, migrate all list callsites and named-action policies/bypasses together. Preserve actor/tenant scope, deny rules, and explicitly privileged global/job read actions; do not broaden permissions to all read actions just to make the migration pass.
- Keep the primary-read verifier enabled; do not use `primary_read_warning?: false` to accommodate application list filters. Verify implicit framework/relationship reads as well as filtered lists and cross-user/cross-tenant isolation.
