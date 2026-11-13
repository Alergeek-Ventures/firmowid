---
name: chatgpt-app-review
description: Use when changing what the MCP server exposes to ChatGPT or other AI clients (server instructions, tools, widgets, tool results, OAuth consent) or when preparing a resubmission of the Firmowid ChatGPT app to OpenAI review.
---

# ChatGPT App Review

The Firmowid ChatGPT app is reviewed by OpenAI against its app submission
guidelines. Two findings shaped the current design:

- The app must not collect sensitive personal data. Invoices for private
  individuals (PESEL) are therefore not issued through MCP:
  `FirmowidMcp.Invoicing.Privacy` removes PESEL from schemas and results and
  the server instructions keep consumer invoices in the web app.
- The app must not collect authentication secrets in any plugin interface, the
  embedded widgets included, not only in chat messages. Instructions that send
  the user to a widget to enter credentials count as collecting them, even if
  chat is forbidden.

## Rules

- No MCP surface asks for, accepts or shows authentication secrets: KSeF
  tokens, passwords, certificates, private keys, signed authentication files,
  bank logins. This covers server instructions, tool descriptions, tool
  arguments and results, widgets and their model context.
- Connections that need such secrets (KSeF, banks) are set up only in the
  Firmowid web app. A tool or widget that needs a missing connection says so
  and gives the web address; for KSeF that is `FirmowidMcp.Ksef.settings_url/0`,
  which the server instructions and the confirmation widget both use.
- A link in a widget opens through the host: render it with `target="_blank"`
  and `assets/js/mcp/bridge.js` passes it to `app.openLink`.
- Prefer status tools that read metadata only, as `get_ksef_connection_status`
  does, over widgets that change settings.
- Keep the in-app assistant and MCP on the same tools (`Firmowid.AiTools`);
  list every difference there with its reason.
- The OAuth consent screen (`FirmowidWeb.Auth.Components.McpConsent`) tells
  people in plain words what the MCP tools read and change. When a tool adds a
  kind of data or a write, update those lines; a reviewer compares them with
  the tool list.
- The connection pages show the client's logo (`FirmowidWeb.Auth.Components.ClientLogo`),
  chosen by the host of its Client ID Metadata Document, never by its
  registered name, which any client can set.

## Accounts that are not ready

An AI client starts at `/oauth/authorize`. A signed-out person signs in or signs
up first; an account without a company, or an admin whose company has not
finished the setup wizard (with the `inbox` flag), goes through the web setup
and returns to the consent screen afterwards.
`FirmowidWeb.Auth.Utilities.ConsentOrganization` decides this and
`FirmowidWeb.Auth.Utilities.PendingAuthorization` keeps the client's name and
the request in the session. `pending_authorization_test.exs` covers both flag
variants and checks that the connected client gets no KSeF setup tool.

## Before resubmitting

1. Read the server instructions (`FirmowidMcp.instructions/0`), every tool
   description in the Ash domains' `tools` blocks and every widget for the rules
   above.
2. Exercise the changed flow through the [dev] app (`chatgpt-app-testing`).
3. Refresh the app's tools in the OpenAI dashboard and describe the changed
   flow in the reviewer information; the PR that changed it carries a draft.
