# Ash Framework Migration Plan

Status: **In Progress — Phase 2 (Payroll domain extracted, continuing Timetracker actions)** | Last updated: 2026-03-26

## Goal

Migrate Firmowid from plain Phoenix/Ecto to Ash-native, incrementally.
Timetracker (Czasosledz) is the beachhead domain. The north star motivator is
AshAI + MCP — letting employees and integrations interact with the app via AI
agents that respect the same authorization and tenancy rules as the web UI.

## Why Ash

1. **Authorization propagates to MCP.** Ash policies defined on resources are
   automatically enforced when AshAI exposes those resources as MCP tools. An
   AI agent calling `start_session` goes through the exact same policy checks
   as a LiveView form submission. No duplicate auth logic.
2. **Declarative domain modeling.** Actions, validations, calculations, and
   policies live on the resource. The 1,251-line `Firmowid.Timetracker` context
   module decomposes into focused, testable pieces.
3. **Built-in multitenancy.** Ash's `attribute` strategy is a direct replacement
   for our `Repo.prepare_query/3` pattern — automatic `WHERE organization_id = ?`
   on every query, automatic attribute setting on create.
4. **AshPhoenix forms.** Replaces manual changeset wiring in LiveViews. Nested
   forms, validation, and error handling come for free.

## Current Architecture (pre-Ash)

### Stack

- Phoenix 1.8, LiveView 1.1.27, Ecto SQL 3.11, Postgrex, Bandit
- ~26 Ecto schemas across ~10 Phoenix contexts
- No Ash dependencies today

### Patterns

| Pattern | Implementation |
|---------|---------------|
| Multi-tenancy | Process-dict `organization_id` via `Repo.put_org_id/1`. `Repo.prepare_query/3` injects `WHERE organization_id = ?` into every query. |
| Authorization | Bodyguard (`@behaviour Bodyguard.Policy` per context). `authorize/3` function clauses check user role + resource ownership. LiveViews call `Bodyguard.permit!/3`. |
| Primary keys | UUIDv7 everywhere via `Firmowid.Schema` macro (`@primary_key {:id, UUIDv7.Type, autogenerate: true}`). |
| Foreign keys | `@foreign_key_type :binary_id` |
| Timestamps | `@timestamps_opts [type: :utc_datetime]` |
| Tenant setting | `on_mount` hook and plug both call `Repo.put_org_id(user.organization_id)` after auth. |
| Tests | Co-located in `lib/**/*_test.exs` (enabled by `test_paths: ["lib"]`). |

### Context Map

```
Firmowid.Accounts         - Users, Organizations, Auth, Invites
Firmowid.Timetracker      - Sessions, Projects, ProjectUsers, HoursRecord
Firmowid.Payroll           - UserSalary (extracted from Timetracker — salary is HR/payroll, not time-tracking)
Firmowid.Management       - Admin read-layer over Timetracker + Accounts
Firmowid.SalesInvoices     - Sales invoices, items, counterparties, KSeF
Firmowid.CostInvoices      - Cost invoices, inbound email, OCR enrichment
Firmowid.Invoicing         - Invoice-transaction matching, AI assistant
Firmowid.Finances          - Bank accounts, transactions
Firmowid.BankData          - GoCardless/Nordigen sync
Firmowid.Analysis          - Financial tagging
Firmowid.Blobs             - S3 file storage
Firmowid.Billing           - Org limits, usage tracking
Firmowid.Currencies        - Exchange rates (NBP)
Firmowid.KSeF              - Polish e-invoicing system
```

### Timetracker Dependency Graph

Timetracker is relatively standalone but not perfectly isolated:

```
Firmowid.Timetracker
  reads from:
    Firmowid.Accounts.User
    Firmowid.Accounts.Organization
  writes to:
    Firmowid.Analysis.TagDefinition  (project create/update/delete syncs tags)
  optional FK:
    Firmowid.SalesInvoices.Counterparty  (on Project)
    Firmowid.Blobs.Blob                  (on HoursRecord)

Firmowid.Management
  reads from Timetracker:
    Session, HoursRecord, UserSalary  (direct Ecto queries)
```

This means converting Timetracker to Ash requires thin Ash wrappers for User,
Organization, Counterparty, TagDefinition, and Blob so that Ash resources can
reference them in `relationships do ... end`.

### User-Organization Relationship

- `users.organization_id` is **nullable**. Users exist without an org during
  onboarding.
- `Organization` has `belongs_to :owner, User` and `has_many :users, User`.
- All auth queries use `skip_organization_id: true` — they operate outside
  tenant scope.
- Tenant is set **after** auth succeeds, from `user.organization_id`.

**Implication:** User and Organization cannot have mandatory attribute
multitenancy. They are the identity layer that sits above tenancy.

### Callers of `Firmowid.Timetracker` (context module)

Mapped during planning to understand the scope of the cutover:

| Caller | What it uses |
|--------|-------------|
| 6 LiveViews (timetracker, project, hours_record) | CRUD: start/end/update/delete session, create/update/delete/archive project, create hours record, list functions |
| 4 Management LiveViews | `get_project`, `get_project_users_with_cost`, `create_user_salary`, `get_user_salary_as_of`, `get_hours_record_by_month` |
| `Management` context module | `Timetracker.user_salaries_as_of_query/1`, `Timetracker.create_user_salary/1`, `Timetracker.get_user_salary_as_of/2`, `Timetracker.get_hours_record_by_month/2`, and direct Ecto queries on `Session`, `HoursRecord`, `UserSalary` schemas |
| `CsvController` | `get_salaries_csv/2`, `get_project_tasks_csv/3`, `get_project/1` |
| Old Ecto `Session` schema | `Timetracker.submitted_hours_records_multiple_dates?/2` in changeset validation |

### Callers of old Ecto schemas directly

| Caller | Schema used |
|--------|------------|
| 3 LiveViews | `Session` (struct matching, `put_duration`) |
| 2 LiveViews + 1 management LV | `Project` (struct matching, `form_changeset`) |
| 1 component | `Session` |
| `Management` context | `Session`, `HoursRecord`, `UserSalary` (direct Ecto queries) |

## Ash Ecosystem Versions

Installed versions (as of 2026-03-26):

| Package | Version | Notes |
|---------|---------|-------|
| ash | 3.21.3 (~> 3.21) | |
| ash_postgres | 2.8.0 (~> 2.8) | |
| ash_phoenix | 2.3.20 (~> 2.3) | |
| picosat_elixir | 0.2.3 (~> 0.2) | SAT solver required by Ash policies |
| ash_ai | ~> 0.5 (not yet installed) | Phase 3 |

## Key Research Findings

### 1. Coexistence — Ash and Ecto side by side

Ash resources and plain Ecto schemas coexist in the same app, sharing the same
Repo and database. Confirmed by multiple production teams and the Ash creator.

- Ash resources ARE Ecto schemas under the hood. Raw Ecto queries work against
  Ash resource modules.
- Both can point at the same table simultaneously during migration.
- `AshPostgres.Repo` is a thin wrapper around `Ecto.Repo`. Adding
  `use AshPostgres.Repo, define_ecto_repo?: false` keeps all existing Ecto code
  working.

**Gotcha:** Ash resources cannot `belongs_to` a plain Ecto schema in Ash's
relationship DSL. Referenced entities need at minimum a thin read-only Ash
resource wrapper pointing at the same table. This is why we create Core wrappers
in Phase 1.

**Gotcha:** Ash uses `Ash.NotLoaded` for unloaded relationships, not
`Ecto.Association.NotLoaded`. Code that pattern-matches on the Ecto struct needs
adjustment for Ash resources.

Sources:
- https://ash-hq.org/forum/support/1078295805787656322 (Zach Daniel confirms)
- https://elixirforum.com/t/adding-ash-ashpostgres-to-a-project-already-in-production/62530
- https://medium.com/@lambert.kamaro/part-31-ash-resources-are-ecto-schemas-fc853a507e36

### 2. Wrapping Existing Tables

Ash resources can wrap existing tables with `migrate? false`:

```elixir
postgres do
  table "sessions"
  repo Firmowid.Repo
  migrate? false
end
```

Ash will NOT generate migrations for this resource. The table schema is assumed
to already exist and match the resource's attributes.

There is also `mix ash_postgres.gen.resources` which can introspect the DB and
scaffold resources automatically. The `--fragments` flag splits generated code
into regenerable fragments (attributes, relationships) and customization files
(actions, policies) that are never overwritten. We may use this for bulk
conversion of later domains.

Sources:
- https://hexdocs.pm/ash_postgres/set-up-with-existing-database.html
- https://hexdocs.pm/ash_postgres/Mix.Tasks.AshPostgres.Gen.Resources.html

### 3. Multitenancy — Attribute Strategy

Our `Repo.prepare_query/3` pattern maps directly to Ash's `:attribute`
multitenancy strategy:

```elixir
multitenancy do
  strategy :attribute
  attribute :organization_id
end
```

This automatically:
- Adds `WHERE organization_id = <tenant>` to every read query
- Sets `organization_id = <tenant>` on every create
- Raises `Ash.Error.Invalid.TenantRequired` if no tenant is provided

The tenant is set via the `scope:` option (which bundles actor + tenant) or
the explicit `tenant:` option on any Ash call.

**`global? true`** allows operations without a tenant (for admin dashboards,
cross-org reports). When used, authorization policies must handle cross-org
visibility.

**User and Organization do NOT get multitenancy** — they are the identity layer.
Everything else in Timetracker gets `strategy :attribute, attribute: :organization_id`.

Sources:
- https://hexdocs.pm/ash/multitenancy.html
- https://alembic.com.au/blog/multitenancy-in-ash-framework

### 4. Authorization — Policies Replace Bodyguard

Ash policies are declarative, defined on each resource, and automatically
enforced on every action call. No manual `Bodyguard.permit!/3` needed.

**Current Bodyguard pattern:**

```elixir
# In context module
@behaviour Bodyguard.Policy
def authorize(:read_projects, %{role: :admin}, _), do: true
def authorize(:update_session, %{role: role, id: user_id}, %{user_id: user_id} = session)
    when role in [:employee, :admin] do
  session.end_datetime == nil or not submitted_hours_record?(user_id, session.start_datetime)
end
def authorize(_, _, _), do: false

# In LiveView
Bodyguard.permit!(Firmowid.Timetracker, :create_session, current_user, session)
```

**Ash-native equivalent:**

```elixir
# On the resource itself
authorizers: [Ash.Policy.Authorizer]

policies do
  bypass actor_attribute_equals(:role, :admin) do
    authorize_if always()
  end

  policy [action_type(:read), actor_attribute_equals(:role, :employee)] do
    authorize_if relates_to_actor_via(:user)
  end

  policy [action([:create, :update, :destroy]), actor_attribute_equals(:role, :employee)] do
    authorize_if relates_to_actor_via(:user)
    forbid_if Firmowid.Ash.Timetracker.Checks.HoursRecordSubmitted
  end
end

# In LiveView — no permit! call needed
Firmowid.Ash.Timetracker.Session
|> AshPhoenix.Form.for_create(:start, scope: socket.assigns.scope)
|> AshPhoenix.Form.submit(params: params)
```

**Built-in policy checks cover our needs:**

| Need | Ash check |
|------|-----------|
| Role check | `actor_attribute_equals(:role, :admin)` |
| Ownership | `relates_to_actor_via(:user)` |
| Custom business rule | `Ash.Policy.SimpleCheck` (e.g., hours record submitted) |
| Admin bypass | `bypass actor_attribute_equals(:role, :admin) do ... end` |

**For read actions,** policies act as filters — unauthorized data is invisible,
not forbidden. An employee calling `:read` on Session only sees their own
sessions. This replaces the manual `WHERE user_id = ?` filtering in the current
context.

**Domain-level authorization config:**

```elixir
defmodule Firmowid.Ash.Timetracker do
  use Ash.Domain

  authorization do
    authorize :by_default
    require_actor? true
  end
end
```

Sources:
- https://hexdocs.pm/ash/policies.html
- https://hexdocs.pm/ash/Ash.Policy.Check.Builtins.html
- https://hexdocs.pm/ash/actors-and-authorization.html

### 5. Policies Propagate to AshAI MCP Automatically

This is the core architectural payoff. AshAI enforces policies through two
mechanisms:

1. **Pre-flight filtering.** Before an LLM sees available tools, AshAI calls
   `Ash.can?` for each tool against the current actor. Unauthorized tools are
   not exposed to the LLM at all.

2. **Runtime enforcement.** Every tool invocation passes through the same
   `Ash.Domain.action/3` code path with `actor:` and `tenant:` set. Policies
   are checked identically to a web request.

Setup:

```elixir
chain
|> AshAi.setup_ash_ai(
  otp_app: :firmowid,
  tools: [:my_sessions, :start_session, :stop_session],
  actor: current_user,
  tenant: current_user.organization_id
)
```

Sources:
- https://deepwiki.com/ash-project/ash_ai/2.3-authorization-and-visibility
- https://github.com/ash-project/ash_ai/issues/61

### 6. UUIDv7 — Built Into Ash

Ash has native UUIDv7 support. No external package needed for Ash resources.

```elixir
attributes do
  uuid_v7_primary_key :id
end
```

This is equivalent to:

```elixir
attribute :id, :uuid_v7 do
  writable? false
  public? true
  default &Ash.UUIDv7.generate/0
  primary_key? true
  allow_nil? false
end
```

The external `uuid_v7` hex package is still needed for plain Ecto schemas
(`use Firmowid.Schema`) during the transition. Once all schemas are Ash
resources, it can be removed.

**Foreign key type:** `config :ash, :default_belongs_to_type, :uuid_v7`

**Timestamps:** Ash defaults to `:utc_datetime_usec`. We use `:utc_datetime`.
Override per resource or via a shared macro:

```elixir
defmodule Firmowid.Ash.Resource do
  defmacro firmowid_timestamps do
    quote do
      create_timestamp :inserted_at, type: :utc_datetime
      update_timestamp :updated_at, type: :utc_datetime
    end
  end
end
```

Sources:
- https://hexdocs.pm/ash/Ash.Type.UUIDv7.html
- https://hexdocs.pm/ash/Ash.UUIDv7.html

### 7. Ash.Scope — Bundling Actor + Tenant

`Ash.Scope` (introduced v3.5.13, 2025-05-30) bundles actor, tenant, and context
into a single struct. Passed via `scope:` option on all Ash calls.

```elixir
defmodule Firmowid.Ash.Scope do
  defstruct [:current_user, :current_tenant]

  defimpl Ash.Scope.ToOpts do
    def get_actor(%{current_user: user}), do: {:ok, user}
    def get_tenant(%{current_tenant: t}), do: {:ok, t}
    def get_context(_), do: :error
    def get_tracer(_), do: :error
  end
end
```

Usage in LiveView:

```elixir
# In on_mount hook (alongside existing Repo.put_org_id during transition):
scope = %Firmowid.Ash.Scope{
  current_user: user,
  current_tenant: user.organization_id
}
socket = assign(socket, :ash_scope, scope)

# In event handlers:
Firmowid.Ash.Timetracker.list_sessions!(scope: socket.assigns.ash_scope)
```

During the transition, both `Repo.put_org_id` (for Ecto contexts) and
`Ash.Scope` (for Ash domains) are set in the auth pipeline. After all domains
are migrated, `Repo.put_org_id` is removed.

Source: https://hexdocs.pm/ash/Ash.Scope.html

### 8. ParadeDB + Ash Integration (spiked 2026-03-26)

**No `ash_paradedb` package exists.** ParadeDB uses the `@@@` operator (exposed
as `~>` in the `paradex` Ecto package, already in our deps).

**Spike results — all verified in iex against live data:**

1. **`fragment()` works in `Ash.Query.filter`:**
   ```elixir
   Ash.Query.filter(Session, fragment("extract(month from ?) = ?", start_datetime, ^3))
   ```
   Returns correct results. Month/year extraction, duration calculations work.

2. **ParadeDB `@@@` via fragment works in Ash filter expressions:**
   ```elixir
   Ash.Query.filter(Project, fragment("? @@@ ?", name, ^"Firm"))
   ```
   The expression compiles and executes, BUT requires `prepare: :unnamed` repo
   option (Postgrex prepared statement caching is incompatible with ParadeDB's
   custom operator).

3. **Duration calculation loading works:**
   ```elixir
   Ash.Query.load(:duration)  # returns correct seconds via EXTRACT(EPOCH FROM ...)
   ```

**Problem: `prepare: :unnamed` delivery to AshPostgres.**

AshPostgres calls `repo.all(query, AshSql.repo_opts(...))` where
`AshSql.repo_opts` returns `[]` for our resource (no schema prefix, no timeout).
There is no hook to inject extra repo options.

**Solution: process dict flag in `Repo.default_options/1`.**

Ecto merges `default_options` as the base layer before explicit opts. Since
`AshSql.repo_opts` returns `[]`, our `default_options` is the only source.

```elixir
# In Repo:
def default_options(_operation) do
  opts = [organization_id: get_org_id()]
  if Process.get(:paradedb_unnamed), do: [{:prepare, :unnamed} | opts], else: opts
end
```

Set the flag in an Ash preparation for search actions. Since `Ash.read!` is
synchronous and single-process, the flag is set for the entire call stack.
`prepare: :unnamed` is harmless for non-ParadeDB queries (just skips statement
caching), so cleanup timing is not critical.

**Chosen approach: `Ash.CustomExpression`** for the search filter:

```elixir
defmodule Firmowid.Ash.Expressions.ParadeDBSearch do
  use Ash.CustomExpression,
    name: :paradedb_search,
    arguments: [[:string, :string]]

  def expression(AshPostgres.DataLayer, [field, query]) do
    {:ok, expr(fragment("? @@@ ?", ^field, ^query))}
  end

  def expression(_data_layer, _args), do: :unknown
end

# config.exs:
config :ash, :custom_expressions, [Firmowid.Ash.Expressions.ParadeDBSearch]
```

`paradedb.score()` for ordering uses `fragment()` in a preparation or
`modify_query`.

Sources:
- `Ash.CustomExpression` docs: https://hexdocs.pm/ash/Ash.CustomExpression.html
- AshPostgres expressions/fragments: https://hexdocs.pm/ash_postgres/expressions.html
- GitHub issue that created CustomExpression: https://github.com/ash-project/ash/issues/374
- Blog post showing fragment + tsvector in Ash: https://blog.1-800-rad-dude.com/posts/2025/08-13-Adding-Postgres-Full-Text-Search-to-an-Ash-Project.html
- Paradex package: https://hex.pm/packages/paradex (v0.4.0, maps `~>` to `@@@`)

## Namespace Strategy

### During Migration: `Firmowid.Ash.*`

All Ash domains and resources live under `Firmowid.Ash.*`:

```
lib/firmowid/ash/
  scope.ex                          # Firmowid.Ash.Scope
  resource.ex                       # Firmowid.Ash.Resource (base macro)
  expressions/
    paradedb_search.ex              # Firmowid.Ash.Expressions.ParadeDBSearch
  core/
    core.ex                         # Firmowid.Ash.Core domain
    user.ex                         # Firmowid.Ash.Core.User
    organization.ex                 # Firmowid.Ash.Core.Organization
    counterparty.ex                 # Firmowid.Ash.Core.Counterparty
    tag_definition.ex               # Firmowid.Ash.Core.TagDefinition
    blob.ex                         # Firmowid.Ash.Core.Blob
  payroll/
    payroll.ex                      # Firmowid.Ash.Payroll domain
    user_salary.ex                  # Firmowid.Ash.Payroll.UserSalary
    changes/
      retire_existing_salary.ex     # Ash.Resource.Change — retires active salary before creating new one
  timetracker/
    timetracker.ex                  # Firmowid.Ash.Timetracker domain
    session.ex                      # Firmowid.Ash.Timetracker.Session
    project.ex                      # Firmowid.Ash.Timetracker.Project
    project_user.ex                 # Firmowid.Ash.Timetracker.ProjectUser
    hours_record.ex                 # Firmowid.Ash.Timetracker.HoursRecord
    checks/
      hours_record_submitted.ex     # custom policy check
  absence/                          # net-new Ash domain (Phase 3)
    absence.ex
    absence_type.ex
    absence_request.ex
    absence_balance.ex
```

Old modules (`Firmowid.Timetracker`, `Firmowid.Accounts`, etc.) stay untouched
until their domain is fully migrated, then deleted.

### Endgame: Drop the Prefix

Once all domains are Ash-native, the `.Ash.` prefix is dropped:

- `Firmowid.Ash.Timetracker.Session` becomes `Firmowid.Timetracker.Session`
- `Firmowid.Ash.Core.User` becomes `Firmowid.Core.User` (or `Firmowid.Accounts.User`)
- Mechanical rename via Igniter or find-replace

## Decisions Made

Decisions locked in during planning. Rationale included for future reference.

### 1. Full port of `Firmowid.Timetracker` — drop old code

Port all ~50 functions from the 1,251-line context module to Ash actions, then
delete the old context module and all 5 Ecto schemas. This is preferred over a
partial port because:
- It eliminates dual code paths
- Forces resolution of all edge cases upfront
- Results in a clean, single-system Timetracker

### 2. Management context stays as Ecto, references switch to Ash modules

Management does raw Ecto queries against Timetracker schemas. Since Ash resources
ARE Ecto schemas, Management can keep its raw queries but point at the new Ash
resource modules (e.g., `from s in Firmowid.Ash.Timetracker.Session, ...`).
No Ash API adoption needed yet.

### 3. ParadeDB via `Ash.CustomExpression` + process dict for `prepare: :unnamed`

- `Ash.CustomExpression` named `:paradedb_search` wraps `fragment("? @@@ ?", ...)`
- `Repo.default_options` checks `Process.get(:paradedb_unnamed)` to inject
  `prepare: :unnamed` when needed
- Ash preparation for search actions sets the flag before query execution
- `paradedb.score()` ordering via `fragment()` in preparations

Rejected alternatives:
- Raw Ecto queries (loses policies + multitenancy)
- Global `prepare: :unnamed` (unnecessary perf hit on all queries)
- ManualRead actions (too much boilerplate per search action)

### 4. Cross-context calls from Ash changes

`Analysis.create_project_tag/1`, `Analysis.sync_project_tag_name/2`,
`Analysis.delete_tag_definition_by_id/1`, and `Blobs.create_blob/3` are called
from Ash `after_action` changes. These contexts are not being migrated yet, so
wrapping them in Ash would be pointless ceremony. They'll be addressed when their
own domains are migrated.

### 5. Duration as Ash calculation (not virtual field)

The old `Session.put_duration/1` function sets a virtual field in Elixir. The
Ash resource uses `calculate :duration, :integer, expr(...)` which computes it
in SQL. Callers use `Ash.Query.load(:duration)` or `Ash.load!` instead of the
old function. Verified working in iex.

### 6. `Ash.bulk_update/4` for batch session updates

The old `update_sessions/1` takes a list of changesets and wraps them in
`Ecto.Multi`. The Ash equivalent is `Ash.bulk_update/4` with `:atomic` strategy
for efficient DB-level updates. API confirmed — supports `return_records?`,
`stop_on_error?`, `transaction: :all`.

## Migration Phases

### Phase 0 — Foundation ✅ COMPLETE

**Goal:** Install Ash, prove coexistence, establish patterns. Zero regressions.

1. ✅ Add deps to `mix.exs`: ash 3.21.3, ash_postgres 2.8.0, ash_phoenix 2.3.20, picosat_elixir 0.2.3
2. ✅ Update `Firmowid.Repo`: add `use AshPostgres.Repo, define_ecto_repo?: false`
3. ✅ Create `Firmowid.Ash.Resource` base macro (firmowid_timestamps)
4. ✅ Add `config :ash, :default_belongs_to_type, :uuid_v7` to config
5. ✅ Create `Firmowid.Ash.Scope` struct implementing `Ash.Scope.ToOpts`
6. ✅ Register ash_domains in config
7. ✅ `mix compile --warnings-as-errors` passes, all 360 tests pass

### Phase 1 — Core Entity Wrappers ✅ COMPLETE

**Goal:** Read-only Ash resources for shared entities. All writes still go
through Ecto.

1. ✅ Create `Firmowid.Ash.Core` domain
2. Read-only resources:
   - ✅ `User` — NO multitenancy (identity layer), read action only
   - ✅ `Organization` — NO multitenancy, read action only
   - ✅ `Counterparty` — attribute multitenancy, read action only
   - ✅ `TagDefinition` — attribute multitenancy, read action only
   - ✅ `Blob` — attribute multitenancy, read action only
3. ✅ All resources: `migrate? false`, minimal policies
4. ✅ Smoke test: `Ash.read!` from iex with scope — verified 78 sessions, 4 projects
5. ✅ Smoke test: 3 counterparties, 4 tags, 11 blobs verified via Tidewave

### Phase 2 — Timetracker as Ash Domain (in progress)

**Goal:** Full Ash domain with CRUD actions, policies, calculations. Old
`Firmowid.Timetracker` context module and Ecto schemas deleted.

**Resources to convert (all with `migrate? false`, attribute multitenancy):**

- **Session** — actions: `start`, `stop`, `create`, `read`, `update`, `destroy`,
  `bulk_update`. Validations: datetime order, project access. Duration as
  calculation. Lockdown as calculation. Postgres exclusion constraint for overlap
  stays at DB level — surface as clean error.
- **Project** — actions: `create`, `read`, `update`, `archive`, `unarchive`,
  `destroy`. TagDefinition sync via after_action change. Managed relationship
  for ProjectUser. ParadeDB search via CustomExpression.
- **ProjectUser** — managed relationship on Project.
- **UserSalary** — Extracted to `Firmowid.Ash.Payroll` domain. CRUD + soft-delete
  `retire` action + `create_with_retire` (retires existing active salary in same
  transaction via `RetireExistingSalary` change module). Read actions: `get_latest`
  (active salary for a user), `as_of` (date-based lookup with end-of-month logic).
  Generic action: `salaries_csv` (payroll CSV for a month/year).
- **HoursRecord** — CRUD with blob relationship. `create` calls
  `Blobs.create_blob` in after_action.

**Authorization migration:**

- Admin bypass on every resource
- Employee policies: ownership via `relates_to_actor_via(:user)`, business
  rules via custom `SimpleCheck` modules
- Domain-level `authorize :by_default, require_actor? true`

**Context decomposition** — the 1,251-line `Firmowid.Timetracker` module
decomposes into:

| Current | Ash equivalent |
|---------|---------------|
| Query functions (list_*, get_*) | Read actions with preparations (filters, sorting) |
| Create/update/delete functions | Create/update/destroy actions with changes |
| Duration calculations | `calculate :duration, :integer, expr(...)` |
| Lockdown checks | Custom policy check `HoursRecordSubmitted` |
| Authorization clauses | Policies on each resource |
| Salary-as-of-date queries | Read action with preparation on UserSalary |
| ParadeDB full-text search | CustomExpression + preparations with `prepare: :unnamed` |
| CSV generation | Read actions or code interface functions with raw Ecto |
| Bulk session update | `Ash.bulk_update/4` with `:atomic` strategy |

**LiveView migration:**

- Replace `Bodyguard.permit!` + manual changesets with `AshPhoenix.Form` + scope
- Wire `Ash.Scope` into `on_mount` hook alongside existing `Repo.put_org_id`
- Update CSV/PDF controllers to read via Ash

**Cleanup:**

- Delete `Firmowid.Timetracker` context module (1,251 lines)
- Delete old Ecto schemas: Session, Project, ProjectUser, UserSalary, HoursRecord
- Update `Management` context to reference Ash resource modules
- Update `CsvController` to use Ash code interface

### Phase 3 — AshAI + MCP + Absence

**Goal:** Expose Timetracker as MCP tools. Build Absence as net-new Ash domain.

1. Add `{:ash_ai, "~> 0.5"}` to mix.exs
2. Add `tools do ... end` to Timetracker domain:
   - `my_sessions` — read sessions for current user
   - `start_session` — start tracking time
   - `stop_session` — stop tracking time
   - `log_time` — create a completed session
   - `my_projects` — read user's projects
3. Run `mix ash_ai.gen.mcp` — dev + production MCP endpoints
4. Run `mix ash_ai.gen.chat --live` — chat UI with streaming + tool calls
5. Build **Absence** domain (net-new Ash):
   - `AbsenceType` — paid leave, unpaid leave, days off, out of office, etc.
   - `AbsenceRequest` — employee requests, manager approves/rejects
   - `AbsenceBalance` — remaining days per type per year
6. Expose Absence tools via MCP
7. Integration tests: MCP tool calls respect policies + tenant

### Phase 4+ — Remaining Domains + Endgame

Migrate remaining contexts one by one. Order by isolation or MCP value:

1. **Finances** (bank accounts, transactions) — relatively standalone
2. **SalesInvoices / CostInvoices** — complex but high MCP value
3. **Accounts** (full auth conversion) — biggest, hardest, unlocks AshAuthentication
4. **Analysis, BankData, KSeF, Invoicing, etc.**

**Endgame:**
- Drop `.Ash.` prefix from all module names
- Remove Bodyguard dep
- Remove `Firmowid.Schema` macro
- Remove `Repo.put_org_id` / `prepare_query` tenant logic
- Remove `uuid_v7` hex package (Ash built-in covers it)

## Execution Worklist (Phase 1 completion + Phase 2)

Ordered sequence. Each item is an atomic, committable step.

### Finish Phase 1 — Core wrappers ✅ DONE

- [x] 1. Add `Firmowid.Ash.Core.Counterparty` read-only wrapper
- [x] 2. Add `Firmowid.Ash.Core.TagDefinition` read-only wrapper
- [x] 3. Add `Firmowid.Ash.Core.Blob` read-only wrapper

### ParadeDB integration ✅ DONE

- [x] 4. Add `Firmowid.Ash.Expressions.ParadeDBSearch` custom expression
- [x] 5. Add `Process.get(:paradedb_unnamed)` check to `Repo.default_options/1`

### Timetracker resources — new ✅ DONE

- [x] 6. Add `Timetracker.ProjectUser` resource (attribute multitenancy, identities, CRUD)
- [x] 7. Add `Timetracker.UserSalary` resource (CRUD + `retire` action, conditional identity)
- [x] 8. Add `Timetracker.HoursRecord` resource (CRUD, validations, blob FK, identity)

### Timetracker resources — flesh out existing

- [x] 9. Flesh out `Timetracker.Session` — all write actions (start, stop, create, update, destroy), overlap error handling, all read actions (list_user_sessions, get_current, weeks_with_sessions, duration queries, month summaries, grouped sessions, most_recent, by_ids), lockdown calculation, bulk_update
- [x] 10. Flesh out `Timetracker.Project` — all write actions (create, update, archive, unarchive, destroy) + TagDefinition sync via after_action changes + all read variants (active/archived with search and duration aggregation, with_users, by_ids, get with preloads, for_user, active_for_user)
- [ ] 11. Add `HoursRecordSubmitted` custom policy check (`Ash.Policy.SimpleCheck`)

### Payroll domain (extracted from Timetracker) ✅ DONE

- [x] 12. Salary actions — `get_latest`, `as_of` (date-based lookup), `create_with_retire` (retires existing), `update`, `retire`. Extracted to `Firmowid.Ash.Payroll` domain.
- [x] 15a. CSV generation — `salaries_csv` generic action on `Payroll.UserSalary`

### Hours record, cost/reporting functions

- [ ] 13. Hours record actions — `get_by_month`, `get_month_hours_records` (users + records), `create` (with blob upload)
- [ ] 14. Cost/reporting read actions — `get_project_total_time_worked`, `get_project_total_cost`, per-user cost breakdowns, all-time variants
- [ ] 15b. CSV generation — `get_project_tasks_csv` (as action on Session or Project)

### Domain code interface + auth wiring

- [ ] 16. Add code interface to Timetracker domain (all public functions)
- [ ] 17. Wire `Ash.Scope` into `on_mount` auth hook (alongside `Repo.put_org_id`)

### Migrate callers

- [ ] 18. Migrate 6 Timetracker LiveViews to Ash code interface + AshPhoenix.Form
- [ ] 19. Migrate 4 Management LiveViews to use Ash resource modules
- [ ] 20. Migrate Management context schema references to Ash resource modules
- [ ] 21. Migrate CsvController to Ash code interface

### Delete old code

- [ ] 22. Delete `Firmowid.Timetracker` context module (lib/firmowid/timetracker.ex)
- [ ] 23. Delete old Ecto schemas: Session, Project, ProjectUser, UserSalary (now in Payroll), HoursRecord
- [ ] 24. Clean up Bodyguard references in deleted code

### Tests

- [ ] 25. Co-located tests for all Ash resources and actions

## What Replaces What (Complete Mapping)

| Current | Ash-native replacement |
|---------|----------------------|
| `Firmowid.Schema` macro | `uuid_v7_primary_key :id` + `firmowid_timestamps()` + `config :ash, :default_belongs_to_type, :uuid_v7` |
| `Repo.put_org_id(org_id)` process dict | `Ash.Scope` struct with `tenant:` |
| `Repo.prepare_query/3` WHERE injection | `multitenancy strategy: :attribute, attribute: :organization_id` |
| `put_change(:organization_id, Repo.get_org_id())` in changesets | Automatic — Ash sets tenant attribute on create |
| `Bodyguard.permit!/3` in LiveViews | Automatic — policies checked on every Ash action call |
| `@behaviour Bodyguard.Policy` + `authorize/3` | `policies do ... end` DSL on each resource |
| Phoenix context module (public API) | Ash Domain + code interface on resources |
| `Ecto.Changeset` in LiveViews | `AshPhoenix.Form` |
| `Ecto.Multi` for transactions | Ash actions with `after_action` changes (same DB transaction) |
| `skip_organization_id: true` | Resources without multitenancy (User, Organization) or `global? true` |
| Manual query functions | Read actions with preparations |
| Virtual fields (duration, lockdown) | Calculations |
| `Session.put_duration/1` | `calculate :duration` + `Ash.Query.load(:duration)` |
| `Paradex ~>` operator in raw Ecto | `Ash.CustomExpression :paradedb_search` + `fragment("? @@@ ?")` |
| `Repo.all(query, prepare: :unnamed)` | Process dict flag in `Repo.default_options` |
| `Ecto.Multi` batch updates | `Ash.bulk_update/4` with `:atomic` strategy |

## Open Items

1. **Session overlap constraint.** Postgres exclusion constraint stays at DB
   level. Ash will surface the `Postgrex.Error`. Add an identity or custom error
   handler for a clean changeset error. Handle during Session write actions.

2. **`paradedb.score()` ordering.** Need to test
   `Ash.Query.sort(expr(fragment("paradedb.score(?)", id)))` or use
   `modify_query` to inject the ORDER BY. Handle during Project search actions.

3. **`prepare: :unnamed` cleanup timing.** Set in preparation, but when to
   clean up? `prepare: :unnamed` is harmless for non-ParadeDB queries (just
   skips statement caching), so cleanup is not critical. Could clean up in
   after_action or just leave it — the next request starts fresh.

4. **Test co-location.** Ash test helpers need to work with `test_paths: ["lib"]`
   layout. Verify when writing first tests.

## Discoveries

Accumulated findings from implementation and spiking. Referenced by number
throughout the plan.

1. **Ash and Ecto coexist cleanly.** `AshPostgres.Repo` wraps `Ecto.Repo` with
   `define_ecto_repo?: false`. Existing Ecto code keeps working. Both can point
   at the same tables.

2. **`picosat_elixir`** is required — Ash policies need a SAT solver. Without
   it, compilation fails with warnings-as-errors.

3. **`match_v4_uuids?: true` is essential** — All existing data has UUIDv4
   primary keys (not v7). Ash's `Ash.Type.UUIDv7` rejects v4 by default. Set
   `config :ash, Ash.Type.UUIDv7, match_v4_uuids?: true` in config.exs. This
   is a `compile_env` so `mix deps.compile ash --force` is needed after changing.

4. **`Repo.put_org_id` coexists with Ash tenant scoping during transition.**
   `Repo.prepare_query/3` intercepts ALL queries including Ash's. Both the
   process-dict org_id and Ash's attribute multitenancy WHERE clause are applied
   (double filter, harmless but redundant). During transition, both must be set
   in the auth pipeline.

5. **Attribute multitenancy** (`strategy :attribute, attribute: :organization_id`)
   is the direct replacement for `Repo.prepare_query/3`. Automatic WHERE
   injection + auto-set on create.

6. **User and Organization must NOT have multitenancy** — they're the identity
   layer. Auth queries use `skip_organization_id: true`. `users.organization_id`
   is nullable (onboarding state).

7. **Ash xref compile deps are inherent** — `resources do` in domain modules
   creates compile-time dependencies on resource modules. The xref
   `--fail-above` threshold was bumped from 1 to 10.

8. **Postgres version is 17.7** — `min_pg_version` set to
   `%Version{major: 17, minor: 0, patch: 0}`.

9. **Session duration calculation** works as an Ash calculation using
   `fragment("EXTRACT(EPOCH FROM ...)")`. Verified in iex — returns correct
   seconds for both running and completed sessions.

10. **Session overlap** uses a Postgres exclusion constraint — stays at DB level,
    Ash surfaces the error.

11. **Project ↔ TagDefinition sync** currently uses `Ecto.Multi` — needs
    `after_action` change in Ash. Will call existing `Analysis` context
    functions directly.

12. **`fragment()` works in `Ash.Query.filter`** — verified for month/year
    extraction, ParadeDB `@@@`, and arbitrary SQL expressions. This is the
    primary escape hatch for Postgres-specific functionality.

13. **ParadeDB requires `prepare: :unnamed`** — Postgrex prepared statement
    caching is incompatible with ParadeDB's custom `@@@` operator. Solution:
    process dict flag in `Repo.default_options/1`, same pattern as
    `Repo.put_org_id`.

14. **`AshSql.repo_opts` returns `[]`** for our resources (no schema prefix,
    no timeout). This means `Repo.default_options` is the sole source of repo
    options when AshPostgres executes queries.

15. **`Ash.bulk_update/4`** supports `:atomic` strategy for efficient DB-level
    batch updates. Replaces `Ecto.Multi`-based `update_sessions/1`.

16. **AshPostgres casts attribute references in fragments** — e.g. `name`
    becomes `name::text` in SQL. This breaks ParadeDB's `@@@` operator which
    needs the raw column reference for BM25 index access. Workaround: use
    literal column names in fragments (`fragment("name @@@ ?", ^search)`)
    instead of attribute references (`fragment("? @@@ ?", name, ^search)`).
    The `CustomExpression` with `[:any, :string]` argument types is registered
    but may still get the cast at runtime — use the literal fragment approach
    in search preparations as a fallback.

17. **Ash spawns async tasks for relationship loading** via
    `Ash.ProcessHelpers.async/2`. These tasks do NOT inherit process dictionary
    entries. Our `Repo.put_org_id` / `prepare_query` pattern breaks in async
    Ash contexts. Fix: `config :ash, :disable_async?, true` during migration.
    This forces synchronous relationship loading (same process), preserving the
    process dict. Remove when `Repo.put_org_id` is eliminated.

18. **Project relationships fully wired** — counterparty, tag_definition,
    project_users, users (many_to_many through ProjectUser), sessions. All
    verified loading correctly via Tidewave with `disable_async?: true`.

19. **Ash validation `on:` only accepts action types** (`:create`, `:update`,
    `:destroy`, `:read`, `:action`), NOT action names. So `:start` (a named
    create action) can't be used — use `:create` to cover both `start` and
    `create` actions.

20. **Custom validations are not atomic-compatible** — update actions using
    custom validations (like `DatetimeOrder`, `ProjectAccess`) need
    `require_atomic? false`.

21. **Session overlap is enforced by a DB trigger** (`no_session_overlap_trigger`
    calling `prevent_session_overlap()`), NOT an exclusion constraint. It raises
    a generic exception with message "Session for this user overlaps with an
    existing session." AshPostgres catches this as `Ash.Error.Unknown` wrapping
    the Postgrex error.

22. **Session lockdown calculation** uses `EXISTS` subquery against
    `hours_records` table matching `user_id` + month/year extracted from
    `start_datetime`. Verified: January sessions → `lockdown: true` (hours
    records exist), March sessions → `lockdown: false` (no hours records).

23. **`get?(true)` on Ash read actions does NOT auto-set `limit: 1`.** Must add
    `prepare build(limit: 1)` explicitly for single-result actions, otherwise
    `Ash.read_one` raises `MultipleResults`.

24. **`Ash.Query.filter/2` is a macro** — cannot use it with `^pin` inside
    `prepare fn`. Use `Ash.Query.do_filter/2` with keyword syntax
    (e.g. `Ash.Query.do_filter(query, user_id: actor_id)`) for runtime
    filtering inside prepare functions.

25. **Generic actions (`:action` type) need their own policy** — the
    `:read`/`:create`/`:update`/`:destroy` policies don't cover them. Must add
    `policy [action_type(:action), ...] do ... end`.

26. **`Ash.Query.for_read/3` vs `for_read/4` — opts vs params.** Calling
    `Ash.Query.for_read(Resource, :action, actor: actor, tenant: tenant)` passes
    the keyword list as **params** (3rd arg), not opts. The domain's
    `require_actor?` check then fails because no actor is in opts. Must use
    `Ash.Query.for_read(Resource, :action, %{}, actor: actor, tenant: tenant)`
    to pass params as 3rd arg and opts as 4th.

27. **Change module context has `.actor` and `.tenant`.** The `context` parameter
    in `Ash.Resource.Change.change/3` is `%Ash.Resource.Change.Context{}` with
    `.actor`, `.tenant` fields. Capture it in the outer `change/3` and close over
    it in `before_action` lambdas. Prefer dedicated Change modules over inline
    `change(fn ...)` for non-trivial logic.

28. **Salary decoupled from Timetracker into Payroll domain.** `UserSalary` is an
    HR/payroll concern, not time-tracking. Cost calculations that need both salary
    and session data use cross-domain Ecto joins (same DB, works because Ash
    resources are Ecto schemas). The `salaries_csv` generic action lives on
    `Payroll.UserSalary` even though it joins `Timetracker.HoursRecord`.

29. **Raw Ecto queries on table strings lose UUID type info.** When using
    `from(p in "projects", ...)` instead of `from(p in ProjectSchema, ...)`,
    Postgrex doesn't know column types and fails with "expected a binary of 16
    bytes" for UUID columns. Always use schema modules (old Ecto or Ash resource)
    in `from()` — they carry the column type metadata.

30. **Xref `--fail-above` threshold needs bumping for Ash.** Ash/Spark DSL
    domains create compile-connected references to all their resources. Each
    `resources do ... end` block in a domain module creates N compile edges.
    Threshold bumped from 1 → 20 to accommodate Ash domains.

31. **Project ↔ TagDefinition sync uses dedicated Change modules.** Three
    separate `Ash.Resource.Change` modules handle the lifecycle:
    `CreateProjectTag` (after_action: creates tag + links via update_all),
    `SyncProjectTagName` (after_action: syncs name on project update),
    `CleanupProjectTag` (after_action: deletes orphaned tag on destroy).
    All delegate to existing `Firmowid.Analysis` context functions.

## Rejected Alternatives

| Alternative | Why rejected |
|-------------|-------------|
| `context` multitenancy strategy | Designed for Postgres schema-per-tenant, not column-based. Would fight Ash conventions. |
| Big-bang migration (all at once) | Too risky for a production app with ~26 schemas and ~10 contexts. |
| Converting Accounts/auth first | Scope creep — auth is complex (OAuth, tokens, sessions). Timetracker is more isolated. |
| Keeping Bodyguard alongside Ash policies | Dual auth systems create confusion. Ash policies propagate to MCP; Bodyguard doesn't. |
| Using external `uuid_v7` package for Ash resources | Ash has built-in `Ash.Type.UUIDv7`. External package only needed for remaining Ecto schemas. |
| `Firmowid.Core` as permanent domain name | `Core` is a migration-time name. Endgame naming TBD after all domains are migrated. |
| AshRbac extension | Generates standard Ash policies at compile time, but our business rules (hours record submitted check) need custom `SimpleCheck` modules anyway. Adds a dep for marginal benefit. |
| Raw Ecto for ParadeDB search | Loses Ash policy enforcement and multitenancy. CustomExpression keeps search inside the Ash expression system. |
| Global `prepare: :unnamed` | Unnecessary performance hit on all queries. Process dict flag is surgical. |
| ManualRead for search actions | Too much boilerplate per action. Fragment in preparations is simpler. |
| Partial port (core CRUD only) | Leaves dual code paths. Full port + deletion is cleaner. |

## References

- Ash Framework docs: https://hexdocs.pm/ash/
- AshPostgres existing DB setup: https://hexdocs.pm/ash_postgres/set-up-with-existing-database.html
- Ash multitenancy: https://hexdocs.pm/ash/multitenancy.html
- Ash policies: https://hexdocs.pm/ash/policies.html
- Ash.Scope: https://hexdocs.pm/ash/Ash.Scope.html
- Ash.Type.UUIDv7: https://hexdocs.pm/ash/Ash.Type.UUIDv7.html
- Ash.CustomExpression: https://hexdocs.pm/ash/Ash.CustomExpression.html
- AshPostgres expressions: https://hexdocs.pm/ash_postgres/expressions.html
- Ash.bulk_update: https://hexdocs.pm/ash/Ash.html#bulk_update/4
- AshAI: https://hexdocs.pm/ash_ai/readme.html
- AshAI authorization: https://deepwiki.com/ash-project/ash_ai/2.3-authorization-and-visibility
- AshPhoenix forms: https://hexdocs.pm/ash_phoenix/getting-started-with-ash-and-phoenix.html
- Migration blog post: https://blog.1-800-rad-dude.com/posts/2025/07-11-Migrating-my-Existing-Elixir-App-to-Ash-Framework.html
- Coexistence confirmed: https://elixirforum.com/t/adding-ash-ashpostgres-to-a-project-already-in-production/62530
- Alembic adoption strategy: https://alembic.com.au/ash-framework
- Paradex (ParadeDB Ecto): https://hex.pm/packages/paradex
- Full-text search in Ash (tsvector): https://blog.1-800-rad-dude.com/posts/2025/08-13-Adding-Postgres-Full-Text-Search-to-an-Ash-Project.html
