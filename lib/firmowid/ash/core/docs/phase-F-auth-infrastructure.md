# Phase F — Auth infrastructure rewrite

## Goal

Replace the entire phx.gen.auth session management (`UserAuth`, `Session`
controller, `Google` controller) with `AshAuthentication` plugs, controller, and
LiveView hooks. Drop `Bodyguard`.

## Decisions

- `AshAuthentication.Plug` handles sessions via JWTs + subject strings, not
  opaque DB tokens.
- `store_in_session(conn, user)` replaces `generate_user_session_token` +
  `put_session(:user_token)`.
- `load_from_session` plug replaces `fetch_current_user`.
- `load_from_bearer` plug replaces `fetch_api_user`.
- `clear_session(conn, :firmowid)` replaces `log_out_user`.
- `ash_authentication_live_session` replaces manual `on_mount` user-loading.
  Custom hooks handle org checks, `Repo.put_org_id`, `%Scope{}`, and avatar.
- `auth_routes/3` (not deprecated `auth_routes_for`) generates routes for
  password + Google strategies.
- `sign_in_with_remember_me` plug goes BEFORE `load_from_session` in browser
  pipeline.
- `Bodyguard.permit!` replaced by `user.role == :admin` guards.
- Google OAuth: `upsert? true` on `:register_with_google` handles account
  linking. Custom linking controller deleted entirely.
  - TODO: Add email-confirmation-based account linking flow later.
  - TODO: Handle linking a different-email Google account with a different-email
    password account.
- `live_socket_id` for broadcast disconnect on logout — verify how
  ash_authentication handles this. If not built-in, replicate in AuthController
  `sign_out/2`.

## Steps

### F1 — Create AuthController

File: `lib/firmowid_web/auth/controllers/auth_controller.ex`

```elixir
defmodule FirmowidWeb.Auth.Controllers.AuthController do
  use FirmowidWeb, :controller
  use AshAuthentication.Phoenix.Controller

  alias Firmowid.Analytics

  def success(conn, _activity, user, _token) do
    return_to = get_session(conn, :return_to) || ~p"/czasosledz"

    conn
    |> delete_session(:return_to)
    |> store_in_session(user)
    |> AshAuthentication.Strategy.RememberMe.Plug.Helpers.maybe_put_remember_me_cookies(
         conn.private[:ash_authentication]
       )
    |> assign(:current_user, user)
    |> then(fn conn ->
      Analytics.identify(user)
      Analytics.track_event("user_log_in", user, %{})
      conn
    end)
    |> redirect(to: return_to)
  end

  def failure(conn, _activity, _reason) do
    conn
    |> put_flash(:error, "Niewłaściwy email lub hasło.")
    |> redirect(to: ~p"/zaloguj")
  end

  def sign_out(conn, _params) do
    # Broadcast disconnect for LiveView sessions
    if live_socket_id = get_session(conn, :live_socket_id) do
      FirmowidWeb.Core.Endpoint.broadcast(live_socket_id, "disconnect", %{})
    end

    conn
    |> clear_session(:firmowid)
    |> AshAuthentication.Strategy.RememberMe.Plug.Helpers.delete_all_remember_me_cookies(:firmowid)
    |> LiveToast.put_toast(:notice, "Wylogowano.")
    |> redirect(to: ~p"/")
  end
end
```

**Note:** Verify the exact `clear_session/2` import — comes from
`use AshAuthentication.Phoenix.Controller`.

### F2 — Router changes

File: `lib/firmowid_web/core/router.ex`

**Add:**

```elixir
use AshAuthentication.Phoenix.Router
import AshAuthentication.Plug.Helpers
```

**Browser pipeline — replace `plug :fetch_current_user` with:**

```elixir
plug :sign_in_with_remember_me
plug :load_from_session
```

Order is critical: remember_me re-hydrates the session before load_from_session
reads it.

**API pipeline — replace `plug :fetch_api_user` with:**

```elixir
plug :load_from_bearer
```

**Add auth routes (replace manual `/auth/google` scope):**

```elixir
scope "/", FirmowidWeb do
  pipe_through :browser
  auth_routes Auth.Controllers.AuthController, Firmowid.Ash.Core.User, path: "/auth"
  sign_out_route Auth.Controllers.AuthController
end
```

This generates:
- `* /auth/user/password/register`
- `* /auth/user/password/sign_in`
- `* /auth/user/password/reset_request`
- `* /auth/user/password/reset`
- `* /auth/user/google/request`
- `* /auth/user/google/callback`
- `GET /sign-out`

**Replace all `live_session` blocks with `ash_authentication_live_session`:**

```elixir
# Authenticated with org (main app)
ash_authentication_live_session :with_org,
  on_mount: [
    {RequireOrganization, :default},
    {CurrentPath, :save_request_uri},
    Timezone
  ] do
  # ... all routes currently in :admin and :require_authenticated_user_with_organization
end

# Authenticated without org (onboarding)
ash_authentication_live_session :without_org,
  on_mount: [{RequireNoOrganization, :default}] do
  live "/organization/", Organization.Views.Index, :index
end

# Guest only (login, register, reset password)
ash_authentication_live_session :guest,
  on_mount: [
    {RedirectAuthenticated, :default},
    {CurrentPath, :save_request_uri},
    Timezone
  ] do
  live "/zaloguj", Auth.Views.Login, :new
  live "/zarejestruj", Auth.Views.Registration, :new
  live "/resetuj-haslo", Auth.Views.ForgotPassword, :new
  live "/resetuj-haslo/:token", Auth.Views.ResetPassword, :edit
end

# Public (landing, confirmation, shared invoices)
ash_authentication_live_session :public,
  on_mount: [
    {CurrentPath, :save_request_uri},
    Timezone
  ] do
  live "/", Landing.Views.Index
  live "/potwierdz/:token", Auth.Views.Confirmation, :edit
  live "/potwierdz", Auth.Views.ConfirmationInstructions, :new
  # ...
end
```

**Note:** The `:admin` and `:require_authenticated_user_with_organization`
live_sessions currently have identical `on_mount` hooks — merge them into one
`:with_org` session, or keep two if route-level distinction matters for other
reasons.

**Verify** that `ash_authentication_live_session` passes through options like
`:root_layout` and non-auth `on_mount` hooks. From research: `:on_mount` hooks
are appended AFTER the auth hook, so `current_user` is available in all custom
hooks.

### F3 — Create on_mount hooks

**File: `lib/firmowid_web/infrastructure/hooks/require_organization.ex`**

```elixir
defmodule FirmowidWeb.Infrastructure.Hooks.RequireOrganization do
  @moduledoc """
  LiveView on_mount hook. Requires authenticated user with an organization.

  After ash_authentication_live_session populates `current_user`, this hook:
  1. Redirects to /zaloguj if no user
  2. Redirects to /organization if user has no org
  3. Sets Repo.put_org_id for Ecto multitenancy bridge
  4. Loads avatar on user and organization via Ash.load!
  5. Assigns current_user, current_org, ash_scope
  """

  import Phoenix.Component
  import Phoenix.LiveView

  alias Firmowid.Ash.Scope

  def on_mount(:default, _params, _session, socket) do
    case socket.assigns[:current_user] do
      nil ->
        {:halt,
         socket
         |> LiveToast.put_toast(:notice, "Musisz się zalogować.")
         |> redirect(to: ~p"/zaloguj")}

      %{organization_id: nil} ->
        {:halt,
         socket
         |> LiveToast.put_toast(:notice, "Aby przejść dalej, przypisz sobie organizację.")
         |> redirect(to: ~p"/organization")}

      user ->
        Firmowid.Repo.put_org_id(user.organization_id)

        user =
          Ash.load!(user, [:organization, avatar_blob: [:url]],
            tenant: user.organization_id,
            authorize?: false,
            actor: %{}
          )

        org =
          Ash.load!(user.organization, [avatar_blob: [:url]],
            tenant: user.organization_id,
            authorize?: false,
            actor: %{}
          )

        scope = %Scope{current_user: user, current_tenant: user.organization_id}

        {:cont,
         socket
         |> assign(:current_user, user)
         |> assign(:current_org, org)
         |> assign(:ash_scope, scope)}
    end
  end
end
```

**File: `lib/firmowid_web/infrastructure/hooks/require_no_organization.ex`**

Checks user present + `organization_id` is nil. Redirects to `/` if user has
org, to `/zaloguj` if no user.

**File: `lib/firmowid_web/infrastructure/hooks/redirect_authenticated.ex`**

If user present → redirect to `/organization` (no org) or `/czasosledz` (has
org). If no user → `{:cont, socket}`.

### F4 — Simplify `user_auth.ex`

File: `lib/firmowid_web/infrastructure/user_auth.ex`

**Delete entirely:**
- `log_in_user/3`
- `log_out_user/1`
- `fetch_current_user/2`
- `fetch_api_user/2`
- `ensure_user_token/1`
- `put_token_in_session/2`
- `maybe_write_remember_me_cookie/3`
- `renew_session/1`
- All `on_mount` functions (`mount_current_user`, `ensure_authenticated_*`,
  `redirect_if_user_is_authenticated`)
- `mount_current_user/2` (private)
- `@remember_me_cookie`, `@max_age`, `@remember_me_options` constants

**Keep and simplify** (these plugs now read `conn.assigns.current_user` already
set by `load_from_session`):
- `require_authenticated_user_with_organization/2` — remove the
  `Accounts.get_user_with_avatar` call, replace with
  `Ash.load!(user, [:organization, avatar_blob: [:url]], ...)`. Keep
  `Repo.put_org_id`, `%Scope{}`, and assigns.
- `require_authenticated_user_with_organization_api/2` — same pattern
- `require_authenticated_user_without_organization/2` — simplify
- `require_superuser/2` — unchanged
- `redirect_if_user_is_authenticated/2` — keep, already reads from assigns
- `maybe_store_return_to/1` — keep
- `signed_in_path/1` — keep

**Remove `import FirmowidWeb.Infrastructure.UserAuth` from router** for the
deleted functions. The remaining plug functions stay importable.

### F5 — Delete legacy controllers

**Delete:** `lib/firmowid_web/auth/controllers/google.ex`
- Entirely replaced by `auth_routes` Google strategy. The custom linking flow
  (email_already_exists, link-via-token) is no longer needed — `upsert? true`
  handles it.
- TODO: email-confirmation-based account linking for security.
- TODO: linking different-email Google account with different-email password
  account.

**Delete:** `lib/firmowid_web/auth/controllers/session.ex`
- Login POST → handled by `auth_routes` password sign-in
- Logout DELETE → handled by `sign_out_route`
- Password-updated redirect → handle in AuthController `success/4` by checking
  activity tuple

**Rewrite:** `lib/firmowid_web/auth/controllers/session_api.ex`
- Replace `Accounts.generate_user_session_token` → `AshAuthentication.Jwt.token_for_user(user)`
- Replace `Accounts.get_user_by_email_and_password` → use ash_auth password
  strategy action

### F6 — Update `conn_case.ex`

File: `test/conn_case.ex`

```elixir
def log_in_user(conn, user) do
  conn
  |> Phoenix.ConnTest.init_test_session(%{})
  |> AshAuthentication.Plug.Helpers.store_in_session(user)
end

def log_in_api_user(conn, user) do
  {:ok, token, _claims} = AshAuthentication.Jwt.token_for_user(user)
  Plug.Conn.put_req_header(conn, "authorization", "Bearer #{token}")
end
```

### F7 — Verify

```bash
mix compile --warnings-as-errors
```

Test login/logout manually:
- Password login → redirects to `/czasosledz`
- Google OAuth login → redirects correctly
- Logout → clears session + remember-me cookie
- Remember-me → persists across browser restart
- LiveView sessions disconnect on logout
- API bearer token auth works

## Files created/modified

| File | Action |
|------|--------|
| `lib/firmowid_web/auth/controllers/auth_controller.ex` | Create |
| `lib/firmowid_web/infrastructure/hooks/require_organization.ex` | Create |
| `lib/firmowid_web/infrastructure/hooks/require_no_organization.ex` | Create |
| `lib/firmowid_web/infrastructure/hooks/redirect_authenticated.ex` | Create |
| `lib/firmowid_web/core/router.ex` | Rewrite pipelines + routes |
| `lib/firmowid_web/infrastructure/user_auth.ex` | Gut and simplify |
| `lib/firmowid_web/auth/controllers/google.ex` | Delete |
| `lib/firmowid_web/auth/controllers/session.ex` | Delete |
| `lib/firmowid_web/auth/controllers/session_api.ex` | Rewrite |
| `test/conn_case.ex` | Rewrite helpers |

## Dependencies

- Phase E must be complete (code interfaces + remember_me strategy exist).
