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
4. If tool schemas or UI resources changed, use the app's **Refresh** flow to rediscover metadata, then start a new conversation with the app selected.
5. Submit a representative feature prompt and exercise the embedded UI interaction affected by the change.
6. Stop your foreground client and confirm it has exited before handing over the shared tunnel.

Verify the intended tool call, its result, and the embedded UI interaction in ChatGPT; local tests, MCP Inspector, and tunnel readiness do not substitute for that verification.
If browser access or a user action is required, hand off only the blocked step to the operator and report what remains unverified; never fabricate success.
Summarize observed results and blockers without private data or credentials.

## Code entrypoints

- `lib/firmowid_web/mcp/chatgpt/router.ex`: `/mcp-chatgpt` adapter, exposing `chatgpt_list_sessions`; the product `/mcp` endpoint is separate.
- `lib/firmowid/ash/timetracker/timetracker.ex`: ChatGPT tool declaration and sessions UI resource.
- `lib/mix/tasks/chatgpt.tunnel.ex`: existing launcher; inspect it when diagnosing a runtime failure rather than constructing a replacement command.
