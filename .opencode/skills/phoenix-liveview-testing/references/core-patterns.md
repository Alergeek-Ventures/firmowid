# Core Patterns

## Contents
- Setup
- Rendering
- Scoped assertions
- Interactions
- Preferred defaults
- Avoid by default
- Debugging

## Setup

Most LiveView tests use:

```elixir
use MyAppWeb.ConnCase
import Phoenix.LiveViewTest
```

## Rendering

Use connected rendering by default:

```elixir
{:ok, view, html} = live(conn, ~p"/greet")
assert html =~ "Welcome"
```

Only test disconnected HTTP rendering when it is part of the behavior:

```elixir
conn = get(conn, ~p"/greet")
assert html_response(conn, 200) =~ "Welcome to stateless HTTP"
```

## Scoped assertions

Prefer:

```elixir
assert has_element?(view, "#count", "1")
```

Over:

```elixir
assert html =~ "1"
```

Broad HTML assertions can pass for the wrong reason.

Use `element/3` when naming the target improves readability:

```elixir
avatar = element(view, ~s(img[src*="#{avatar_url}"]))
assert has_element?(avatar)
```

## Interactions

Preferred pattern:

```elixir
{:ok, view, _html} = live(conn, ~p"/counter")

view
|> element("#increment")
|> render_click()

assert has_element?(view, "#count", "1")
```

Avoid direct event dispatch unless intentionally testing server-side event handling apart from markup:

```elixir
render_click(view, "increase")
```

## Preferred defaults

- `live/2` for connected LiveView tests
- `element/3` + `render_click/1` for clicks
- `form/3` + `render_submit/1` for submits
- `form/3` + `render_change/1` for validation changes
- `has_element?/3` for scoped assertions
- `follow_redirect/3` when the destination page matters
- `render_async/2` instead of `Process.sleep/1`

## Avoid by default

- `render_click(view, "event")`
- `render_submit(view, "event", params)`
- `render_change(view, "event", params)`

These bypass HTML and can produce false positives unless lower-level event testing is intentional.

## Debugging

Use:

```elixir
open_browser(view)
```

Use temporarily to inspect rendered state.
