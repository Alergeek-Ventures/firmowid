---
name: chatgpt-app-testing
description: Use when testing Firmowid's ChatGPT app through Secure MCP Tunnel, including safe shared Infisical credentials, operator handoff, OAuth linking, embedded UI, and real ChatGPT acceptance.
---

# ChatGPT App Testing

## Scope and prerequisites

- Load and follow `infisical-secrets` first (`../infisical-secrets/SKILL.md`). Use the Firmowid project, environment `dev`, folder `/dev/openai-tunnel`; `/app` remains application runtime configuration. Do not move existing secrets.
- Use trusted `infisical` and `tunnel-client` binaries already available on PATH (the project's devenv provides them). Binary provisioning is an environment detail, not this skill's workflow: do not prescribe Nix, install packages, download arbitrary executables, run download-to-shell scripts, or bypass OS security checks. If a binary is absent or incompatible, stop and ask the developer.
- CLI reference version: official `openai/tunnel-client` **v0.0.15**, not a guarantee of the installed version. Before secret access, check `tunnel-client --version`, `tunnel-client run --help`, and `infisical secrets get --help`. The installed `run --help` must support every flag shown below; stop on incompatible syntax and do not silently install or upgrade.
- Use the existing worktree server, port from `.server.port`, and approved read-only ChatGPT prototype endpoint `/mcp-chatgpt`; verify that it is implemented and available before running. The existing product endpoint `/mcp` remains separate. Do not add an environment seed, start a second server, or restart the server. Ask the developer if the existing service is unavailable.
- Never expose Tidewave (including its MCP endpoint), debugging/admin endpoints, production secrets, or production/account API keys. Only approved product MCP endpoints (`/mcp-chatgpt` for this prototype, `/mcp` for existing product testing) may be local tunnel targets. Keep tunnel health/admin UI loopback-only.
- The target ChatGPT workspace/account and linked Firmowid development account/data must belong to the **current operator**. Do not assume another developer's login, seeded account, consent, or data is appropriate. The control-plane runtime key is transport authentication, not Firmowid user authentication.

## Shared tunnel ownership and permissions

Use only `CONTROL_PLANE_API_KEY` and `CONTROL_PLANE_TUNNEL_ID` from the shared folder. The key is a runtime key with OpenAI Tunnels **Read + Use**, never an admin key. Tunnel management (**Read + Manage**) is a separate administrative task, not required for this run.

Verify that the tunnel is associated with the intended ChatGPT workspace and Platform organization. A personal Platform association alone does not make it visible in another workspace. The app creator also needs Tunnels **Read + Use** and separate ChatGPT developer-mode permissions; ask the workspace administrator when these are missing.

**Project rule: one active client per shared tunnel**, even for HTTP testing. This prevents developers' worktrees/accounts competing for requests; it is stricter than the upstream stdio-only deployment limit. Communicate manually with developers before starting: agree who owns the tunnel, which worktree is targeted, and when testing ends. Do not kill another developer's client. On handoff, the prior owner stops their foreground client (Ctrl-C), confirms it has exited, then the next owner starts theirs. Do not overlap, background with `nohup`/`disown`, or create managed runtimes.

## Foreground run (current worktree, checked and supervised)

Prefer the repository launcher after agreeing on ownership and approving the existing localhost OAuth discovery metadata:

```sh
mix chatgpt.tunnel
```

The task locates this worktree through `Mix.Project.project_file()` (not the shell's current directory), validates its regular, non-symlink `.server.port` in `1..65535`, and checks required CLI flags before secret access. Missing binaries produce actionable errors, never an install. It captures only the two exact shared Infisical values with `--silent --secret-overriding=false`; retrieval output and errors are never printed. Empty, malformed and placeholder credentials fail closed; `OPENAI_API_KEY` is never a fallback. Credentials are child environment bindings, not argv.

It unsets **all inherited environment names** except `PATH`, `HOME`, `SSL_CERT_FILE`, `SSL_CERT_DIR`, `LANG`, `LC_ALL` and `LC_CTYPE`, then adds only the two transport credentials. Names are enumerated without logging values; application/AWS/database keys, profiles, proxies, loader injection and Bash startup hooks are not passed. Infisical help/retrieval run separately with the existing login environment and captured output. Use trusted binaries, HOME and certificate paths; this is environment isolation, not a sandbox against malicious executables or config files in HOME. Normal Mix project configuration may still load `/app` through the existing config workflow; those credentials do not reach the supervisor/client.

The fixed foreground run targets only `http://localhost:<port>/mcp-chatgpt`, polls **both `main` and `harpoon`**, fixes the public control-plane base and empty path, deliberately opts into localhost-development plaintext HTTP, uses loopback ephemeral health and info JSON logs, and disables raw HTTP logging, payload capture, remote UI/browser opening and managed Cloudflare. No detached runtime or app start/restart is created. Keep safe logs local; do not export effective configuration, payloads or auth diagnostics.

The task runs only in `MIX_ENV=dev`, requires the development environment's Bash and invokes only the static `priv/scripts/chatgpt_tunnel_supervisor.bash` helper with the numeric Mix OS PID and resolved trusted executable. The helper owns one direct tunnel child, forwards INT/TERM/HUP (with a 0.2-second grace period before TERM cleanup), and polls parent liveness every 0.2 seconds. On shutdown/parent death (including SIGKILL of BEAM), it sends TERM, performs 50 waits of 0.1 seconds (about 5 seconds), then KILL if still running, and reaps the child with `wait`. It never writes cleanup output to a closed BEAM log pipe, launches an independent watchdog, or kills process groups/other clients. Cloudflare/stdio subprocesses are disabled; grandchildren are not supervised. SIGKILL of the supervisor itself, an unreaped zombie parent, PID reuse, and OS-uninterruptible children are outside this portable polling guarantee. Confirm child exit before handoff. Do not kill the helper directly or background/disown the task.

The manual command below remains for diagnostics; it is **not equivalent** to the task's environment isolation or parent-death supervision. Prefer the task. Do not run either while another developer owns the shared tunnel.

The following **Bash** subshell captures exact shared values, fails closed, validates the port, and passes credentials only through the child environment. Run from the worktree root with the existing Infisical login/project selection pointing to Firmowid; never guess a project ID. No key value belongs in argv, logs, chat, files, or shell history.

Use a trusted shell without inherited tunnel profiles, extra channels/targets/headers, unsafe logging, or unapproved control-plane/proxy settings. Review configuration by names, not environment dumps. The snippet clears profile selection and stdio target, fixes the public OpenAI control-plane host, and disables raw HTTP logging; it is not a sanitizer for every possible inherited setting. Stop if the environment's provenance/configuration is unclear.

**Deliberate local-development opt-in:** the command below enables `--harpoon.allow-plaintext-http` because v0.0.15 requires it to register OAuth-discovered HTTP protected-resource/upstream targets. Run it only after inspecting discovery metadata and configuration and approving the trusted loopback origin `http://localhost:<port>`, with no extra targets, remote scopes, or remote HTTP origins. This switch is not loopback-scoped by the client: do not use it as a general production workaround or enable it for arbitrary HTTP callouts. Prefer HTTPS outside this deliberate local test. Leave Cloudflare disabled; reject inherited managed/static Cloudflare settings rather than starting a companion.

Use `localhost` to match the current development OAuth issuer. `localhost` and `127.0.0.1` are **distinct origins**, even on the same port. Inspect the current issuer and metadata first: align the target hostname with the issuer, or explicitly trust only the inspected, expected local origin using `--mcp.oauth-trusted-origin=http://localhost:<port>` if an approved target deliberately uses `127.0.0.1`. Do not broadly trust advertised origins. Keep `--log.format=json`: the validated local CLI run failed without an explicit log format.

```bash
(
  set +x
  set -euo pipefail
  command -v infisical >/dev/null || exit 1
  command -v tunnel-client >/dev/null || exit 1
  [[ -r .server.port ]] || exit 1
  PORT=$(<.server.port)
  [[ "$PORT" =~ ^[0-9]{1,5}$ ]] || exit 1
  (( 10#$PORT >= 1 && 10#$PORT <= 65535 )) || exit 1

  unset TUNNEL_CLIENT_CONFIG TUNNEL_CLIENT_PROFILE TUNNEL_CLIENT_PROFILE_FILE
  unset MCP_COMMAND OPENAI_API_KEY OPENAI_ADMIN_KEY
  CONTROL_PLANE_API_KEY=$(infisical secrets get CONTROL_PLANE_API_KEY \
    --domain https://infisical.alergeek.me --env=dev \
    --path=/dev/openai-tunnel --plain --secret-overriding=false \
    --silent 2>/dev/null) || exit 1
  [[ -n "$CONTROL_PLANE_API_KEY" ]] || exit 1
  CONTROL_PLANE_TUNNEL_ID=$(infisical secrets get CONTROL_PLANE_TUNNEL_ID \
    --domain https://infisical.alergeek.me --env=dev \
    --path=/dev/openai-tunnel --plain --secret-overriding=false \
    --silent 2>/dev/null) || exit 1
  [[ "$CONTROL_PLANE_TUNNEL_ID" =~ ^tunnel_[0-9a-f]{32}$ ]] || exit 1
  MCP_SERVER_URL="http://localhost:$PORT/mcp-chatgpt"
  export CONTROL_PLANE_API_KEY CONTROL_PLANE_TUNNEL_ID MCP_SERVER_URL
  tunnel-client run \
    --mcp.server-url="$MCP_SERVER_URL" \
    --harpoon.allow-plaintext-http \
    --control-plane.base-url=https://api.openai.com \
    --control-plane.url-path= \
    --control-plane.poll-channel=main \
    --control-plane.poll-channel=harpoon \
    --health.listen-addr=127.0.0.1:0 \
    --log.format=json \
    --log.level=info --log.http-raw-unsafe=false
)
```

Keep the foreground client running during discovery and every ChatGPT call. Use its local health/UI address to check `/healthz`, `/readyz`, and `/ui` without exporting logs, payloads, or effective configuration. A healthy process, polling, or ready status is **transport readiness, not a completed demo**. Empty/missing values or retrieval failures must stop the run; never fall back to another key or environment. Subshell exit ends the exported variables' lifetime without altering the parent shell.

### OAuth discovery troubleshooting

The repeated `--control-plane.poll-channel` flags are required: `main` and `harpoon` must both be allowlisted for OAuth discovery and the locally auto-registered Harpoon targets. A startup-ready `/readyz` response (including HTTP 200) does not validate Harpoon polling. If logs show `unsupported channel harpoon`, the client is configured with only the `main` allowlist. Stop only your own client, replace its command with the run snippet above, and restart only the tunnel client—not Firmowid. Then refresh the app metadata and retry app creation.

## OAuth is a separate verification gate

Secure MCP Tunnel can forward MCP traffic and OAuth discovery, but it does **not** automatically make the authorization server browser-accessible. In v0.0.15 the OAuth shim does not rewrite `authorization_endpoint`: the browser goes **directly to the upstream authorization endpoint**. Verify reachability from the operator's browser and any server-side discovery/token callers; a reachable local `/mcp` alone is insufficient. Do not invent a public endpoint or launch another tunnel to work around this.

Before claiming account linking works, verify:

- Protected-resource metadata/challenges and the canonical `resource` identifier across discovery, authorization, token exchange, and audience validation. Default is `http://localhost:<port>/mcp`; `/mcp-chatgpt` transport does **not** imply that audience. In the explicitly approved temporary ChatGPT/Tidewave-only worktree, the operator sets the exact observed non-secret `CHATGPT_OAUTH_RESOURCE_URL` only in this worktree's **untracked `.env.worktree`**, separate from shared transport credentials in Infisical **dev `/dev/openai-tunnel`**. **Never insert the URL into shared Infisical dev `/app`**: all developers/worktrees load that folder, but approval covers only this isolated worktree. The loader applies `.env.worktree` last. Before any agent edit, verify the file is git-ignored; if safety tooling blocks access, stop and ask the user to add the non-secret line without bypassing the block. Runtime config reads it only in dev and strictly accepts HTTPS `tunnel-service.gateway.unified-0.internal.api.openai.org` with `/v1/mcp/tunnel_<32 lowercase hex characters>`, no userinfo/query/fragment, and no port except 443. Malformed values fail startup; missing uses the default; prod/test ignore it. It changes the shared product `/mcp` canonical resource and JWT audience within this worktree, so existing local-resource clients/tokens there will not match while enabled. Never rewrite arbitrary incoming resource parameters. No shared Infisical key, second environment or production secrets are needed. The user must restart the app after config changes; hot code reload cannot reread runtime env/config. Agents must not restart app or tunnel.
- Choose **DCR** with public-client `none` authentication and PKCE S256. Installed `ash_authentication_oauth2_server` **0.3.1** CIMD uses singular `token_endpoint_auth_method` and rejects `private_key_jwt`, while the observed client supports `none` in plural supported-method metadata. Do not use CIMD or weaken authentication to bypass this mismatch. The shared `resource_url` controls protected-resource metadata, authorize/token checks, and JWT audience issuance/verification; inspect these after the user restart.
- The exact authorization-server `issuer`, metadata endpoints, authorization/token URLs, and server-side token validation (issuer, audience, expiry, scopes). Tunnel acceptance of metadata is not proof of OAuth correctness.
- Authorization-code + PKCE with `S256`, client registration/identification, and the **exact callback shown by ChatGPT** allowlisted by the provider. Do not assume one universal callback URI or localhost callback.
- Only explicitly approved extra metadata/authorization origins are trusted. v0.0.15 supports `MCP_OAUTH_TRUSTED_ORIGINS` for discovery; this is not browser routing. The deliberate loopback HTTP run above requires the separate Harpoon plaintext opt-in; recheck discovered targets and inherited configuration so that it cannot authorize unapproved remote HTTP callouts.
- Linking resolves the current operator's Firmowid development identity and enforces its permissions. Never replace OAuth with static account keys or bypass auth to finish a demo.

If these checks fail, report the specific unverified gate and ask the developer for the intended auth configuration. Local diagnostics validated the hostname/plaintext/log-format corrections only; this skill does **not** claim authenticated linking, embedded UI, or ChatGPT acceptance.

## Create and refresh the development app

1. In the intended ChatGPT workspace, enable developer mode if permitted. Use **Settings / Workspace settings → Apps → Create**, then choose **Tunnel** and the shared tunnel. Current UI may instead label this as a developer-mode connection under Plugins; verify the displayed flow rather than assuming labels are stable.
2. Scan/discover tools, complete OAuth with the current operator's development account, and create the private development app. **Publication is not required** for this test.
3. After schema, tool, auth, or UI metadata changes, use the app/connection **Refresh** flow, verify the advertised metadata changed, and start a **new conversation**. For breaking UI asset changes, version the resource URI to avoid stale resources. Ask the developer if server reload is needed; do not restart it yourself.

## Optional minimal implementation guideline (not existing prototype behavior)

The existing `list_sessions` tool can return only the authenticated operator's authorized development sessions. A proposed UI can render those results; inspect the implementation before treating any UI as existing behavior. Never return cookies, tokens, raw session credentials, or other users' data.

Associate the rendering tool with a registered UI resource using `_meta.ui.resourceUri`, served as `text/html;profile=mcp-app`. Render from `structuredContent` via the MCP Apps bridge (`ui/initialize`, `ui/notifications/tool-result`, JSON-RPC over `postMessage`), validating host messages and data. Keep the tool useful without UI. Use narrow resource/CSP allowlists, not a broad iframe exposing the application or debugger.

An optional **Refresh** button can call the read-only tool through bridge `tools/call` and render its new result; this is separate from ChatGPT's metadata Refresh. Otherwise provide a real non-destructive interaction such as selecting a row or expanding details. Do not claim a working button/bridge until exercised in ChatGPT.

## Mandatory acceptance

Acceptance is the actual sequence in **ChatGPT web**, in the current operator's target account/workspace:

1. Link their Firmowid development account through the actual OAuth flow.
2. Start a new conversation with the development app selected and submit a representative prompt.
3. Observe ChatGPT invoking the intended MCP tool with valid arguments and receiving authorized results.
4. Observe the embedded UI rendering those results, including empty/error handling where relevant.
5. Perform a visible UI interaction and verify the expected state/result change (and tool round trip if the interaction calls a tool).

Record non-sensitive evidence of the prompt, tool selected, UI result, interaction, and any blocked gate. Do not capture auth URLs with codes, tokens, cookies, or private data. MCP Inspector, API calls, Codex, unit tests, and tunnel readiness are useful diagnostics **but none substitutes for this acceptance**. If ChatGPT/browser access is unavailable, say acceptance remains unverified; do not report demo completion.

## Official references

- [Pinned v0.0.15 README: runtime keys and foreground client](https://github.com/openai/tunnel-client/blob/v0.0.15/README.md).
- [Pinned v0.0.15 configuration: env/flags, OAuth rewriting and trust boundaries](https://github.com/openai/tunnel-client/blob/v0.0.15/docs/configuration.md).
- [Secure MCP Tunnel: permissions, workspace association and OAuth boundaries](https://developers.openai.com/api/docs/guides/secure-mcp-tunnels).
- [Developer mode: Apps Create, plan/workspace permissions and private testing](https://help.openai.com/en/articles/12584461-developer-mode-apps-and-full-mcp-connectors-in-chatgpt-beta).
- [Connect and test: metadata refresh and new conversations](https://developers.openai.com/apps-sdk/deploy/connect-chatgpt).
- [Authentication: canonical resource, issuer, PKCE and callbacks](https://developers.openai.com/apps-sdk/build/auth).
- [MCP Apps UI: resource metadata, structured results and bridge](https://developers.openai.com/apps-sdk/build/chatgpt-ui).

Infisical syntax was checked against installed `infisical secrets get --help`, including `--secret-overriding=false`; no secrets were retrieved. Upstream web documentation may evolve independently of the pinned client. Recheck installed help and current workspace UI before use.
