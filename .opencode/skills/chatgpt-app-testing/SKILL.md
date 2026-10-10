---
name: chatgpt-app-testing
description: Use when developing or testing Firmowid ChatGPT tools and embedded UI through the existing Firmowid Dev app and shared tunnel.
---

# ChatGPT App Testing

## Existing setup

The **Firmowid Dev** test app is already configured in the **Alergeek Ventures** ChatGPT workspace, accessible to all users, and linked to the shared tunnel.
Only one local environment may use that tunnel at a time; agree with the operator on ownership and the target worktree before use.

Follow `infisical-secrets` for secret handling: `CONTROL_PLANE_API_KEY` and `CONTROL_PLANE_TUNNEL_ID` are in Infisical environment `dev`, folder `/dev/openai-tunnel`; the launcher reads them.

## Feature development and testing

1. Use the existing local services according to `AGENTS.md`.
2. Run `mix chatgpt.tunnel` and keep it in the foreground throughout testing.
3. Test the existing **Firmowid Dev** app in real ChatGPT. Link the operator's Firmowid development account only if prompted; do not recreate or reconfigure the app.
4. If tool schemas or resource metadata changed, an operator with the required administrator permissions must refresh **Firmowid Dev in workspace settings**, then the tester starts a new conversation with the app selected. Ordinary testers may not have permission to refresh; hand this step to the administrator. Treat UI resource URIs as cache keys: version the URI when replacing a cached widget or its CSP, and update every reference.
5. Submit a representative feature prompt and exercise the embedded UI interaction affected by the change.
6. Stop your foreground client and confirm it has exited before handing over the shared tunnel.

Verify the intended tool call, its result, and the embedded UI interaction in ChatGPT; local tests, MCP Inspector, and tunnel readiness do not substitute for that verification.
If browser access or a user action is required, hand off only the blocked step to the operator and report what remains unverified; never fabricate success.
Summarize observed results and blockers without private data or credentials.

## LiveView widgets and local network access

The shared tunnel transports MCP calls and resource reads. A widget's LiveView
WebSocket connects directly from the tester's browser to the advertised worktree
origin. The tester needs access to that origin, including tailnet access when
applicable. `localhost` refers to the tester's computer.

Zen/Firefox Local Network Access (LNA) can block this WebSocket inside ChatGPT
even when the same page and form work directly. A domain exception in
`about:config` → `network.lna.skip-domains` was verified to unblock this setup.
Preserve existing comma-separated entries. Use the exact worktree hostname for
a diagnostic; for a developer who explicitly wants all Wave environments, use
`*.wave.local,*.wave.exposed`. The `*.` prefix matches nested subdomains at any
depth; repeated wildcards are unnecessary. These exceptions affect both source
and target domains, so any website may attempt connections to matching targets
without LNA checks. Keep application authentication and restore temporary
diagnostic exceptions after testing.

Distinguish failures by stage: MCP response validation/resource retrieval,
widget CSP, WebSocket handshake, LiveView mount, form events, and model-context
updates. HTTP 200 alone does not validate a negotiated MCP response. For
ChatGPT CSP compatibility, mirror standard resource `_meta.ui.csp` in
`_meta["openai/widgetCSP"]` using `connect_domains` and `resource_domains`;
include the HTTPS and WSS origins required by the widget. Inspect the actual
browser CSP before assuming the metadata was applied. A local-control iframe
needs `allow-forms` as well as its script permissions to exercise submission.

Verify connected LiveView, validation, submission, and model-context delivery
inside ChatGPT. Success on a direct local-control page only verifies that path.
For a failed handshake, inspect the browser's actual `Origin`, response status,
and LNA diagnostics rather than attributing the failure to proxy latency.

References: [Mozilla LNA settings](https://support.mozilla.org/en-US/kb/control-personal-device-local-network-permissions-firefox),
[wildcard semantics](https://firefox-admin-docs.mozilla.org/reference/policies/localnetworkaccess),
[Apps SDK resource metadata](https://developers.openai.com/plugins/reference).

## Code entrypoints

- `lib/firmowid_web/mcp/`: shared `/mcp` transport, signed LiveView capabilities and embedded runtime.
- `lib/firmowid/ash/invoicing/invoicing.ex`: the sole tool, `list_invoices`; native AshAi arguments use `{"input": {...}}`.
- `lib/firmowid_web/invoicing/mcp/`: invoice presentation and dynamic UI resource, sharing the application's design system.
- `lib/mix/tasks/chatgpt.tunnel.ex`: existing launcher; inspect it when diagnosing a runtime failure rather than constructing a replacement command.
