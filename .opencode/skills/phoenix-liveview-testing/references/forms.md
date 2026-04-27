# Forms

## Contents
- Form submission
- Form validation changes
- False-positive traps

## Form submission

Preferred pattern:

```elixir
view
|> form("#add-todo", %{todo: %{body: "Buy lembas"}})
|> render_submit()

assert has_element?(view, "[data-role=todo]", "Buy lembas")
```

Prefer this over direct event submission because `form/3` validates:
- the form exists
- the selector is correct
- the form is wired for submission

Avoid by default:

```elixir
render_submit(view, "create", %{todo: %{body: "Buy lembas"}})
```

## Form validation changes

Preferred pattern:

```elixir
html =
  view
  |> form("#subscribe", %{subscription: %{email: "invalid"}})
  |> render_change()

assert html =~ "has invalid format"
```

Use `has_element?/3` when multiple similar validation messages exist or precise location matters.

Avoid by default:

```elixir
render_change(view, "validate", %{subscription: %{email: "invalid"}})
```

That bypasses HTML and may miss a broken or missing `phx-change`.

## False-positive traps

Do not rely on broad returned HTML when the same text can appear elsewhere, such as:
- prefilled form values
- unrelated headings
- duplicated content

Prefer a scoped assertion on the actual rendered success or error area.
