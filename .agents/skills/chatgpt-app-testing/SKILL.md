---
name: chatgpt-app-testing
description: Use when developing or testing Firmowid ChatGPT tools and embedded UI through the existing [dev] firmowid app and shared tunnel.
---

# ChatGPT App Testing

## Existing setup

Use the existing **[dev] firmowid** app in the **Alergeek Ventures** ChatGPT
workspace. It is available to workspace users and linked to the shared tunnel.
Agree with the operator on tunnel ownership and the target worktree before use;
only one local environment may use it at a time.

**The app only works with a server started at `http://localhost:4000`, from
the `main` worktree.** A tunnel and its app keep the OAuth origin they were set
up with: refreshing tools, relinking an account or editing the app does not move
them to another origin, and any other origin fails with 404 or 502. That origin
resolves to each developer's own computer.

Follow `infisical-secrets`. The tunnel launcher reads `CONTROL_PLANE_API_KEY`
and `CONTROL_PLANE_TUNNEL_ID` from Infisical environment `dev`, folder
`/dev/openai-tunnel`.

## MCP tools and widgets

Expose MCP tools directly through the owning Ash domain's `tools` block and add
them to the `/mcp` tool allowlist. AshAi derives their contracts from resource
actions, arguments, types and policies. Follow `list_sales_invoices`,
`list_cost_invoices` or `get_ksef_connection_status` as existing examples.

Build interactive widgets under `lib/firmowid_mcp/`, within the owning feature;
use `FirmowidMcp.Ksef.Connection` and its LiveView as the existing example.
Reuse `Widgets` for tool/resource registration lookup and scoped tool execution,
`Runtime` for the HTML shell, content-addressed URIs and resource metadata, and
`Session`/`LiveSession` for signed mounts, authorization and expiry. The
existing `assets/js/mcp/bridge.js` connects LiveView to the Apps SDK, updates
model context and handles downloads and external links. Share UI through
`FirmowidUI` where both web and MCP use it. Follow `repository-organization` for
ownership rules.

## Feature development and testing

1. When the operator wants to work on the GPT app, prepare the `main`
   worktree: it listens on port 4000 (`.server.port`), and you set
   `PHX_URL=http://localhost:4000` in `.env.worktree`, then restart Phoenix
   (`tmux kill-session -t firmowid-4000`, then
   `tmux new -d -s firmowid-4000 "sh -lc 'env TERM=xterm-256color mix phx.server 2>&1 | tee tmp/phoenix.log'"`).
   `mix dev.up` writes the wave or Caddy URL back into `PHX_URL`, so set it
   again after every `mix dev.up`. Confirm
   `curl http://localhost:4000/.well-known/oauth-authorization-server` reports
   `http://localhost:4000` as the issuer.
2. Run `mix chatgpt.tunnel` and keep it in the foreground while testing. Its
   startup log must register `localhost` harpoon hosts.
3. Open **[dev] firmowid** in ChatGPT. Link the operator's Firmowid development
   account only if prompted; do not recreate or reconfigure the app or its
   tunnel.
4. After tool schemas or resource metadata change, ask a workspace administrator
   to refresh the app in workspace settings. Start a new conversation with the
   app selected. Widget URIs are content-addressed by `FirmowidMcp.Runtime`; use
   the generated URI rather than introducing manual versions.
5. Submit a representative prompt. Verify the tool result and exercise the
   affected widget flow, including validation, submission and model-context
   updates where applicable.
6. Stop your tunnel client and confirm it has exited before handing over the
   shared tunnel.

Local tests, MCP Inspector and tunnel readiness do not establish that the widget
works inside ChatGPT. Hand off blocked browser or administrator steps to the
operator and report what remains unverified. Keep private data and credentials
out of reports.

## Connection troubleshooting

The shared tunnel transports MCP calls and resource reads. A widget's LiveView
WebSocket connects directly from the tester's browser to the advertised worktree
origin. The tester needs access to that origin, including tailnet access when
applicable. `localhost` refers to the tester's computer.

Zen/Firefox Local Network Access (LNA) can block this WebSocket inside ChatGPT
even when the same page and form work directly. A domain exception in
`about:config` → `network.lna.skip-domains` was verified to unblock this setup.
Preserve existing comma-separated entries. Use the exact worktree hostname for a
diagnostic; for a developer who explicitly wants all Wave environments, use
`*.wave.local,*.wave.exposed`. The `*.` prefix matches nested subdomains at any
depth; repeated wildcards are unnecessary. These exceptions affect both source
and target domains, so any website may attempt connections to matching targets
without LNA checks. Keep application authentication and restore temporary
diagnostic exceptions after testing.

Identify the failing stage: MCP response/resource retrieval, widget CSP,
WebSocket handshake, LiveView mount, form event or model-context update. Inspect
the browser's actual CSP, `Origin`, response status and LNA diagnostics. HTTP
200 or success on a direct local-control page does not establish success in
ChatGPT. A local-control iframe needs `allow-forms` to exercise form submission.

References:
[Mozilla LNA settings](https://support.mozilla.org/en-US/kb/control-personal-device-local-network-permissions-firefox),
[wildcard semantics](https://firefox-admin-docs.mozilla.org/reference/policies/localnetworkaccess),
[Apps SDK resource metadata](https://developers.openai.com/apps-sdk/reference).

Inspect the existing `mix chatgpt.tunnel` launcher when diagnosing tunnel
startup or readiness failures.
