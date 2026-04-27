---
name: phoenix-liveview-testing
description: Write and review Phoenix LiveView tests using Phoenix.LiveViewTest. Use for rendering, user interactions, forms, components, navigation, uploads, async assigns, hooks, and resilient selector/assertion strategy.
---

# Testing LiveView

Use this skill when working on Phoenix LiveView tests.

## Core rules

- Test behavior from the user's perspective.
- Prefer exercising rendered HTML over sending events directly.
- Prefer scoped assertions over broad HTML string matching.
- Prefer stable selectors: unique IDs and semantic data attributes.
- Avoid over-testing implementation details unless they are product requirements.

## Use this skill for

- Phoenix LiveView tests built with `Phoenix.LiveViewTest`
- Writing new tests for LiveViews, forms, navigation, uploads, hooks, and async assigns
- Reviewing existing tests for false positives, brittle selectors, or implementation coupling

## Do not use this skill for

- Full browser end-to-end testing where JavaScript behavior itself must be validated
- Plain controller tests that do not involve LiveView
- General ExUnit style guidance unrelated to LiveView behavior

## Default workflow

Copy this checklist and update it while working:

```text
LiveView Test Progress:
- [ ] Mount the LiveView or component appropriately
- [ ] Exercise behavior through element/form helpers
- [ ] Assert visible behavior with scoped selectors
- [ ] Check for false-positive risks from bypassing HTML
- [ ] Verify selectors are resilient to harmless refactors
```

## Standard interaction pattern

Use this default pattern for most interactive tests:

```elixir
{:ok, view, _html} = live(conn, ~p"/path")

view
|> element_or_form_helper(...)
|> render_action()

assert has_element?(view, "selector", "expected text")
```

## Choose the right guide

- Rendering and interaction basics → [references/core-patterns.md](references/core-patterns.md)
- Forms and validation → [references/forms.md](references/forms.md)
- Function components and LiveComponents → [references/components.md](references/components.md)
- Redirects and patch navigation → [references/navigation.md](references/navigation.md)
- Upload previews, direct-to-server, direct-to-cloud → [references/uploads.md](references/uploads.md)
- JS hooks and async assigns → [references/async-and-hooks.md](references/async-and-hooks.md)
- CSS selector strategy → [references/selectors.md](references/selectors.md)

## Firmowid methodology extension

Use this section for Firmowid or similar repos that prioritize production-close,
critical-path tests over broad coverage.

### Purpose

- This methodology defines Firmowid-style testing for high-confidence,
  low-interference, colocated tests.
- It supplements the generic LiveView guidance above with repo-specific rules.

### Primary goal

- Prefer a small number of high-confidence tests over broad coverage.
- Tests should protect critical user and business paths, not document every
  implementation detail.
- Do not overtest; stale or redundant tests are worse than missing low-value
  coverage.

### Colocation

- Tests live under `lib/`, colocated with the code they exercise.
- Shared support lives under `lib/test/`.
- Do not create a separate `/test` tree for normal test files.

### What we mainly test

- Prefer tests of user interactions first.
- Users' experience is what matters most.
- Prefer two main kinds of tests:
  1. critical-path LiveView/HTTP flow tests
  2. focused domain logic tests where UI is not the right surface
- Avoid maintaining a separate boundary-test layer by default.
- If user-facing interaction tests fail, investigate downward from there.

### Production-close infrastructure

- Keep DB real in tests.
- Keep S3/blob storage real in tests.
- Use the normal application/runtime wiring where practical.

### External boundary rule

- Mock external HTTP systems, not internal app code.
- Use `Req.Test` for external API calls during higher-level tests.
- Do not mock Ash resources, LiveViews, DB, or S3.

### Data setup

- Prefer `Ash.Seed` for test setup.
- `Ash.Seed` is the default unless the action itself is what is being tested.
- Avoid action-heavy fixture setup when it introduces auth, side effects, or
  irrelevant complexity.

### LiveView interaction style

- Exercise LiveViews through real routes and rendered markup.
- Prefer `live/2`, `element/3`, `form/3`, `render_click`, `render_submit`,
  `render_change`.
- Search, interact, and assert by what the user actually sees and expects.
- Prefer visible text, labels, roles, stable IDs, and clear user-facing
  structure.
- Avoid hidden implementation hooks when possible:
  - no hidden attributes
  - no `data-*` selectors unless there is no better user-facing handle
- Avoid direct event dispatch unless intentionally testing lower-level behavior.

### Confidence over duplication

- Each test must justify its existence with a distinct confidence gain.
- Merge overlapping assertions into the most representative critical-path test.
- It is fine for a test to follow a slightly longer realistic path if that path
  gives better confidence.
- Prefer intermediate assertions along the way so failures happen earlier and
  iteration is faster.
- Remove or rewrite stale generated scaffolding when it no longer matches
  current routes, APIs, or UX.

### Shared helpers and DRY

- Keep shared helpers small and boring.
- Use `lib/test/data_case.ex`, `lib/test/conn_case.ex`, and focused fixtures.
- Promote helpers only when they are truly shared.
- Prefer feature-local helpers over giant global factories.
- Avoid god fixtures and over-abstracted setup.

### Async and interference

- Use `async: true` when the test does not rely on shared mutable state.
- Use `async: false` only when required.
- `async: false` tests should be uncommon.
- Use `async: false` for tests that mutate app env, shared caches, singleton
  processes, or other global state.
- Restore global state on exit.

### Determinism over sleeps

- Avoid `Process.sleep/1` by default.
- Prefer deterministic assertions first:
  - redirects
  - rendered state
  - async helpers
  - DB assertions
  - job assertions
- Only use `Process.sleep/1` as a last resort, keep it isolated, and explain
  why it is unavoidable.

### Validation

- Run focused tests while iterating.
- Before finishing, run `mix check`.
- Do not assume `mix check` fully validates test-file quality or stale test
  references.
- `.exs` test files are not protected by the same strict compile pass as normal
  app code.
- A renamed module or function in a test may survive as a warning or only
  surface when that specific test path executes.
- Review test files themselves for realism, overlap, brittleness, and stale
  assumptions.
- Manual testing still matters for important UI flows.

### Example philosophy

- Prefer keeping:
  - registration critical path
  - register + create organization
  - register + join organization
- Merge related downstream assertions into the most representative flow when
  possible.
- Remove stale generated tests when they no longer reflect the real app.
