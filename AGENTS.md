# Firmowid agent's instructions

This document contains instructions for AI agents working on this codebase.

This is an Elixir LiveView app. It is focused on invoicing, bank accounts synchronization,
and other tasks related to company management, like payroll or client's billing.

## Worktree autonomy

Within the agreed task, you have full autonomy to edit files, modify local
application data, and start, stop, or restart the development server without
separate approval. Stay within your current worktree and its dedicated local
services. Do not interfere with other worktrees or their processes, data, and
services.

Use `mix dev.status` to display the current worktree's service endpoints and
check their health before deciding whether a restart is needed.

Use `mix dev.down` and `mix dev.up` to restart the development environment.
This clears the worktree's local database; `mix dev.up` automatically recreates
it and runs the seeds. Any data not included in the seeds will be lost.

Tidewave MCP always targets your current worktree. Use it as the primary tool
for runtime inspection and debugging. Temporary unavailability during a restart
is expected; report it if the connection remains unavailable after startup.

## Local access and seed data

The local database is seeded by default, so sample accounts and data are
available for development and manual testing.

- Sign in with `kira@bytecraft.collective` / `kolejka123456`.
- Visit `/development` in the application for the full seed data guide.

## Use git

Complete the work and verify it first, then ask the user whether to commit the
resulting changes. Do not ask about committing before starting the work, and do
not decide to commit on your own. Commit only after the user explicitly approves.

All commit messages must follow **Conventional Commits (Angular variant)**:

- required format: `<type>(<scope>): <subject>`
- `scope` is optional
- do not use merge commits (`Merge branch ...`) - they are blocked in CI

Examples:

- `feat(payroll): add monthly summary action`
- `fix: prevent duplicate invoice import`
- `chore(ci): enforce conventional commits in workflow`

## Manual testing and good will

While we employ a bunch of tools to analyze code and catch bugs early, it's
still important to test your changes manually. This is especially true for
changes that affect the user interface or are introducing something new.

Always go above and beyond to make sure that whoever comes after you
understands what you've done, that it works and that it's correct.

For example, after changing an invoice form, open the application in a browser
and click through the affected flow as a real user: fill in the form, submit it,
check validation messages, and verify the saved invoice. Use browser interaction
to validate the behavior, not just compilation or automated tests.

## Automated Tests

They have value, and we have these in our codebase, as part of our validation suite.
They have to be super fast, test critical paths for regressions.

Do not **overtest**. Discuss with users about testing; we never want to be held back
by outdated / inflexible tests.


## Migrations Policy (Ash only)

Schema migrations must be managed through Ash/AshPostgres migration tooling.

- Use Ash migration/codegen flow (`mix ash.codegen`, `mix ash.migrate`, and
  underlying `mix ash_postgres.generate_migrations`).
- Do **not** generate direct Ecto migrations (`mix ecto.gen.migration`) in normal work.
- Direct/manual Ecto migrations are allowed only in emergency incidents when Ash
  tooling cannot express the change in time.
- Every emergency manual migration must be explicitly documented in PR/commit notes,
  with reason and follow-up plan to return to Ash-managed schema changes.

## Code Quality Verification

Use verification to get fast feedback while working and establish confidence in
the integrated change before submitting it:

- During the local edit loop, use `mix check --quick`. It keeps strict compilation,
  inexpensive checks and tests, but skips costly type analysis and translation
  extraction. It is feedback, not final verification.
- For a narrow change or a failing check, run the relevant task or focused test
  directly (for example `mix test lib/path/to/feature_test.exs`). Fix the cause
  before repeating the broader verification.
- Before submitting changes, run the full verification:

```bash
mix check
```

> Do not `tail` or `grep` the output - it's super compact, specifically for agents.

All full checks must pass before changes can be merged. Verification does not
auto-format source files; fix formatting explicitly. Timings and failure output
identify what needs attention, and skipped checks are not evidence of success.
Use `--no-test` only when tests are verified separately. Tests calling real
external APIs are excluded by default; include them deliberately with
`mix check --external` when credentials and external services are available.

## Code Style Guidelines

### Frontend architecture conventions (`lib/firmowid_web`)

- **Directory path = module namespace** (`FirmowidWeb.X.Y.Z` lives in
  `lib/firmowid_web/x/y/z.ex`).
- Prefer a **feature-first layout** with standard subfolders:
  `views/`, `components/`, `controllers/`, `utilities/`.
- Keep dependencies directional: nested/child features may depend on shared
  parent feature modules, but avoid cross-sibling dependencies.
- Keep these conventions enforceable in practice (Credo + code review), and
  always finish refactors with `mix check`.

### User-facing URL language

- User-facing pathnames, query param keys, and human-readable query values must be
  **Polish**.
- Technical/internal endpoints may stay technical when they are not part of the
  product UX (for example auth internals, admin routes, health checks, or external
  callback payloads).
- Keep canonical feature URLs in feature-owned navigation modules (for example
  `FirmowidWeb.Invoicing.Navigation`).
- Put shared parsing/encoding mechanics in `FirmowidWeb.Infrastructure.Utilities.*`.
- Do not add compatibility aliases or English fallbacks unless the user explicitly
  asks for a staged migration.

### Pure Elixir Files Preference

Avoid writing `.heex` templates. Sometimes, it's unavoidable, but prefer Elixir
files, as they have access to Credo and will be linted / checked more rigorously.

### Automated Test File Location

Tests are colocated with the code they test — placed as close to the source files as
possible inside `lib/`, not in a separate `test/` tree. This is followed across the
entire codebase. Example: tests for `lib/firmowid/ash/finances/transaction.ex` live
at `lib/firmowid/ash/finances/finances_test.exs`.

### Module Documentation

- All modules must have `@moduledoc` describing their purpose
- Public functions should have `@doc` and `@spec`

### Sobelow

- All issues from Sobelow must be fixed - if it's a false positive, explain why
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

# Documentation

Always strive to use libraries, frameworks and packages in an optmial way.
Follow best practices, good patterns and refactor code that's not doing that.

## Online

Use available tools or navigate to the documentation on websites. Verify APIs
for the used versions of packages, check cookbooks, guides and examples to make
sure you're "holding it right".

## Usage rules

These are linked to installed dependencies, so should be exactly matching to
the code you write.

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
<!-- ash-start -->
## ash usage
_A declarative, extensible framework for building Elixir applications._

[ash usage rules](deps/ash/usage-rules.md)
<!-- ash-end -->
<!-- ash:actions-start -->
## ash:actions usage
[ash:actions usage rules](deps/ash/usage-rules/actions.md)
<!-- ash:actions-end -->
<!-- ash:aggregates-start -->
## ash:aggregates usage
[ash:aggregates usage rules](deps/ash/usage-rules/aggregates.md)
<!-- ash:aggregates-end -->
<!-- ash:authorization-start -->
## ash:authorization usage
[ash:authorization usage rules](deps/ash/usage-rules/authorization.md)
<!-- ash:authorization-end -->
<!-- ash:calculations-start -->
## ash:calculations usage
[ash:calculations usage rules](deps/ash/usage-rules/calculations.md)
<!-- ash:calculations-end -->
<!-- ash:code_interfaces-start -->
## ash:code_interfaces usage
[ash:code_interfaces usage rules](deps/ash/usage-rules/code_interfaces.md)
<!-- ash:code_interfaces-end -->
<!-- ash:code_structure-start -->
## ash:code_structure usage
[ash:code_structure usage rules](deps/ash/usage-rules/code_structure.md)
<!-- ash:code_structure-end -->
<!-- ash:data_layers-start -->
## ash:data_layers usage
[ash:data_layers usage rules](deps/ash/usage-rules/data_layers.md)
<!-- ash:data_layers-end -->
<!-- ash:exist_expressions-start -->
## ash:exist_expressions usage
[ash:exist_expressions usage rules](deps/ash/usage-rules/exist_expressions.md)
<!-- ash:exist_expressions-end -->
<!-- ash:generating_code-start -->
## ash:generating_code usage
[ash:generating_code usage rules](deps/ash/usage-rules/generating_code.md)
<!-- ash:generating_code-end -->
<!-- ash:migrations-start -->
## ash:migrations usage
[ash:migrations usage rules](deps/ash/usage-rules/migrations.md)
<!-- ash:migrations-end -->
<!-- ash:query_filter-start -->
## ash:query_filter usage
[ash:query_filter usage rules](deps/ash/usage-rules/query_filter.md)
<!-- ash:query_filter-end -->
<!-- ash:querying_data-start -->
## ash:querying_data usage
[ash:querying_data usage rules](deps/ash/usage-rules/querying_data.md)
<!-- ash:querying_data-end -->
<!-- ash:relationships-start -->
## ash:relationships usage
[ash:relationships usage rules](deps/ash/usage-rules/relationships.md)
<!-- ash:relationships-end -->
<!-- ash:testing-start -->
## ash:testing usage
[ash:testing usage rules](deps/ash/usage-rules/testing.md)
<!-- ash:testing-end -->
<!-- ash_postgres-start -->
## ash_postgres usage
_The PostgreSQL data layer for Ash Framework_

[ash_postgres usage rules](deps/ash_postgres/usage-rules.md)
<!-- ash_postgres-end -->
<!-- ash_postgres:advanced_features-start -->
## ash_postgres:advanced_features usage
[ash_postgres:advanced_features usage rules](deps/ash_postgres/usage-rules/advanced_features.md)
<!-- ash_postgres:advanced_features-end -->
<!-- ash_postgres:best_practices-start -->
## ash_postgres:best_practices usage
[ash_postgres:best_practices usage rules](deps/ash_postgres/usage-rules/best_practices.md)
<!-- ash_postgres:best_practices-end -->
<!-- ash_postgres:check_constraints-start -->
## ash_postgres:check_constraints usage
[ash_postgres:check_constraints usage rules](deps/ash_postgres/usage-rules/check_constraints.md)
<!-- ash_postgres:check_constraints-end -->
<!-- ash_postgres:configuration-start -->
## ash_postgres:configuration usage
[ash_postgres:configuration usage rules](deps/ash_postgres/usage-rules/configuration.md)
<!-- ash_postgres:configuration-end -->
<!-- ash_postgres:custom_indexes-start -->
## ash_postgres:custom_indexes usage
[ash_postgres:custom_indexes usage rules](deps/ash_postgres/usage-rules/custom_indexes.md)
<!-- ash_postgres:custom_indexes-end -->
<!-- ash_postgres:custom_sql_statements-start -->
## ash_postgres:custom_sql_statements usage
[ash_postgres:custom_sql_statements usage rules](deps/ash_postgres/usage-rules/custom_sql_statements.md)
<!-- ash_postgres:custom_sql_statements-end -->
<!-- ash_postgres:foreign_keys-start -->
## ash_postgres:foreign_keys usage
[ash_postgres:foreign_keys usage rules](deps/ash_postgres/usage-rules/foreign_keys.md)
<!-- ash_postgres:foreign_keys-end -->
<!-- ash_postgres:migrations-start -->
## ash_postgres:migrations usage
[ash_postgres:migrations usage rules](deps/ash_postgres/usage-rules/migrations.md)
<!-- ash_postgres:migrations-end -->
<!-- ash_postgres:multitenancy-start -->
## ash_postgres:multitenancy usage
[ash_postgres:multitenancy usage rules](deps/ash_postgres/usage-rules/multitenancy.md)
<!-- ash_postgres:multitenancy-end -->
<!-- usage_rules:elixir-start -->
## usage_rules:elixir usage
[usage_rules:elixir usage rules](deps/usage_rules/usage-rules/elixir.md)
<!-- usage_rules:elixir-end -->
<!-- usage_rules:otp-start -->
## usage_rules:otp usage
[usage_rules:otp usage rules](deps/usage_rules/usage-rules/otp.md)
<!-- usage_rules:otp-end -->
<!-- usage-rules-end -->
