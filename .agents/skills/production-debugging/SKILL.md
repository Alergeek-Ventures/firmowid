---
name: production-debugging
description: Use when the user reports a bug, crash, log, Sentry issue or data problem from production, or asks for queries or IEx commands to run on production.
---

# Production debugging

- Tidewave, the local database and the local logs show only the current
  worktree's development environment. They never show production data or
  production behavior. A local reproduction is a hypothesis until production
  evidence supports it.
- Production evidence comes from the anonymized production database MCP, the
  Sentry and PostHog MCP tools and what the user pastes (logs, psql output,
  IEx results). Look for the MCP tools first, also under a `gw-` prefix
  (`gw-firmowid-anonymized`, `gw-sentry`, `gw-posthog`); ask the user only for
  what they cannot reach.
- The anonymized MCP (`gw-firmowid-anonymized`, `anonimized-mcp` in
  `opencode.json`) runs one read-only `SELECT` on the production database and
  replaces personal data with stable aliases such as `NAME_k3j7x2ab`:
  - Start with `list_sources`, then `describe_schema` for the source. Oban
    tables live in the `oban` schema (`oban.oban_jobs`); `errors` is
    `jsonb[]`, so the last attempt is
    `errors[array_length(errors, 1)]->>'error'`, and `meta` holds the job's
    summary.
  - Masking can also hit technical text, such as module names or short enum
    values (`zal`). Literals in the query are not masked, so confirm a value
    behind an alias with a comparison: `SELECT invoice_type = 'zal' AS is_zal …`
    or `WHERE worker = 'Firmowid.Ksef.Workers.FetchWorker'`.
  - File contents in S3, such as the KSeF XML behind `blobs.blob_path`, are
    not reachable through it; ask the user for a file when the evidence you
    need is only there.
- Name the evidence that ties a proposed fix to production before recommending
  it. When it does not match the code, look for release-only differences:
  runtime configuration and environment variables, paths resolved at compile
  time instead of runtime (for example under `priv`), tenant data that seeds do
  not cover.
- When production data is needed beyond these tools, give the user commands to
  run instead of querying local data:
  - IEx commands on a single line: no line starting with `|>`, separate
    statements with `;`. Multi-line pipes submit early and break when pasted.
  - Read-only by default. Mark anything that writes and explain its effect
    before the command.
  - Select readable columns (names, numbers, dates) next to ids so the output
    can be judged without further lookups.
