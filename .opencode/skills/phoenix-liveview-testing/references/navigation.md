# Navigation

## Contents
- Redirects
- Live redirects
- Patches
- Behavior vs implementation

## Redirects to non-LiveView or another live session

Use:

```elixir
view
|> element("#logo")
|> render_click()

{path, _flash} = assert_redirect(view)
assert path == ~p"/"
```

Use `follow_redirect/3` when the next page matters:

```elixir
{:ok, conn} =
  view
  |> element("#logo")
  |> render_click()
  |> follow_redirect(conn, ~p"/")
```

## Redirects inside the same live_session

Same pattern:

```elixir
view
|> element("[data-role=page-link]", "Team")
|> render_click()

{path, _flash} = assert_redirect(view)
assert path == ~p"/team"
```

Or follow it:

```elixir
{:ok, team_view, team_html} =
  view
  |> element("[data-role=page-link]", "Team")
  |> render_click()
  |> follow_redirect(conn, ~p"/team")
```

## Patches

If URL change itself matters:

```elixir
assert_patch(view, ~p"/directory/#{member.id}")
```

If user-visible behavior matters more, prefer:

```elixir
view
|> element("[data-role=member]", "Aragorn")
|> render_click()

assert has_element?(view, "#active-member", "Aragorn")
```

## Behavior vs implementation

Prefer behavior-first tests.
Use URL assertions only when deep linking, sharing, or browser state is part of the requirement.
