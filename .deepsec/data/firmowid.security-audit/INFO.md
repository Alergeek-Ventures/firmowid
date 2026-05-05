# firmowid.security-audit

## What this codebase does

- Polish multi-tenant business app for invoicing, cost-invoice intake,
  bank sync, payroll/time tracking, org management, and KSeF e-invoicing.
- Stack is Elixir + Phoenix LiveView with Ash/AshPostgres,
  AshAuthentication, PostgreSQL, and Oban.
- Sensitive integrations include Google OAuth, GoCardless,
  Resend webhooks/email, S3-compatible blob storage, OpenAI, and Reducto OCR.
- Core security shape is org-scoped data access; most business records live
  under an `organization_id` tenant.

## Auth shape

- `sign_in_with_password` and `register_with_google` are the main login paths;
  Google auto-linking is allowed only for provider-verified emails.
- `remember_me`, `sign_in_with_remember_me`, and `load_from_session` restore
  browser sessions automatically in the `:browser` pipeline.
- `load_from_bearer` is the API auth primitive in the `:api` pipeline.
- `require_authenticated_user_with_organization` is the main gate for app data;
  it also builds `ash_scope` with `actor` + tenant.
- `require_superuser` is the extra gate for non-dev `/admin` routes.

## Threat model

- Highest-impact bug class is cross-tenant data exposure: invoices, payroll,
  bank transactions, blobs, and KSeF state leaking across organizations.
- Next is privilege expansion through Ash policy bypasses, mis-scoped jobs,
  or overly broad `SystemActor` roles.
- Public attack surface is concentrated in auth routes, Resend webhook intake,
  public invoice share links, file/PDF download flows, and bank/KSeF callbacks.
- Attackers would also value secrets or tokens for KSeF, Google OAuth,
  Resend, GoCardless, S3 storage, and AI/OCR integrations.

## Project-specific patterns to flag

- Any use of `skip_organization_id`, `put_skip_org_id`, or direct `Repo.*`
  reads/writes that bypass normal tenant scoping.
- Any new `SystemActor` role, Ash `bypass` policy, or job path that widens
  automated access beyond one org.
- Any anonymous/public flow around `by_share_token`, `/faktura/:token`, or
  share-token PDF rendering that loads more than the intended invoice.
- Any webhook or inbound-email flow that trusts recipient parsing or payload
  fields without `WebhookAuth` signature verification and explicit org checks.
- Any blob/PDF/export path that could expose wrong-tenant files or accidentally
  include internal-only fields such as invoice notes.

## Known false-positives

- `SalesInvoice.by_share_token` intentionally does one bootstrap
  cross-tenant lookup with `Repo.one(skip_organization_id: true)` before
  rebuilding a properly tenant-scoped anonymous scope.
- `/faktura/:token` is intentionally public; access is controlled by the share
  token plus `SystemActor` role `:anonymous`, not by user session auth.
- `/kosztowe/skrzynka` is intentionally public at the router layer; it is
  protected by `FirmowidWeb.Infrastructure.Plugs.WebhookAuth` using Svix-style
  HMAC verification.
- `authorize?: false` and some `skip_organization_id` calls appear often in
  `*_test.exs` and fixtures; treat test-only uses separately from production.
- Simple raw SQL or SQL-looking code such as the `/health` `SELECT 1` check,
  Ash fragments, or hardcoded parameterized queries are often intentional.
