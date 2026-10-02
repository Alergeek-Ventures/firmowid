---
name: infisical-secrets
description: Use an already-migrated Alergeek Infisical setup safely during local development, scripts, curl requests, debugging, and deployments without exposing secrets in logs or chat.
---

# Infisical Secrets Usage

Use this skill when working in a repository that has already been migrated to the Alergeek Infisical setup.

This skill is for day-to-day usage, not migration. For migration, use `commands/av-infisicalize-migrate.md`.

## Core Rules

- Treat every value from Infisical as sensitive unless it is clearly a non-secret config value.
- Never print, log, paste, summarize, or expose secret values.
- Never dump the environment with bare `env`, `printenv`, `set`, `export`, `export -p`, or framework debug commands that dump process env. Exporting specifically required variables to a child process is allowed; never display their values.
- Disable shell tracing with `set +x` before secret access. Never use xtrace (`set -x`), credential logging, or environment/config dumps while secrets are present.
- Prefer fetching only the exact variable needed instead of loading the whole environment when making one-off requests.
- Use shell variables to pass secrets to commands, but do not display those variables.
- If you need to verify a secret exists, verify by command success, variable presence, or length only. Do not reveal the value.
- Do not write fetched secrets into tracked files.
- Do not add real secrets to `.env`, `.env.worktree`, README files, issue comments, logs, test snapshots, or generated artifacts.

## Firmowid Elixir Workflow

- Run normal `mix ...` commands. Do not wrap Mix commands with `infisical run`, dotenvx, mise, npm, pnpm, or shell wrappers unless this repository later standardizes on that pattern.
- `config/dev.exs` and `config/test.exs` automatically load Infisical `dev` secrets from `/app` before local config reads environment variables.
- `.env.worktree` is the local worktree override file and wins over Infisical values.
- Use `AV_SKIP_INFISICAL=1` only for emergency or offline local workflows.
- Never dump the full environment or secret values while debugging.
- Production env is handled by GitHub Actions and Coolify deployment sync, not by runtime Infisical loading in the application container.

## Alergeek Infisical Context

- Infisical URL: `https://infisical.alergeek.me`
- All example commands include `--domain https://infisical.alergeek.me` to target the self-hosted instance. Omit it only if your CLI is already logged into this domain or the project has `.infisical.json` configured.
- Projects normally have at least `dev` and `prod` environments.
- Local development should use Infisical as the source of shared env values.
- App runtime secrets and variables live under `/app` in each environment.
- `.env.worktree` is allowed for local worktree-specific overrides and should stay untracked.
- Personal long-term overrides should usually live in Infisical personal overrides, not in project files.

## Firmowid Development Namespace

Use the **Firmowid project**, Infisical environment **`dev`**:

| Folder | Purpose |
| --- | --- |
| `/app` | Application runtime secrets and configuration; loaded by local Elixir config. |
| `/dev/<tool>` | Shared development-tool credentials/configuration, separate from app runtime. |
| `/dev/openai-tunnel` | Shared OpenAI Secure MCP Tunnel runtime values for ChatGPT app testing. |

The environment `dev` (`--env=dev`) and folder `/dev` (`--path=...`) are different concepts. Do not move, rename, or duplicate existing secrets as part of using this convention.

The optional **non-secret** `CHATGPT_OAUTH_RESOURCE_URL` belongs only in the
isolated current worktree's **untracked `.env.worktree`**, applied last by the
existing app loader. **Never insert it into shared Infisical dev `/app`**: that
folder is loaded by all developers/worktrees, and approval covers only this
worktree. The operator writes the exact observed HTTPS tunnel resource URL;
do not guess it or duplicate transport credentials into `/app`. Before an agent
edit, verify `.env.worktree` is git-ignored; if safety tooling blocks access, stop
and ask the user to add the non-secret line without bypassing the block. Runtime
config reads/strictly validates this URL only in dev; test and prod ignore it.
This approved temporary ChatGPT/Tidewave-only worktree override changes the
shared product MCP canonical resource/audience, including existing `/mcp`
clients in this worktree, without rewriting incoming resource parameters. No shared
Infisical key, second environment
or production secrets are needed. The user must restart the app after changing
it: hot code reload does not rerun runtime config or Infisical loading. Agents
must not restart the app/tunnel. See the prototype README for exact validation
and DCR rather than incompatible 0.3.1 CIMD guidance.

The required exact names in `/dev/openai-tunnel` are:

- `CONTROL_PLANE_API_KEY`: an OpenAI **runtime** API key whose principal has Tunnels **Read + Use**. It is not an admin key; do not substitute `OPENAI_ADMIN_KEY` or an unrelated account key.
- `CONTROL_PLANE_TUNNEL_ID`: the shared tunnel identifier.

Fetch each by exact name with `infisical secrets get NAME --domain https://infisical.alergeek.me --env=dev --path=/dev/openai-tunnel --plain --secret-overriding=false`. Capture output into a variable, never run this as a value-printing command. Disabling personal overrides selects the shared values; check installed `infisical secrets get --help` before use and stop if the option is unsupported.

For the foreground run, operator handoff, OAuth checks, and actual ChatGPT acceptance flow, load the sibling `chatgpt-app-testing` skill. Neither folder contents nor live tunnel access have been verified by this documentation.

## One-Off Secret Access

For one-off commands, fetch only the needed variable into a shell variable:

```sh
TOKEN=$(infisical get API_TOKEN --domain https://infisical.alergeek.me --env=dev --path="/app" --plain)
```

Then pass it to the command without printing it:

```sh
curl -sS \
  -H "Authorization: Bearer $TOKEN" \
  https://example.com/api/endpoint
```

After the command, unset the variable if the shell session may continue:

```sh
unset TOKEN
```

Never do this:

```sh
echo "$TOKEN"
infisical get API_TOKEN --domain https://infisical.alergeek.me --env=dev --path="/app" --plain
curl -v -H "Authorization: Bearer $TOKEN" https://example.com/api/endpoint
```

`curl -v` can expose headers. Avoid verbose/debug output when secrets are present.

## Curl Requests

When making authenticated `curl` requests:

- Fetch the credential into a shell variable.
- Use `-sS` unless debugging transport issues.
- Do not use `-v`, `--trace`, or `--trace-ascii` with secret headers.
- Do not include credentials directly in the command line if they would appear in shell history, logs, or process listings.
- Prefer headers over query parameters for tokens.
- If a response might contain secrets, save it to a local ignored file or inspect only non-sensitive fields.

Example:

```sh
API_TOKEN=$(infisical get API_TOKEN --domain https://infisical.alergeek.me --env=dev --path="/app" --plain)
curl -sS \
  -H "Authorization: Bearer $API_TOKEN" \
  -H "Content-Type: application/json" \
  https://example.com/api/health
unset API_TOKEN
```

## Variables vs Secrets

Infisical can contain both ordinary configuration variables and secrets.

- Variables are non-sensitive operational config, such as feature flags, public URLs, environment names, or non-secret IDs.
- Secrets are credentials, tokens, passwords, private keys, API keys, database URLs with credentials, webhook secrets, signing secrets, and anything that grants access.
- If unsure, treat the value as a secret.
- Even non-secret variables can reveal infrastructure details, so avoid dumping the full environment.

## `.env.worktree` Usage

Use `.env.worktree` for local-only overrides, such as:

- local ports
- local database names
- temporary feature flags
- sandbox endpoints
- personal non-shared development values

Do not use `.env.worktree` for secrets that should be shared or rotated centrally. Put those in Infisical instead.

`.env.worktree` should be ignored by git. If it is not ignored, add it to `.gitignore` before using it.

## Verifying Values Without Revealing Them

To verify that a value exists without printing it:

```sh
VALUE=$(infisical get API_TOKEN --domain https://infisical.alergeek.me --env=dev --path="/app" --plain)
test -n "$VALUE"
unset VALUE
```

To verify approximate shape without exposing the value, only report metadata:

```sh
VALUE=$(infisical get API_TOKEN --domain https://infisical.alergeek.me --env=dev --path="/app" --plain)
printf 'API_TOKEN is set, length=%s\n' "${#VALUE}"
unset VALUE
```

Do not reveal prefixes, suffixes, partial tokens, or decoded payloads unless the user explicitly confirms that the value is non-sensitive.

## Agent Workflow

When a user asks to run a command that needs env values:

1. Check whether the repo already has an Infisical setup, such as `.infisical.json`, README instructions, or deployment workflows.
2. Identify the minimum variables needed for the task.
3. Use plain `mix ...` commands for this Elixir app; config loads Infisical automatically in local `:dev` and `:test`.
4. Use `VAR=$(infisical get VAR --domain https://infisical.alergeek.me --env=dev --path="/app" --plain)` for one-off commands needing only one or a few values.
5. Avoid command modes that print request headers, environment variables, credentials, or full configs.
6. Redact any accidental secret-looking output before summarizing to the user.
7. Unset shell variables after use when practical.

## Production Safety

Production secrets require extra care.

- Do not fetch or use `prod` secrets unless the user explicitly asked for production or the task clearly requires it.
- Prefer read-only or low-impact operations for production debugging.
- Avoid writing production secrets into local files.
- Do not run destructive production commands without explicit confirmation.
- Do not paste production values into chat, logs, tickets, or commit messages.

## Deployment Notes

For migrated repositories, production deployment usually happens through GitHub Actions using the private `Alergeek-Ventures/av-secret-service/coolify-deploy` action.

Agents normally should not manually copy production env values from Infisical to deployment platforms. The deployment action is responsible for fetching Infisical env values, syncing them to Coolify, deploying, and polling status.

If a deployment needs new variables:

- Add shared values to the correct Infisical project and environment.
- Use personal overrides only for personal development behavior.
- Use GitHub environment variables/secrets only for deployment integration credentials, such as the Infisical machine identity ID, Coolify token, and Coolify app UUID.

## Redaction

If command output includes secret-looking data, do not repeat it. Replace it with `[REDACTED]` in summaries.

Secret-looking data includes:

- bearer tokens
- API keys
- JWTs
- passwords
- database URLs with credentials
- private keys
- webhook signing secrets
- OAuth client secrets
- session cookies

When in doubt, redact.
