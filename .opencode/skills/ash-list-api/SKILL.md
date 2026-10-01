---
name: ash-list-api
description: Use when adding or changing Ash resource list actions, filters, or list callsites.
---

# Ash List API

- Provide one reusable list action per resource with rich, composable optional filters; do not add workflow-specific lists.
- Extend generic filter arguments for new caller needs; keep reusable query mechanics in the resource and business-specific filter combinations at the call site.
- Use resource/domain list code interfaces; never call `Ash.read` or `Ash.read!` directly, including after building a query.
- Keep resource authorization independent of supplied filters.
