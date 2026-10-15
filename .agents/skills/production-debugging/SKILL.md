---
name: production-debugging
description: Use when the user reports a bug, crash, log, Sentry issue or data problem from production, or asks for queries or IEx commands to run on production.
---

# Production debugging

- Tidewave, the local database and the local logs show only the current
  worktree's development environment. They never show production data or
  production behavior. A local reproduction is a hypothesis until production
  evidence supports it.
- Production evidence comes from what the user pastes (logs, psql output, IEx
  results) and from Sentry and PostHog. In opencode, use the `sentry` and
  `posthog` subagents, which have the production MCPs; elsewhere ask the user.
- Name the evidence that ties a proposed fix to production before recommending
  it. When it does not match the code, look for release-only differences:
  runtime configuration and environment variables, paths resolved at compile
  time instead of runtime (for example under `priv`), tenant data that seeds do
  not cover.
- When production data is needed, give the user commands to run instead of
  querying local data:
  - IEx commands on a single line: no line starting with `|>`, separate
    statements with `;`. Multi-line pipes submit early and break when pasted.
  - Read-only by default. Mark anything that writes and explain its effect
    before the command.
  - Select readable columns (names, numbers, dates) next to ids so the output
    can be judged without further lookups.
