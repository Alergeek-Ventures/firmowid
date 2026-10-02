# Read-only embedded UI prototype

This is a local implementation prototype, **not a completed ChatGPT demo or
acceptance test**. No new credentials, database schema, seed data or authorization
policies are required. The isolated tunnel OAuth flow has an optional dev-only
canonical resource setting described below.

## Local tunnel launcher

Agree who owns the shared tunnel (one active client only), keep the existing
worktree server running, and use the existing Firmowid Infisical login/project:

```sh
mix chatgpt.tunnel
```

Runs only in `MIX_ENV=dev`. Requires trusted `bash`, `infisical` and `tunnel-client` on PATH; the task never installs
them or starts/restarts Firmowid. It reads `.server.port` relative to the Mix
project, fetches only `CONTROL_PLANE_API_KEY` and `CONTROL_PLANE_TUNNEL_ID` from
Infisical dev `/dev/openai-tunnel`, and passes them only through the child
environment. Missing/placeholder values fail closed, with no fallback key.
The fixed target is `http://localhost:<port>/mcp-chatgpt`; both `main` and
`harpoon` polling are enabled for OAuth discovery. All inherited env names are
unset except `PATH`, `HOME`, `SSL_CERT_FILE`, `SSL_CERT_DIR`, `LANG`, `LC_ALL`,
and `LC_CTYPE`; only the two transport credentials are added. Application/AWS/
database credentials, profiles, proxies and shell startup hooks are not passed.
Infisical runs separately with its existing login environment and captured output.
Logs are info
JSON with raw HTTP logging and payload capture off, health/UI are loopback-only,
and Cloudflare is disabled. Never export auth diagnostics or configuration.

This intentionally enables Harpoon plaintext HTTP for trusted localhost
development, not arbitrary remote callouts. Inspect/approve discovery metadata
first. Keep the invocation in the foreground. The fixed repository Bash helper
forwards INT/TERM/HUP to its owned direct child, allowing a 0.2-second signal
grace period before TERM cleanup. Every 0.2 seconds it checks the Mix OS PID;
parent exit (including SIGKILL) triggers TERM, 50 waits of 0.1 seconds (about
5 seconds), then KILL if necessary, followed by `wait`. Cleanup never writes to the
possibly closed log pipe. There is no separate watchdog or process-group kill.
Cloudflare and stdio subprocesses are disabled; grandchildren are not supervised.
Killing the supervisor itself with SIGKILL, an unreaped zombie parent, PID reuse, or an OS-uninterruptible
child are outside this portable polling guarantee. Confirm child exit before
handoff. No other client's processes are killed. See `.opencode/skills/chatgpt-app-testing/SKILL.md` for
ownership, OAuth checks and mandatory real ChatGPT acceptance. Tunnel readiness
does not prove OAuth linking or embedded UI acceptance.

## Dev-only canonical OAuth resource

Transport credentials (`CONTROL_PLANE_API_KEY`, `CONTROL_PLANE_TUNNEL_ID`) stay
in Infisical **dev `/dev/openai-tunnel`**. Separately, the operator writes
the exact observed non-secret canonical resource URL as
`CHATGPT_OAUTH_RESOURCE_URL` only in this worktree's **untracked `.env.worktree`**.
Do not insert it into shared Infisical dev `/app`: that folder is loaded by all
developers/worktrees, while this approval covers only the isolated current
worktree. Do not derive or guess it from the local transport endpoint. No shared
Infisical key, second environment or production secret is needed. Before any
agent edit, verify `.env.worktree` is git-ignored; if safety tooling blocks access,
stop and ask the user to add the non-secret line rather than bypassing the block.

The existing loader exports `/app` into the process environment, then applies
`.env.worktree` overrides. `config/runtime.exs` reads this optional value **only
in dev**, validates the exact lowercase HTTPS host
`tunnel-service.gateway.unified-0.internal.api.openai.org` and path
`/v1/mcp/tunnel_<32 lowercase hex characters>`, and fails startup on malformed
values. Only absent/default HTTPS port or explicit `:443` is allowed; userinfo,
query, fragment, whitespace, URL aliases and alternate paths are rejected.
Missing means `Endpoint.url() <> "/mcp"`; production and test ignore the env var.

This is explicitly approved for this temporary worktree used only by ChatGPT
and Tidewave. The shared OAuth server's resource controls protected-resource
metadata, authorize/token resource checks and JWT audience issuance/validation
(`ash_authentication_oauth2_server` installed version **0.3.1**). Therefore it
also changes the audience for existing product `/mcp` clients: old local-resource
tokens/requests no longer match while enabled. Tidewave is not a tunnel target.
Incoming arbitrary `resource` parameters are never rewritten or allowlisted.
The issuer and localhost redirect compatibility rewrite remain unchanged.

Choose **DCR** (dynamic client registration), public client authentication
`none` with PKCE S256. Version 0.3.1 CIMD reads the singular
`token_endpoint_auth_method` and rejects `private_key_jwt`; the observed client
metadata advertises plural supported methods including `none`. Do not switch
to CIMD or broaden server authentication to paper over that incompatibility.

After the operator adds/verifies the exact local `.env.worktree` value, the **operator
must restart Phoenix** to rerun the loader and runtime configuration. Agents must
not restart the app or tunnel. Hot code reload alone cannot reread runtime
environment/config. Use the normal Phoenix restart mechanism only: **do not use
`mix dev.down` for an ordinary restart**, because it removes development volumes
and can destroy local database and service data. A deliberate manual
application-config update is a separate operator action, not a persistent
substitute. After Phoenix is restarted, use ChatGPT's **Refresh** separately to
refresh the app/metadata; it does not restart Phoenix. The user previously
confirmed an end-to-end OAuth widget limit-1 run before the later hardening.
Normalized output and supervisor behavior have since been verified locally, but
that is not a fresh real ChatGPT retest; optional real acceptance remains pending.

## Contracts

- Technical endpoint: `/mcp-chatgpt`, native AshAi HTTP MCP transport.
- Authentication: the same `:mcp` pipeline as `/mcp`: required OAuth bearer,
  `mcp` scope, authenticated actor with an organization, organization as tenant.
  The HTML never receives a bearer token and never fetches the server directly.
- Only tool: `chatgpt_list_sessions`, reusing
  `Firmowid.Ash.Timetracker.Session.list_user_sessions`. The action filters on
  the actor's ID and applies existing resource authorization and multitenancy.
- Arguments: `{"input":{"after_date":"2026-09-01"},"limit":25}`.
  `input.after_date` is optional, inclusive UTC, validated by Ash as a date.
  `limit` defaults to 25 and must be an integer from 1 to 50. No arbitrary
  filter, sort, offset, aggregate, tenant or user input is accepted. Newest first.
- Only resource: `ui://firmowid/chatgpt/sessions.html`, MIME
  `text/html;profile=mcp-app`, bound via native `_meta.ui.resourceUri`.
  CSP connect/resource/frame/base-URI domain allowlists are all empty. No
  browser permissions, external dependencies, external assets or fetch calls.
- Successful result: matching `content[0].text` JSON and `structuredContent`:

  ```json
  {
    "sessions": [
      {
        "title": "Praca nad projektem",
        "start_datetime": "2026-09-01T09:00:00Z",
        "end_datetime": "2026-09-01T10:00:00Z",
        "duration": 3600,
        "project": {"name": "Projekt"}
      }
    ],
    "limit": 25,
    "after_date": "2026-09-01",
    "possibly_truncated": false
  }
  ```

  The adapter emits exactly the listed top-level and session fields: native
  identifiers and timestamps are stripped. `start_datetime`, `end_datetime`,
  `duration`, and `project` are required session properties; `end_datetime` is
  an ISO-8601 datetime string, and `project` is either `null` or exactly
  `{"name":"Projekt"}` (no other project properties). `duration` is in seconds.
  There is no total count or pagination contract. `possibly_truncated`
  conservatively means the returned length reached the requested limit, not
  proof of another page. Errors retain the native `isError`/text envelope. The
  adapter advertises a matching `outputSchema`; `additionalProperties` is
  `false` for the wrapper, each session, and non-null project objects.

## Compatibility adapter

Installed AshAi 1.0.3 natively registers static HTML resources, UI bindings and
tool `_meta`, but does not emit top-level annotations/security schemes. Its
read executor uses an **unpaginated bounded query and serializes a list**, not
an Ash page envelope; lists do not receive native `structuredContent`.

The endpoint-specific Plug delegates execution, origin validation and protocol
handling to AshAi, bounds arguments through its supported transformer hook,
then decorates JSON responses. It normalizes the preview result to the exact
closed output contract above, removing native record identifiers and other
unadvertised fields. It adds standard read-only/non-destructive/
closed-world annotations and top-level OAuth `securitySchemes`, mirrored in
native `_meta.securitySchemes`. It wraps the native list into the preview map
  above and advertises its matching output schema. No dependency fork or
  replacement MCP server is involved.

The existing `/mcp` tool allowlist and tools are unchanged. Its resource
allowlist is explicitly empty to preserve its previous absence of resources
after registering this new resource in the shared domain.

Static HTML in `priv/mcp_apps/chatgpt` is intentional: the native
`mcp_ui_resource` API requires `html_path`, read at request time. This is an MCP
Apps resource, not a Phoenix template. Deployment must retain the `priv` asset
and use a working directory in which that configured path resolves.

## UI protocol and verification limits

The self-contained UI implements JSON-RPC over parent `postMessage`:
`ui/initialize` (Apps protocol `2026-01-26`),
`ui/notifications/initialized`, initial `ui/notifications/tool-result`, and
Refresh through `tools/call`. It checks `event.source === window.parent`, pins
the parent origin after the initialization response (opaque sandbox origins
require wildcard outbound target), correlates request IDs, and times out
requests. All session text is rendered with DOM `textContent`.

Regression tests cover endpoint routing/unauthenticated rejection, descriptor
and resource allowlists, metadata/CSP, mutation rejection, bounded inputs, and
real Ash-authorized results with same-tenant other-user and cross-tenant data.
Those execution tests set the actor/tenant directly on a test connection;
they do not constitute a full OAuth linking or real ChatGPT acceptance test.

The OAuth server's default canonical protected resource remains `/mcp`
(`Firmowid.Ash.Core.Secrets`), unless the dev override above is enabled. Real ChatGPT
discovery/linking for the additional endpoint and actual host rendering must
still be verified. The adapter supplies the missing descriptor fields but
does not claim full Apps SDK compatibility across hosts.
