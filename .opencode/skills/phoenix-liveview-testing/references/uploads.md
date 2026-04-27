# Uploads

## Contents
- Preview testing
- Cancel testing
- Direct-to-server uploads
- Direct-to-cloud uploads
- Cleanup

## Preview testing

Use:

```elixir
view
|> file_input("#upload-form", :photos, [
  %{name: "image.png", content: File.read!("test/support/images/image.png"), type: "image/png"}
])
|> render_upload("image.png")

assert has_element?(view, "[data-role='image-preview']")
```

## Cancel testing

```elixir
view
|> element("[data-role='cancel-upload']")
|> render_click()

refute has_element?(view, "[data-role='image-preview']")
```

## Direct-to-server uploads

Preferred flow:
1. upload file
2. submit form
3. follow redirect
4. assert saved result

```elixir
upload =
  file_input(view, "#upload-form", :photos, [
    %{name: "moria-door.png", content: File.read!("test/support/images/moria-door.png"), type: "image/png"}
  ])

render_upload(upload, "moria-door.png")

{:ok, show_view, _html} =
  view
  |> form("#upload-form", %{album: %{name: "Moria adventures"}})
  |> render_submit()
  |> follow_redirect(conn)

assert has_element?(show_view, "h2", "Moria adventures")
assert has_element?(show_view, "[data-role='image']")
```

## Direct-to-cloud uploads

LiveView tests are most useful for:
- upload metadata contract
- saved provider URL shape
- server-side post-upload behavior

Use `preflight_upload/1` to inspect metadata when needed.

Do not assume LiveView tests cover browser-side uploader JavaScript.

## Cleanup

Clean written test files after upload tests.
Prefer a dedicated test uploads directory so cleanup cannot affect development data.
