# Selector Strategy

## Contents
- Preferred selectors
- What should break tests
- What should not break tests
- Patterns to prefer

## Preferred selectors

- Use unique IDs for unique elements
- Use semantic data attributes for repeated elements or sub-elements
- Prefer descendant selectors over exact tree-shape selectors

Examples:

```elixir
assert has_element?(view, "#post-37 [data-role=like-count]", "3")
assert has_element?(view, "[data-role=todo]", "Buy lembas")
```

## What should break tests

- An important element is removed
- A control is no longer wired correctly
- User-visible behavior disappears

## What should not break tests

- CSS class refactors
- Layout changes such as flex vs grid
- harmless wrapper changes
- purely presentational renaming

## Patterns to prefer

Prefer:
- `#post-37 [data-role=like-count]`

Avoid when possible:
- `.post-action > .count`
- `div > span > .count`
- selectors based only on styling classes

Choose selectors that express meaning rather than presentation.
