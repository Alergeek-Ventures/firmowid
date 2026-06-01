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
- Never run commands that would echo all environment variables, such as `env`, `printenv`, `set`, `export`, or framework debug commands that dump process env.
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
