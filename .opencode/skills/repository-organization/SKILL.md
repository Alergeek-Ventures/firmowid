---
name: repository-organization
description: Use when placing new code, organizing modules, extracting shared components, or reviewing boundaries between Firmowid, FirmowidWeb, FirmowidMcp and FirmowidUI.
---

# Repository Organization

## Resource first

- Put behavior that Ash supports in the owning resource from the start: actions, arguments and types, validations, changes, preparations, calculations, aggregates, relationships and policies. Use the appropriate Ash mechanism rather than implementing it in a caller or a parallel service layer.
- This applies even with a single caller. Do not wait for reuse before moving domain behavior into a resource. Web views, widgets and tools consume resource/domain action interfaces.
- Keep actions independent of presentation: widget modules, layouts and UI definitions belong to the interface, not the resource.

## Presentation starts at the call site

- Start UI composition, display state and interaction wiring at the actual call site, inside the owning feature. Reuse existing components and mechanisms first; domain validation and business rules still belong in Ash.
- A second real UI consumer is the signal to consider extracting the common part. Share only what is actually shared, without anticipating future widgets or consumers.
- Sharing is reversible: a component used only by web can return to web. This is a possible retrospective simplification, not mandatory churn whenever usage changes.
- Keep feature slices shallow; add layers for concrete responsibilities.

## Ownership and dependency direction

The agreed target boundaries are:

| Namespace / directory | Owns |
| --- | --- |
| `Firmowid` / `lib/firmowid` | Domain resources, actions, argument and result types, business rules and policies. |
| `FirmowidWeb` / `lib/firmowid_web` | Browser application presentation and interactions. |
| `FirmowidMcp` / `lib/firmowid_mcp` | MCP exposure, protocol infrastructure and feature-owned widgets. |
| `FirmowidUI` / `lib/firmowid_ui` | UI components, styles and JS hooks actually shared by the interfaces. |

- Web and MCP consume the domain and shared UI. The domain does not depend on either presentation; shared UI does not depend on either interface's router, layout or authentication flow.
- Shared UI may use Phoenix Components and LiveView. Independence from an interface does not require independence from Phoenix.
- Keep interface-specific navigation and widget shells with their owners. Supply interface-specific destinations and behavior to shared components at the call site.
- These boundaries do not require separate OTP applications or servers.
- Existing code may predate these boundaries. Migrate within the agreed task; do not move the entire design system or clean up unrelated single-consumer components opportunistically.

## Module layout

- Directory path equals module namespace: `FirmowidWeb.X.Y.Z` lives in `lib/firmowid_web/x/y/z.ex`.
- Prefer a feature-first layout. In presentation features, use the established `views/`, `components/`, `controllers/` and `utilities/` subfolders when needed; do not create empty scaffolding.
- Keep dependencies directional: nested/child features may depend on shared parent feature modules, but avoid cross-sibling dependencies.
- Keep these conventions enforceable through Credo and code review. Finish code refactors with `mix check` as required by the repository verification workflow.

## MCP integration

- Derive exposed operation contracts from Ash actions, types and policies through existing AshAi mechanisms. Do not duplicate them or create a resource merely because a tool needs a name.
- Associate tools with optional widgets in the MCP presentation layer. Keep protocol/session infrastructure there and business authorization in Ash.
