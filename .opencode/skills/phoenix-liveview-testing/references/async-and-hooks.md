# Async Assigns and JS Hooks

## Contents
- Async assigns
- JS hooks
- Limitations

## Async assigns

Prefer `render_async/2` over `Process.sleep/1`.

Preferred:

```elixir
{:ok, view, _html} = live(conn, ~p"/metrics")
assert render_async(view, 2000) =~ "User Visits"
```

Loading states can be asserted immediately after mount.

Use sleeps only when there is no better synchronization primitive.

## JS hooks

Use `render_hook/2` or `render_hook/3` to test the LiveView side of a hook:

```elixir
view
|> element("#load-more", "Loading ...")
|> render_hook("load-more")
```

Then assert the updated page state:

```elixir
assert has_element?(view, "[data-role=post]", post.text)
```

## Limitations

LiveView tests do not execute browser JavaScript.

They can validate:
- the hook target exists
- the hook event updates server-rendered state correctly

They cannot validate:
- `IntersectionObserver` behavior
- browser-side hook implementation details
- full end-to-end JS integration

Use browser automation when JS behavior itself is critical.
