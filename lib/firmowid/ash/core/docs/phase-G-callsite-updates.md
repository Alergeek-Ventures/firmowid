# Phase G — Callsite updates

## Goal

Replace every `Accounts.*` call across the codebase with `Core` code interfaces,
`AshPhoenix.Form`, or `Ash.load!`. Replace `Bodyguard.permit!` with role
checks. This phase covers everything except the Timetracker rewrite (G7 in
separate doc) and test fixtures/tests (G9).

## Decisions

- All forms use `AshPhoenix.Form` (`for_create`, `for_update`, `validate`,
  `submit`) instead of Ecto changesets + `to_form`.
- Avatar loading at callsites: `Ash.load!(entity, [avatar_blob: [:url]], tenant: ..., authorize?: false, actor: %{})`.
- `Bodyguard.permit!` → `user.role == :admin` guard. Raises on failure.
- Password verification before user deletion happens at the callsite (not in the
  Ash action).
- Google account unlink → destroy the `UserIdentity` record.
- `Accounts.Organization` struct references → `Firmowid.Ash.Core.Organization`.
- `Accounts.User` struct references → `Firmowid.Ash.Core.User`.

## Reference: Accounts function → Core equivalent

| Legacy `Accounts` function | New equivalent |
|---|---|
| `register_user(params)` | `Core.register_with_password(params)` (ash_auth action) |
| `get_user_by_email(email)` | `Core.get_user_by_email(email)` or `Ash.read_one!` with filter |
| `get_user_by_email_and_password(email, pw)` | Auth routes handle this; or `AshAuthentication.Strategy` action |
| `get_user!(id)` | `Core.get_user!(id, ...)` |
| `update_user(user, attrs)` | `Core.update_profile(user, attrs)` / `Core.update_role(user, attrs)` |
| `update_user_profile(user, attrs)` | `Core.update_profile(user, attrs)` |
| `update_user_avatar(user, blob_id)` | `Core.update_user_avatar(user, %{avatar_blob_id: blob_id})` |
| `update_user_password(user, pw, params)` | ash_auth password change action via `AshPhoenix.Form` |
| `change_user_email(user, params)` | `AshPhoenix.Form.for_update(user, :request_email_change, ...)` |
| `apply_user_email(user, pw, params)` | ash_auth email change action |
| `update_user_email(user, token)` | ash_auth `:confirm_email_update` action |
| `deliver_user_update_email_instructions(...)` | Handled by ash_auth email change confirmation add-on |
| `change_user_password(user, params)` | `AshPhoenix.Form.for_update(user, :change_password, ...)` |
| `change_user_registration(user, params)` | `AshPhoenix.Form.for_create(User, :register_with_password, ...)` |
| `change_user_delete_account(user)` | Simple `to_form(%{"current_password" => ""})` — just a password field |
| `delete_user(user, password)` | Verify password at callsite, then `Core.destroy_user(user)` |
| `confirm_user(token)` | ash_auth `:confirm_new_user` action |
| `deliver_user_confirmation_instructions(user, url)` | Handled by ash_auth confirmation add-on |
| `deliver_user_reset_password_instructions(user, url)` | Handled by auth_routes reset request |
| `get_user_by_reset_password_token(token)` | Handled by auth_routes reset phase |
| `reset_user_password(user, params)` | Handled by auth_routes reset phase |
| `unlink_google_account(user)` | Destroy user's `UserIdentity` record for Google |
| `get_user_with_avatar(user)` | `Ash.load!(user, [avatar_blob: [:url]], tenant: user.organization_id, authorize?: false, actor: %{})` |
| `get_organization(id)` | `Core.get_organization!(id, ...)` |
| `create_organization(params, user)` | `Core.create_organization(params)` with `owner_id` argument |
| `update_organization(org_id, attrs, user)` | `Core.update_organization(org, attrs)` / `Core.update_basic_info(org, attrs)` |
| `get_organization_with_avatar(org)` | `Ash.load!(org, [avatar_blob: [:url]], tenant: org.id, authorize?: false, actor: %{})` |
| `update_organization_avatar(org, blob_id)` | `Core.update_organization_avatar(org, %{avatar_blob_id: blob_id})` |
| `regenerate_organization_nickname(org_id)` | `Core.regenerate_nickname(org)` |
| `add_email_to_org_allowlist(org_id, email)` | `Core.add_sender_email(org, %{email: email})` |
| `remove_email_from_org_allowlist(org_id, email)` | `Core.remove_sender_email(org, %{email: email})` |
| `list_organization_invites(org_id)` | `Core.list_invites!(tenant: org_id, ...)` |
| `create_organization_invites(org_id, issued_by_id)` | `Core.create_invite!(%{issued_by_id: id}, tenant: org_id, ...)` |
| `get_organization_invites!(id, org_id)` | `Core.get_invite!(id, tenant: org_id, ...)` (need get code interface) |
| `delete_organization_invites(org_id, invite)` | `Core.destroy_invite!(invite, tenant: org_id, ...)` |
| `consume_organization_invite(code, user_id)` | `Core.read_invite_by_code!(%{invite_code: code})` then `Core.consume_invite!(invite, %{user_id: uid})` |
| `generate_user_session_token(user)` | Handled by phase F (AuthController / conn_case) |
| `get_user_by_session_token(token)` | Handled by phase F (load_from_session plug) |
| `delete_user_session_token(token)` | Handled by phase F (clear_session) |

## Steps by file group

### G1 — Auth views (AshPhoenix.Form rewrite)

**`lib/firmowid_web/auth/views/registration.ex`**

Before:
```elixir
changeset = Accounts.change_user_registration(%User{})
# ...
case Accounts.register_user(user_params) do
  {:ok, user} ->
    Accounts.deliver_user_confirmation_instructions(user, &url(~p"/potwierdz/#{&1}"))
```

After:
```elixir
form = AshPhoenix.Form.for_create(User, :register_with_password, domain: Core) |> to_form()
# ...
case AshPhoenix.Form.submit(socket.assigns.form, params: user_params) do
  {:ok, _user} ->
    # Confirmation email is auto-sent by ash_auth confirmation add-on
```

- Remove `alias Firmowid.Accounts.User` — use `Firmowid.Ash.Core.User`
- `validate` event → `AshPhoenix.Form.validate(form, params, target: target)`
- `submit` event → `AshPhoenix.Form.submit(form, params: params)`
- The `_action: "registered"` session trick for Session controller is no longer
  needed — AuthController `success/4` handles post-registration redirect.

**`lib/firmowid_web/auth/views/login.ex`**

Login form POST → goes to `auth_routes` password sign-in endpoint. The LiveView
just renders the form and submits to the auth route. No `Accounts` calls.

Check if the form action URL changes from `~p"/zaloguj"` to the generated auth
route path.

**`lib/firmowid_web/auth/views/confirmation.ex`**

```elixir
# Before:
case Accounts.confirm_user(token) do
# After:
# Use ash_auth confirm action. The confirmation add-on generates a
# :confirm_new_user action. Call it via AshAuthentication.Strategy:
strategy = AshAuthentication.Info.strategy!(User, :confirm_new_user)
case AshAuthentication.Strategy.action(strategy, :confirm, %{"confirm" => token}) do
```

**`lib/firmowid_web/auth/views/confirmation_instructions.ex`**

```elixir
# Before:
if user = Accounts.get_user_by_email(email) do
  Accounts.deliver_user_confirmation_instructions(user, url)
# After:
# Re-request confirmation via ash_auth. The confirmation add-on should
# have a way to re-send. Check ash_auth docs for the exact API.
```

**`lib/firmowid_web/auth/views/forgot_password.ex`**

```elixir
# Before:
if user = Accounts.get_user_by_email(email) do
  Accounts.deliver_user_reset_password_instructions(user, url)
# After:
# Form posts to auth_routes reset_request endpoint, which handles the
# email lookup and delivery. The LiveView just renders the form.
```

**`lib/firmowid_web/auth/views/reset_password.ex`**

```elixir
# Before:
user = Accounts.get_user_by_reset_password_token(token)
changeset = Accounts.change_user_password(user)
case Accounts.reset_user_password(user, params) do
# After:
# Use ash_auth reset route/action. The :password_reset_with_password action
# is generated. Use AshPhoenix.Form or submit to auth_routes reset endpoint.
```

**`lib/firmowid_web/auth/views/settings.ex`**

The security tab in the auth settings view (separate from
`settings/views/index.ex` which is the main settings page):

- `change_user_email` / `apply_user_email` / `deliver_user_update_email_instructions`
  → `AshPhoenix.Form.for_update(user, :request_email_change, domain: Core)`
  The ash_auth email change confirmation add-on handles the delivery.
- `change_user_password` / `update_user_password`
  → `AshPhoenix.Form.for_update(user, :change_password, domain: Core)`
  (Verify action name — ash_auth may generate differently.)
- `update_user_email(user, token)` — ash_auth `:confirm_email_update` action

### G2 — Google OAuth

- Delete `lib/firmowid_web/auth/controllers/google.ex` (done in phase F5)
- Remove route `get "/google", Google, :request` and related from router
- Remove route `get "/google/callback", Google, :callback`
- Remove route `get "/google/link/:token", Google, :link`
- Add TODO comments in AuthController and router about email-confirmation-based
  account linking.

### G3 — Settings view (`lib/firmowid_web/settings/views/index.ex`)

~30 callsites. Group by function:

**Organization updates:**
```elixir
# Before: Accounts.update_organization(org_id, attrs, user)
# After:  Core.update_basic_info(org, attrs, authorize?: false, actor: %{})
#   or    Core.update_correspondence(org, attrs, ...)
```

**Avatar loads (after updates):**
```elixir
# Before: Accounts.get_organization_with_avatar(updated_org)
# After:  Ash.load!(updated_org, [avatar_blob: [:url]], tenant: updated_org.id, authorize?: false, actor: %{})
```

```elixir
# Before: Accounts.get_user_with_avatar(updated)
# After:  Ash.load!(updated, [avatar_blob: [:url]], tenant: updated.organization_id, authorize?: false, actor: %{})
```

**User avatar upload:**
```elixir
# Before: Accounts.update_user_avatar(user, blob_id)
# After:  Core.update_user_avatar(user, %{avatar_blob_id: blob_id}, authorize?: false, actor: %{})
```

**Org avatar upload:**
```elixir
# Before: Accounts.update_organization_avatar(org, blob_id)
# After:  Core.update_organization_avatar(org, %{avatar_blob_id: blob_id}, authorize?: false, actor: %{})
```

**Sender emails:**
```elixir
# Before: Accounts.add_email_to_org_allowlist(org_id, email)
# After:  org = Core.get_organization!(org_id, ...)
#          Core.add_sender_email(org, %{email: email}, authorize?: false, actor: %{})
```

**Nickname:**
```elixir
# Before: Accounts.regenerate_organization_nickname(org_id)
# After:  org = Core.get_organization!(org_id, ...)
#          Core.regenerate_nickname(org, authorize?: false, actor: %{})
```

**Profile updates:**
```elixir
# Before: Accounts.update_user_profile(user, attrs)
# After:  Core.update_profile(user, attrs, authorize?: false, actor: %{})
```

**Delete account:**
```elixir
# Before: Accounts.delete_user(user, password)
# After:
#   Verify password at callsite:
#     case Argon2Provider.valid?(password, user.hashed_password) do
#       true -> Core.destroy_user(user, authorize?: false, actor: %{})
#       false -> {:error, :invalid_password}
#     end
```

**Security forms (email change, password change):**
- Replace `Accounts.change_user_email()` → `AshPhoenix.Form.for_update(user, :request_email_change, ...)`
- Replace `Accounts.change_user_password()` → `AshPhoenix.Form.for_update(user, :change_password, ...)`
- Replace `Accounts.change_user_delete_account(user)` → simple `to_form(%{"current_password" => ""})`
- Replace `Accounts.apply_user_email(user, pw, params)` → `AshPhoenix.Form.submit(form, params: params)` — the ash_auth action handles password verification + email change
- Replace `Accounts.update_user_password(user, pw, params)` → `AshPhoenix.Form.submit(form, params: params)`
- Replace `Accounts.update_user_email(user, token)` → ash_auth `:confirm_email_update` action
- Replace `Accounts.deliver_user_update_email_instructions(...)` → auto-handled by ash_auth confirmation add-on
- Replace `Accounts.unlink_google_account(user)` → destroy user's `UserIdentity` where `strategy == "google"`

**Bodyguard replacements:**
```elixir
# Before: Bodyguard.permit!(Accounts, :update_organization, user, org)
# After:  unless user.role == :admin, do: raise("Unauthorized")
#   or simply: if user.role != :admin, do: raise(Ash.Error.Forbidden, ...)
```

There are 8 `Bodyguard.permit!` calls — all check admin role for org operations.

**Struct alias:**
```elixir
# Before: alias Firmowid.Accounts.Organization
# After:  alias Firmowid.Ash.Core.Organization
```

### G4 — Invites view (`lib/firmowid_web/organization/invites/views/index.ex`)

```elixir
# Before: Bodyguard.permit!(Accounts, :read_organization_invites, current_user)
# After:  unless current_user.role == :admin, do: raise("Unauthorized")

# Before: Accounts.list_organization_invites(organization_id)
# After:  Core.list_invites!(tenant: organization_id, authorize?: false, actor: %{})

# Before: Accounts.create_organization_invites(org_id, user_id)
# After:  Core.create_invite!(%{issued_by_id: user_id}, tenant: org_id, authorize?: false, actor: %{})

# Before: Accounts.get_organization_invites!(id, org_id)
# After:  Core.get_invite!(id, tenant: org_id, ...) — add get code interface if missing

# Before: Accounts.delete_organization_invites(org_id, invite)
# After:  Core.destroy_invite!(invite, tenant: org_id, authorize?: false, actor: %{})
```

### G5 — Organization onboarding view

File: `lib/firmowid_web/organization/views/index.ex`

```elixir
# Before: Accounts.create_organization(params, user)
# After:  Core.create_organization!(Map.put(params, "owner_id", user.id), authorize?: false, actor: %{})

# Before: Accounts.consume_organization_invite(invite_code, user.id)
# After:
#   [invite] = Core.read_invite_by_code!(%{invite_code: code}, authorize?: false, actor: %{})
#   Core.consume_invite!(invite, %{user_id: user.id}, tenant: invite.organization_id, authorize?: false, actor: %{})
#   {:ok, invite.organization_id}
```

### G6 — Workers and domain code

**`lib/firmowid/ash/invoicing/invoicing.ex` (lines 449-450):**
```elixir
# Before:
{:ok, ecto_org} = Accounts.get_organization(organization_id)
organization = Accounts.get_organization_with_avatar(ecto_org)
# After:
organization =
  Core.get_organization!(organization_id, authorize?: false, actor: %{})
  |> Ash.load!([avatar_blob: [:url]], tenant: organization_id, authorize?: false, actor: %{})
```

**`lib/firmowid/ash/invoicing/workers/inbound_email_worker.ex` (line 65):**
```elixir
# Before: {:ok, organization} = Accounts.get_organization(org_id)
# After:  organization = Core.get_organization!(org_id, authorize?: false, actor: %{})
```

**`lib/firmowid/ash/invoicing/workers/matching_worker.ex` (line 11):**
```elixir
# Before: alias Firmowid.Accounts.Organization
# After:  alias Firmowid.Ash.Core.Organization
# Note: This file queries all org IDs for cron fan-out via raw Ecto —
# that's a justified exception (infrastructure, not domain logic).
```

**`lib/firmowid/ash/ksef/ksef.ex` (line 87):**
```elixir
# Before: {:ok, organization} = Accounts.get_organization(org_id)
# After:  organization = Core.get_organization!(org_id, authorize?: false, actor: %{})
```

**`lib/firmowid/ash/ksef/workers/session_worker.ex` (line 58):**
```elixir
# Before: {:ok, organization} = Accounts.get_organization(org_id)
# After:  organization = Core.get_organization!(org_id, authorize?: false, actor: %{})
```

### G7 — Other web views

**`lib/firmowid_web/invoicing/cost_invoices/controllers/inbound.ex`:**
```elixir
# Before: alias Firmowid.Accounts.Organization
#          {:ok, _org} <- Accounts.get_organization(org_id)
# After:  alias Firmowid.Ash.Core.Organization
#          _org = Core.get_organization!(org_id, authorize?: false, actor: %{})
```

**`lib/firmowid_web/invoicing/cost_invoices/components/assistant.ex` (line 75):**
**`lib/firmowid_web/invoicing/sales_invoices/components/assistant.ex` (line 75):**
```elixir
# Before: assign(:current_user, Accounts.get_user_with_avatar(current_user))
# After:  assign(:current_user,
#            Ash.load!(current_user, [avatar_blob: [:url]],
#              tenant: current_user.organization_id, authorize?: false, actor: %{}))
```

**`lib/firmowid_web/invoicing/sales_invoices/views/creator.ex` (line 401):**
**`lib/firmowid_web/invoicing/sales_invoices/views/edit.ex` (line 69):**
```elixir
# Before: {:ok, organization} = Accounts.get_organization(org_id)
# After:  organization = Core.get_organization!(org_id, authorize?: false, actor: %{})
```

**`lib/firmowid_web/hours_record/controllers/record.ex` (lines 21, 108):**
```elixir
# Before: Accounts.get_organization_with_avatar()
# After:  |> Ash.load!([avatar_blob: [:url]], tenant: org.id, authorize?: false, actor: %{})
```

**`lib/firmowid_web/management/views/project_form.ex` (lines 131, 147, 173):**
```elixir
# Before: Accounts.get_user_with_avatar(user)
# After:  Ash.load!(user, [avatar_blob: [:url]],
#            tenant: user.organization_id, authorize?: false, actor: %{})

# Before: Firmowid.Accounts.User (line 173 — used for Ecto query source)
# After:  Firmowid.Ash.Core.User
# Note: This usage is part of the timetracker rewrite (G7 in separate doc).
#        For now, just swap the alias.
```

### G8 — Seeds

**`priv/repo/seeds/bytecraft.exs`:**

Replace all `Accounts.*` calls:
```elixir
# Register users:
#   Before: Accounts.register_user(%{email: ..., password: ...})
#   After:  Core.register_with_password(%{email: ..., password: ...})
#     or    Ash.Seed.seed!(User, %{email: ..., hashed_password: hash})

# Update users:
#   Before: Accounts.update_user(user, %{role: :admin, name: "..."})
#   After:  Core.update_role(user, %{role: :admin}, authorize?: false, actor: %{})
#           Core.update_profile(user, %{name: "..."}, authorize?: false, actor: %{})

# Create organization:
#   Before: Accounts.create_organization(%{"nip" => ..., "name" => ..., "owner_id" => id}, user)
#   After:  Core.create_organization!(%{nip: ..., name: ..., owner_id: id}, authorize?: false, actor: %{})

# Invites:
#   Before: Accounts.create_organization_invites(org_id, issuer_id)
#   After:  Core.create_invite!(%{issued_by_id: issuer_id}, tenant: org_id, authorize?: false, actor: %{})

#   Before: Accounts.consume_organization_invite(invite.invite_code, user.id)
#   After:  Core.consume_invite!(invite, %{user_id: user.id}, tenant: org_id, authorize?: false, actor: %{})

# Aliases:
#   Before: alias Firmowid.Accounts.Organization
#   After:  alias Firmowid.Ash.Core.Organization
```

**`priv/repo/seeds/voidstack.exs`:**

Same patterns as bytecraft.

### G9 — Senders (namespace update)

Files:
- `lib/firmowid/ash/core/senders/confirmation_sender.ex`
- `lib/firmowid/ash/core/senders/email_change_sender.ex`
- `lib/firmowid/ash/core/senders/password_reset_sender.ex`

These alias `Firmowid.Accounts.UserNotifier`. After phase H moves UserNotifier
to `Firmowid.Ash.Core.UserNotifier`, update the aliases. Can be done in H.

## Verify after each sub-step

```bash
mix compile --warnings-as-errors
```

Full `mix check` after all G steps complete.

## Dependencies

- Phase E (code interfaces exist)
- Phase F (auth infrastructure rewritten — auth views reference new patterns)
- G7 Timetracker rewrite is in a separate doc: `lib/firmowid/ash/timetracker/docs/`
