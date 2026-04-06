# Accounts → Core Migration Progress

## Completed

- **Sub-phase A** — Added `ash_authentication`, `ash_authentication_phoenix` deps + `Argon2Provider`
- **Sub-phase B** — Migration (tokens, user_identities tables), Token + UserIdentity + Secrets + Senders, User resource fully transformed
- **Sub-phase C** — Organization resource writable (12 actions, changes, calculations)
- **Sub-phase D** — OrganizationInvite resource (multitenant, 5 actions)

## Remaining — Phase E through H

| Phase | Doc | Status |
|-------|-----|--------|
| E — Code interfaces + resource prep | [phase-E-code-interfaces.md](phase-E-code-interfaces.md) | Pending |
| F — Auth infrastructure | [phase-F-auth-infrastructure.md](phase-F-auth-infrastructure.md) | Pending |
| G — Callsite updates (non-timetracker) | [phase-G-callsite-updates.md](phase-G-callsite-updates.md) | Pending |
| G7 — Timetracker Ash rewrite | [../../timetracker/docs/phase-G7-timetracker-ash-rewrite.md](../../timetracker/docs/phase-G7-timetracker-ash-rewrite.md) | Pending |
| H — Cleanup | [phase-H-cleanup.md](phase-H-cleanup.md) | Pending |

## Execution order

1. **E** — pure additive, nothing breaks
2. **F** — rewire auth infrastructure (test login/logout immediately)
3. **G1–G6** — callsite updates (file-by-file, each compilable)
4. **G7** — timetracker Ash rewrite (can run in parallel with G1–G6 after E)
5. **G8–G9** — seeds + tests
6. **H** — cleanup + final verification

Compile check after each step. Full `mix check` after F, after all G, after H.

## Key decisions

| # | Decision |
|---|----------|
| 1 | Avatar: `Ash.load!(entity, [avatar_blob: [:url]], ...)` at callsites. No special calculations. |
| 2 | Google linking: `upsert? true` for now. TODO: email confirmation later. |
| 3 | Forms: `AshPhoenix.Form` everywhere. |
| 4 | Session management: `AshAuthentication.Plug` (JWTs, not DB tokens). |
| 5 | User destroy: password verification at callsite. |
| 6 | Timetracker: full Ash rewrite. Domains expose `:list` reads. Views compose. |
| 7 | RememberMe add-on included. |
| 8 | On-mount: `ash_authentication_live_session` + focused hooks (RequireOrganization, etc.). |
| 9 | Performance: address if issues arise. |
| 10 | Bodyguard → `user.role == :admin` guard. |
| 11 | Transaction pattern for reads: one `:list` action per resource with optional filter arguments. |
| 12 | `Timetracker.seconds_to_hours/1` (ceiling) is a business rule — stays on domain. |
| 13 | Cross-domain composition (User × Session × Salary) happens in view layer, not domain actions. |

## Justified Ecto exceptions (kept)

| Exception | File | Reason |
|-----------|------|--------|
| Oban job count | `invoicing.ex` | Oban has no count API |
| Cross-tenant share token lookup | `sales_invoice.ex` | Ash multitenancy can't be bypassed inline |
| Postgres regex in numbering | `sales_invoice.ex` | `fragment("? ~ ?")` — no Ash regex operator |
| Organization IDs query | `matching_worker.ex` | Infrastructure — reads all org IDs for cron |
| Oban job queries | `ksef.ex`, `session_worker.ex` | Oban has no Ash interface |
| `Repo.drop_paradedb_unnamed()` | project listing callsite | ParadeDB cleanup |
