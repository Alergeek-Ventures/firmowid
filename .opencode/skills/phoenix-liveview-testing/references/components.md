# Components

## Contents
- Function components
- LiveComponents
- Test-value heuristics

## Function components

Use either:
- `render_component/2`
- `~H` with `rendered_to_string/1`

Preferred for more complex component composition:

```elixir
assigns = %{}

html =
  rendered_to_string(~H"""
  <.badge type="human" />
  """)

assert html =~ "human"
```

Test:
- consumer-visible behavior
- conditional rendering
- important output differences

Avoid over-specifying exact HTML structure unless structure is the requirement.

## LiveComponents

### Static content

```elixir
html = render_component(MyComponent, id: "name", field: :name, user: user)
assert html =~ "Frodo"
```

### Interactivity

Test through the parent LiveView:

```elixir
{:ok, view, _html} = live(conn, ~p"/users/#{user}/settings")

view
|> element("#name")
|> render_click()

view
|> form("#name-form", %{name: "Bilbo"})
|> render_submit()

assert has_element?(view, "#name", "Bilbo")
```

## Test-value heuristics

Prefer testing:
- state transitions
- conditional branches
- visible behavior

Be cautious about spending test budget on trivial markup with little failure risk.
