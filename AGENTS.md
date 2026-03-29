# Firmowid agent's instructions

This document contains instructions for AI agents working on this codebase.

This is an Elixir LiveView app. It is focused on invoicing, bank accounts synchronization,
and other tasks related to company management, like payroll or client's billing.

## Development server

When running, assume that the whole application - with all required services -
is properly running. We use `wt` (`worktrunk`) to maintain each worktree.
Parallel worktrees are running on the same host, so we use different ports.
They are stored in `.env.local` and `.server.port` files and are used by
development scripts.

**Accessing the dev server:**

- Check `.server.port` for the port number - for example: `http://localhost:16423`
- Use `kira@bytecraft.collective` / `kolejka123456` as credentials (look at
  `seeds.exs` if in doubt)
- Visit `/development` for the full seed data guide

**Local setup:**

- `mix dev.up` - starts services, reads config from `.env.local` (or uses defaults)
- `mix dev.down` - stops services
- Worktrunk generates `.env.local` with hashed ports for feature branches

Tidewave MCP should be available, allowing you to inspect the running system.
If not - flag that instantly. It's the best way to debug so if it's missing
**it's a huge issue.**

Do not start own servers or restart. Ask the user to do that if something is
malfunctioning. You can by mistake kill other worktrees / your MCPs / your
process running on this machine.

## Use git

Before starting the work, ask user if they want you to commit the changes.
If they say so, after each successful, atomic change - commit it.
Make sure it works and is correct before doing so. Instructions below.

## Manual testing and good will

While we employ a bunch of tools to analyze code and catch bugs early, it's
still important to test your changes manually. This is especially true for
changes that affect the user interface or are introducing something new.

Always go above and beyond to make sure that that whoever comes after you
understands what you've done, that it works and that it's correct.

## Automated Tests

They have value, and we have these in our codebase, as part of our validation suite.
They have to be super fast, test critical paths for regressions.

Do not **overtest**. Discuss with users about testing; we never want to be held back
by outdated / inflexible tests.

## Automated Test File Location

Tests are colocated with the code they test — placed as close to the source files as
possible inside `lib/`, not in a separate `test/` tree. This is followed across the
entire codebase. Example: tests for `lib/firmowid/ash/finances/transaction.ex` live
at `lib/firmowid/ash/finances/finances_test.exs`.

## Code Quality Verification

Before submitting changes, always run the quality checks:

```bash
mix check
```

This single command runs all quality checks in order:

1. `mix compile --warnings-as-errors` - Compile with strict warnings
2. `mix format --check-formatted` - Verify code formatting  
3. `mix credo --strict` - Static code analysis
4. `mix sobelow --config` - Security vulnerability scanning
5. `mix test` - Run test suite

All checks must pass before changes can be merged.

## Code Style Guidelines

### Module Documentation

- All modules must have `@moduledoc` describing their purpose
- Public functions should have `@doc` and `@spec`

### Credo Rules

- Keep function nesting depth <= 2 (extract helper functions)
- Keep cyclomatic complexity <= 9 (use maps/pattern matching instead of long case/cond)
- Sort aliases alphabetically
- Use `if/else` instead of `cond` with single condition
- Avoid `apply/3` when argument count is known (use direct calls or helper functions)
- No TODO/FIXME comments (convert to issues or remove)

### Sobelow

- All issues from Sobelow must be fixed
- Never skip rules via config - use `# sobelow_skip` comments with explanations
- When adding a skip comment, always explain WHY it's safe:

```elixir
# sobelow_skip ["Traversal.FileModule"]
# file_path comes from scanning the project directory (filtered through gitignore),
# not from user-controlled web input. This is a CLI tool indexing local files.
defp read_file(file_path) do
  File.read(file_path)
end
```

- Try to refactor code to avoid violations when possible
- Common false positives in this codebase:
  - `Traversal.FileModule` - File operations on project files (not web input)
  - `SQL.Query` - Hardcoded SQL with parameterized user input

## Files That Must Never Be Committed

Any sort of runtime data should be ignored. Preferably, we use a temporary
directory for such purposes, given to us by the framework / language / library,
that auto deletes itself after use.

If not, `.gitignore` and clean it up afterwards.

If you accidentally stage any of these files, unstage them immediately.
Never modify `.gitignore` to allow committing runtime data.

## Never leave repository boundaries

Everything should be contained within the repository. Only other directory
allowed is a temporary one - but then you should go through language / library.
Installing external dependencies shouldn't happen globally and should be
reproducible - note it down in README and PROGRESS.

E.g. installing `osgrep` - not via `npm install -g` but rather create a new
folder, gitignore it, install via local `npm install`. Write down the documentation
in README (benchmarking section).

<!-- usage-rules-start -->
<!-- phoenix:ecto-start -->
## phoenix:ecto usage
[phoenix:ecto usage rules](deps/phoenix/usage-rules/ecto.md)
<!-- phoenix:ecto-end -->
<!-- phoenix:html-start -->
## phoenix:html usage
[phoenix:html usage rules](deps/phoenix/usage-rules/html.md)
<!-- phoenix:html-end -->
<!-- phoenix:liveview-start -->
## phoenix:liveview usage
[phoenix:liveview usage rules](deps/phoenix/usage-rules/liveview.md)
<!-- phoenix:liveview-end -->
<!-- phoenix:phoenix-start -->
## phoenix:phoenix usage
[phoenix:phoenix usage rules](deps/phoenix/usage-rules/phoenix.md)
<!-- phoenix:phoenix-end -->
<!-- usage_rules:elixir-start -->
## usage_rules:elixir usage
[usage_rules:elixir usage rules](deps/usage_rules/usage-rules/elixir.md)
<!-- usage_rules:elixir-end -->
<!-- usage_rules:otp-start -->
## usage_rules:otp usage
[usage_rules:otp usage rules](deps/usage_rules/usage-rules/otp.md)
<!-- usage_rules:otp-end -->
<!-- usage-rules-end -->
