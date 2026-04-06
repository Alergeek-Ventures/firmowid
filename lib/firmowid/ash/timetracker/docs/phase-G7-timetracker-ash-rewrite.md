# Phase G7 — Timetracker Ash rewrite

## Goal

Remove all raw Ecto (`import Ecto.Query`, `from(...)`, `Repo.all/one/get/preload`)
from the Timetracker domain. Replace with clean Ash read actions following the
Transaction pattern (one `:list` read per resource with optional filter arguments).
Move cross-domain data composition to the view layer.

## Decisions

- **Transaction pattern:** Each resource gets one `:list` read action with
  optional arguments. Filters applied via `prepare build(filter:) where present(:arg)`.
  Sorting, loading, aggregation controlled at callsite.
- **Domains expose atomic data operations. Views compose them for display.**
  Cross-domain joins (User × Session × HoursRecord × UserSalary) are NOT domain
  actions — they're LiveView composition.
- **`Timetracker.seconds_to_hours/1`** stays on the domain module — it's a
  business rule (ceiling). All cost calculations must use it.
- **Existing calculations** (`:duration`, `:month_start`, `:week_start`,
  `:lockdown`) on Session stay as-is — they're pure expression calcs.
- **`salary_as_of_subquery/2`** on UserSalary is deleted. Callers use the
  existing `Payroll.as_of(date, tenant:)` code interface instead.
- **Performance:** Address if issues arise, not preemptively. The composition
  pattern may issue more queries than the single raw Ecto query, but org user
  counts are small and these are admin-only screens.

## Inventory of raw Ecto to remove

### `session.ex` — private helpers

| Function | Lines | What it does |
|----------|-------|-------------|
| `query_employees_for_month/2` | 600-643 | 4-way LEFT JOIN: User × salary_as_of × time_worked(sessions) × HoursRecord |
| `find_employee_details/2` | 663-723 | Get user → preload sessions grouped by project/title → preload projects → salary + hours_record |
| `employee_salary_as_of/3` | 726-730 | Single user salary lookup via `salary_as_of_subquery` |
| `employee_hours_record/2` | 733-737 | Single user hours record lookup |
| `filter_employee_search/2` | 646-660 | ILIKE search on user name/email |

### `session.ex` — generic actions to delete

| Action | Lines | Replacement |
|--------|-------|-------------|
| `:list_employees_for_month` | 277-295 | View-layer composition in `Employees` LiveView |
| `:employee_details` | 297-313 | View-layer composition in `Employee` LiveView |

### `session.ex` — generic actions to delete (pure Ash, replaceable by `:list` + callsite)

| Action | Lines | Replacement |
|--------|-------|-------------|
| `:total_time_worked` | 233-244 | Callsite uses `Ash.aggregate!` on `:list` read |
| `:months_with_sessions` | 222-231 | Callsite uses `:list` read with `distinct(:month_start)` |
| `:weeks_with_sessions` | 178-189 | Callsite uses `:list` read with `distinct(:week_start)` |
| `:grouped_user_project_sessions` | 191-220 | Callsite uses `:list` read + load `:duration` + Elixir group_by |
| `:project_tasks_csv` | 246-275 | Callsite (Csv controller) uses `:list` read + group + CSV encode |

### `session.ex` — private helpers to delete (pure Ash, logic moves to callsite)

| Function | Lines | Replacement |
|----------|-------|-------------|
| `read_sessions_grouped_by_title/4` | 531-544 | Callsite reads sessions + groups in Elixir |
| `read_months_with_sessions/2` | 547-558 | Callsite reads with distinct |
| `read_weeks_with_sessions/2` | (similar) | Callsite reads with distinct |
| `aggregate_total_time_worked/2` | 561-573 | Callsite uses `Ash.aggregate!` |
| `maybe_filter_month_year/3` | 576-584 | Absorbed into `:list` read arguments |
| `maybe_filter/3` (user_id, project_id) | 586-590 | Absorbed into `:list` read arguments |

### `project.ex` — generic actions to delete

| Action | Replacement |
|--------|-------------|
| `:list_active` | Callsite uses `:list` read with `active_only: true` + aggregate |
| `:list_archived` | Callsite uses `:list` read with `archived_only: true` + aggregate |
| `:project_total_cost` | View-layer composition |
| `:project_total_cost_all_time` | View-layer composition |
| `:project_month_users_with_cost` | View-layer composition |
| `:project_users_with_cost_all_time` | View-layer composition |
| `:project_users_with_removed` | View-layer composition |
| `:user_projects_with_duration` | Callsite uses `:list` read with `user_id:` + aggregate |

### `project.ex` — private helpers to delete

| Function | Lines | Replacement |
|----------|-------|-------------|
| `read_projects_with_duration/5` | 403-430 | Callsite does the aggregate + hours conversion |
| `build_duration_filter/2` | 432-440 | Inline in callsite |
| `apply_archive_filter/2` | 442-448 | Part of `:list` read's `active_only`/`archived_only` args |
| `maybe_default_sort/2` | 453-457 | Callsite applies sort |

### `project_costs.ex` — delete entirely (286 lines)

All functions are cross-domain orchestrators or raw Ecto queries.

### `hours_record.ex` — rewrite `:month_hours_records`

The raw Ecto cross-join (User × HoursRecord) becomes view-layer composition.

### `user_salary.ex` — changes

| What | Action |
|------|--------|
| Delete `salary_as_of_subquery/2` (lines 270-283) | Callers use `Payroll.as_of` code interface |
| Rewrite `:salaries_csv` action (raw Ecto) | Move to Csv controller as view-layer composition |

## New Ash read actions

### Session `:list`

File: `lib/firmowid/ash/timetracker/session.ex`

```elixir
read :list do
  description """
  Flexible session listing with optional filters.
  Sorting, loading (duration, lockdown, month_start), and aggregation
  controlled at callsite.
  """

  argument :user_id, :uuid
  argument :project_id, :uuid
  argument :month, :integer
  argument :year, :integer
  argument :running_only, :boolean
  argument :ids, {:array, :uuid}

  prepare build(filter: expr(user_id == ^arg(:user_id))) do
    where present(:user_id)
  end

  prepare build(filter: expr(project_id == ^arg(:project_id))) do
    where present(:project_id)
  end

  prepare build(filter: expr(
    fragment("extract(month from ?) = ?", start_datetime, ^arg(:month)) and
    fragment("extract(year from ?) = ?", start_datetime, ^arg(:year))
  )) do
    where [present(:month), present(:year)]
  end

  prepare build(filter: expr(is_nil(end_datetime))) do
    where argument_equals(:running_only, true)
  end

  prepare build(filter: expr(id in ^arg(:ids))) do
    where present(:ids)
  end
end
```

**Keep:** `:get_current` (actor-based, `get? true`) and `:list_overlapping`
(validation-specific). These serve distinct purposes from generic listing.

### Project `:list`

File: `lib/firmowid/ash/timetracker/project.ex`

```elixir
read :list do
  description """
  Flexible project listing with optional filters.
  Duration aggregation, counterparty loading, sorting at callsite.
  """

  argument :user_id, :uuid
  argument :search, :string
  argument :active_only, :boolean
  argument :archived_only, :boolean
  argument :ids, {:array, :uuid}

  prepare build(filter: expr(
    exists(project_users, user_id == ^arg(:user_id))
  )) do
    where present(:user_id)
  end

  prepare build(filter: expr(is_nil(archived_at))) do
    where argument_equals(:active_only, true)
  end

  prepare build(filter: expr(not is_nil(archived_at))) do
    where argument_equals(:archived_only, true)
  end

  prepare build(filter: expr(id in ^arg(:ids))) do
    where present(:ids)
  end

  # ParadeDB search — reuse existing preparation
  prepare {Firmowid.Ash.Preparations.ParadeDBSearch, columns: ~w(name), argument: :search}
end
```

**Keep:** `:get` (`get? true`, loads users + counterparty).

**Delete:** `:searchable`, `:by_ids`, `:with_users`, `:for_user`,
`:active_for_user`. All covered by `:list` + callsite loading/filtering.

### HoursRecord `:list`

File: `lib/firmowid/ash/timetracker/hours_record.ex`

```elixir
read :list do
  argument :user_id, :uuid
  argument :month, :integer
  argument :year, :integer

  prepare build(filter: expr(user_id == ^arg(:user_id))) do
    where present(:user_id)
  end

  prepare build(filter: expr(month == ^arg(:month))) do
    where present(:month)
  end

  prepare build(filter: expr(year == ^arg(:year))) do
    where present(:year)
  end
end
```

Delete `:month_hours_records` generic action.

### ProjectUser `:list`

File: `lib/firmowid/ash/timetracker/project_user.ex`

```elixir
read :list do
  argument :project_id, :uuid
  argument :user_id, :uuid

  prepare build(filter: expr(project_id == ^arg(:project_id))) do
    where present(:project_id)
  end

  prepare build(filter: expr(user_id == ^arg(:user_id))) do
    where present(:user_id)
  end
end
```

### Core User `:list`

Defined in phase E (step E5). Provides search filter on name/email.

## Code interfaces on domains

### Timetracker domain (`lib/firmowid/ash/timetracker/timetracker.ex`)

```elixir
resources do
  resource Session do
    define :list_sessions, action: :list
    # keep existing interfaces for :start, :stop, :get_current, etc.
  end

  resource Project do
    define :list_projects, action: :list
    define :get_project, action: :get
    # keep existing interfaces for :create, :update, :destroy, etc.
  end

  resource HoursRecord do
    define :list_hours_records, action: :list
    # keep existing interfaces
  end

  resource ProjectUser do
    define :list_project_users, action: :list
  end
end
```

### Core domain (`lib/firmowid/ash/core/core.ex`)

Add `define :list_users, action: :list` (from phase E).

## View-layer composition patterns

### `Employees` LiveView

File: `lib/firmowid_web/management/views/employees.ex`

Currently calls `AshSession.list_employees_for_month(date, opts, scope: scope)`.

After:

```elixir
defp assign_employees(socket) do
  %{selected_date: date, archived: archived, search: search, ash_scope: scope} = socket.assigns
  opts = [scope: scope]

  # 1. List users (with optional search)
  users = Core.list_users!(search_arg(search), opts)

  # 2. Time worked per user for this month
  sessions = Timetracker.list_sessions!(
    %{month: date.month, year: date.year},
    Ash.Query.load(:duration),
    opts
  )
  time_by_user = sessions
    |> Enum.group_by(& &1.user_id)
    |> Map.new(fn {uid, ss} -> {uid, ss |> Enum.map(& &1.duration) |> Enum.sum()} end)

  # 3. Salaries as of this month
  salaries = Payroll.as_of!(date, opts)
  salary_by_user = Map.new(salaries, &{&1.user_id, &1.hourly_rate})

  # 4. Hours records for this month
  hrs = Timetracker.list_hours_records!(%{month: date.month, year: date.year}, opts)
  hr_by_user = Map.new(hrs, &{&1.user_id, &1})

  # 5. Compose
  employees = Enum.map(users, fn user ->
    %{
      user: user,
      time_worked: Map.get(time_by_user, user.id, 0),
      hourly_rate: Map.get(salary_by_user, user.id),
      hours_record: Map.get(hr_by_user, user.id)
    }
  end)

  assign(socket, :employees, employees)
end
```

**Note:** The exact function signatures depend on how code interfaces are
generated. `list_sessions!` may take arguments as a map or as keyword options.
Check the generated interface.

**Note:** The `search` filtering happens on the User `:list` read action (ILIKE
on name/email). The legacy code filtered in the main Ecto query.

**Note:** The `archived` argument is a no-op in the legacy code (TODO comment
says no `archived` column exists). Keep the argument but skip it for now.

### `Employee` LiveView

File: `lib/firmowid_web/management/views/employee.ex`

Currently calls `AshSession.employee_details(id, date, scope: scope)`.

After:

```elixir
# 1. Load user with avatar
user = Core.get_user!(id, opts)
  |> Ash.load!([avatar_blob: [:url]], tenant: tenant, authorize?: false, actor: %{})

# 2. Sessions for this user+month, grouped by project+title
sessions = Timetracker.list_sessions!(
  %{user_id: id, month: date.month, year: date.year},
  opts
) |> Ash.load!(:duration, opts)

sessions_by_project = Enum.group_by(sessions, & &1.project_id)

grouped = sessions
  |> Enum.group_by(&{&1.project_id, &1.title})
  |> Enum.map(fn {{pid, title}, ss} ->
    %{project_id: pid, title: title, duration: ss |> Enum.map(& &1.duration) |> Enum.sum()}
  end)
  |> Enum.sort_by(& &1.duration, :desc)

# 3. Projects for this user
projects = Timetracker.list_projects!(%{user_id: id}, opts)
  |> Enum.map(fn project ->
    project_sessions = Map.get(sessions_by_project, project.id, [])
    Map.put(project, :sessions, project_sessions)
  end)

# 4. Salary and hours record
[salary] = Payroll.as_of!(date, %{user_id: id}, opts)  # or nil
hourly_rate = salary && salary.hourly_rate || Decimal.new(0)

hours_record = Timetracker.list_hours_records!(
  %{user_id: id, month: date.month, year: date.year}, opts
) |> List.first()

# 5. Compose
total_time = sessions |> Enum.map(& &1.duration) |> Enum.sum()

employee = user
  |> Map.put(:projects, projects)
  |> Map.put(:hourly_rate, hourly_rate)
  |> Map.put(:hours_record, hours_record)
  |> Map.put(:time_worked, total_time)
```

### `Project` LiveView

File: `lib/firmowid_web/management/views/project.ex`

Currently calls:
- `AshProject.project_total_cost(id, date, scope:)`
- `AshProject.project_month_users_with_cost(id, date, scope:)`
- `AshProject.project_users_with_cost_all_time(id, scope:)`
- `AshProject.project_total_cost_all_time(id, scope:)`
- `AshSession.total_time_worked(%{project_id: id, ...}, scope:)`

After: compose in `assign_project_data/1`:

```elixir
# For active project (month view):

# Time worked per user this month for this project
sessions = Timetracker.list_sessions!(
  %{project_id: project.id, month: date.month, year: date.year},
  opts
) |> Ash.load!(:duration, opts)

time_by_user = group_time_by_user(sessions)
total_time = sessions |> Enum.map(& &1.duration) |> Enum.sum()

# Salaries
salaries = Payroll.as_of!(date, opts)
salary_by_user = Map.new(salaries, &{&1.user_id, &1.hourly_rate})

# Hours records
hrs = Timetracker.list_hours_records!(%{month: date.month, year: date.year}, opts)
hr_by_user = Map.new(hrs, &{&1.user_id, &1})

# Project membership
members = Timetracker.list_project_users!(%{project_id: project.id}, opts)
member_ids = MapSet.new(members, & &1.user_id)

# All user IDs (members + users with sessions)
all_user_ids = MapSet.union(member_ids, MapSet.new(Map.keys(time_by_user)))

# Load users with avatars
users = Core.list_users!(opts)
  |> Enum.filter(&MapSet.member?(all_user_ids, &1.id))
  |> Enum.map(fn user ->
    user = Ash.load!(user, [avatar_blob: [:url]], tenant: tenant, authorize?: false, actor: %{})
    time = Map.get(time_by_user, user.id, 0)
    rate = Map.get(salary_by_user, user.id)
    hours = Timetracker.seconds_to_hours(time)
    cost = rate && Decimal.mult(rate, Decimal.new(hours))

    user
    |> Map.put(:time_worked, time)
    |> Map.put(:hourly_rate, rate)
    |> Map.put(:cost, cost)
    |> Map.put(:hours_record, Map.get(hr_by_user, user.id))
    |> Map.put(:removed_from_project, not MapSet.member?(member_ids, user.id))
    |> Map.put(:expanded, false)
  end)
  |> Enum.sort_by(&{&1.removed_from_project, &1.name, &1.email})

total_cost = users |> Enum.map(& &1.cost) |> Enum.reject(&is_nil/1) |> Enum.reduce(Decimal.new(0), &Decimal.add/2)
```

**Critical:** `Timetracker.seconds_to_hours/1` must be used for ALL hours
conversions. It ceils — this is a business rule.

### `Projects` LiveView (list active/archived)

File: `lib/firmowid_web/management/views/projects.ex`

Currently calls `AshProject.list_active(date, search:, scope:)`.

After:

```elixir
# Read projects with duration aggregate
projects = Timetracker.Project
  |> Ash.Query.for_read(:list, %{active_only: true, search: search}, opts)
  |> Ash.Query.aggregate(:duration, :sum, :sessions,
       field: :duration, default: 0, query: month_filter(date))
  |> Ash.Query.load(counterparty: [:display_label])
  |> maybe_sort(search)
  |> Ash.read!(opts)
  |> Enum.map(fn project ->
    seconds = project.aggregates[:duration] || 0
    Map.put(project, :hours, Timetracker.seconds_to_hours(seconds))
  end)

Firmowid.Repo.drop_paradedb_unnamed()
```

**Note:** `Repo.drop_paradedb_unnamed()` is a ParadeDB cleanup call that must
stay after ParadeDB searches.

### `ProjectForm` LiveView

File: `lib/firmowid_web/management/views/project_form.ex`

Currently calls `AshProject.project_users_with_removed(project_id, scope:)`.

After:

```elixir
# Project members
members = Timetracker.list_project_users!(%{project_id: project_id}, opts)
member_ids = MapSet.new(members, & &1.user_id)

# Users with sessions for this project
sessions = Timetracker.list_sessions!(%{project_id: project_id}, opts)
session_user_ids = sessions |> Enum.map(& &1.user_id) |> MapSet.new()

# All relevant user IDs
all_ids = MapSet.union(member_ids, session_user_ids)

# Load users with avatars
users = Core.list_users!(opts)
  |> Enum.filter(&MapSet.member?(all_ids, &1.id))
  |> Enum.map(fn user ->
    user
    |> Ash.load!([avatar_blob: [:url]], tenant: tenant, authorize?: false, actor: %{})
    |> Map.put(:removed_from_project, not MapSet.member?(member_ids, user.id))
  end)
  |> Enum.sort_by(&{&1.name, &1.email})
```

Also replace `Firmowid.Accounts.User` on line 173 → `Firmowid.Ash.Core.User`.

### `HoursRecord.Index` LiveView

File: `lib/firmowid_web/hours_record/views/index.ex`

Currently calls `AshProject.user_projects_with_duration(user_id, date, scope:)`.

After:

```elixir
# User's projects with duration for this month
projects = Timetracker.Project
  |> Ash.Query.for_read(:list, %{user_id: user_id}, opts)
  |> Ash.Query.aggregate(:duration, :sum, :sessions,
       field: :duration, default: 0,
       query: Ash.Query.filter(Session,
         user_id == ^user_id and
         fragment("extract(month from ?) = ?", start_datetime, ^month) and
         fragment("extract(year from ?) = ?", start_datetime, ^year)
       ))
  |> Ash.read!(opts)
  |> Enum.map(fn project ->
    Map.put(project, :duration, project.aggregates[:duration] || 0)
  end)
  |> Enum.sort_by(& &1.duration, :desc)
```

### `Csv` controller

File: `lib/firmowid_web/timetracker/controllers/csv.ex`

**Salaries CSV** — currently calls `AshUserSalary.salaries_csv(month, year, scope:)`.

After:

```elixir
# Compose in controller
users = Core.list_users!(opts)
salaries = Payroll.as_of!(Date.new!(year, month, 1), opts)
salary_by_user = Map.new(salaries, &{&1.user_id, &1.hourly_rate})

hrs = Timetracker.list_hours_records!(%{month: month, year: year}, opts)
hr_by_user = Map.new(hrs, &{&1.user_id, &1})

csv = users
  |> Enum.filter(&Map.has_key?(hr_by_user, &1.id))
  |> Enum.sort_by(& &1.name)
  |> Enum.map(fn user ->
    hr = hr_by_user[user.id]
    rate = salary_by_user[user.id]
    salary = rate && Decimal.mult(rate, hr.number_of_hours) || Decimal.new(0)
    %{name: user.name, hourly_rate: rate, number_of_hours: hr.number_of_hours, salary: salary}
  end)
  |> CSV.encode(headers: [...])
  |> Enum.join()
```

**Project tasks CSV** — currently calls `AshSession.project_tasks_csv(...)`.

After:

```elixir
sessions = Timetracker.list_sessions!(
  %{project_id: project_id, month: month, year: year}, opts
) |> Ash.load!(:duration, opts)

csv = sessions
  |> Enum.group_by(& &1.title)
  |> Enum.map(fn {title, ss} ->
    %{title: title, duration: Timetracker.seconds_to_hours(Enum.sum(Enum.map(ss, & &1.duration)))}
  end)
  |> Enum.sort_by(& &1.duration, :desc)
  |> CSV.encode(headers: [title: "Zadanie", duration: "Czas trwania (godziny)"])
  |> Enum.join()
```

## Files deleted

| File | Lines |
|------|-------|
| `lib/firmowid/ash/timetracker/project_costs.ex` | 286 |

## Files modified

| File | What changes |
|------|-------------|
| `lib/firmowid/ash/timetracker/session.ex` | Delete 7 generic actions + ~200 lines of private helpers. Add `:list` read. |
| `lib/firmowid/ash/timetracker/project.ex` | Delete 8 generic actions + ~100 lines of private helpers. Add `:list` read. Delete `:searchable`, `:by_ids`, `:with_users`, `:for_user`, `:active_for_user` reads. |
| `lib/firmowid/ash/timetracker/hours_record.ex` | Delete `:month_hours_records` generic action. Add `:list` read. |
| `lib/firmowid/ash/timetracker/project_user.ex` | Add `:list` read. |
| `lib/firmowid/ash/timetracker/timetracker.ex` | Add code interfaces for all new `:list` reads. |
| `lib/firmowid/ash/payroll/user_salary.ex` | Delete `salary_as_of_subquery/2`. Delete `:salaries_csv` generic action. |
| `lib/firmowid_web/management/views/employees.ex` | Rewrite `assign_employees` — compose domain calls. |
| `lib/firmowid_web/management/views/employee.ex` | Rewrite `handle_params` — compose domain calls. |
| `lib/firmowid_web/management/views/project.ex` | Rewrite `assign_project_data` — compose domain calls + inline cost calc. |
| `lib/firmowid_web/management/views/projects.ex` | Rewrite listing — use `:list` + aggregate at callsite. |
| `lib/firmowid_web/management/views/project_form.ex` | Rewrite user loading — compose domain calls. |
| `lib/firmowid_web/hours_record/views/index.ex` | Rewrite — compose domain calls. |
| `lib/firmowid_web/timetracker/controllers/csv.ex` | Rewrite both CSV endpoints — compose domain calls. |

## Verification

After completing:

```bash
mix compile --warnings-as-errors
```

Grep for zero raw Ecto in timetracker:

```bash
grep -rn 'import Ecto.Query' lib/firmowid/ash/timetracker/
grep -rn 'Firmowid.Repo\.' lib/firmowid/ash/timetracker/
grep -rn 'from(' lib/firmowid/ash/timetracker/
```

All should return zero results.

**Exception:** `Repo.drop_paradedb_unnamed()` in project listing callsite is
allowed — it's a ParadeDB cleanup, not a domain query.

Then full:

```bash
mix check
```

Manual test:
1. Employees list — correct time worked, hourly rates, hours records
2. Employee detail — projects with sessions, salary, hours record
3. Project view (active) — per-user costs, totals, month-over-month delta
4. Project view (archived) — all-time totals
5. Project form — users with removed_from_project flag
6. Hours record index — all users with their records
7. CSV downloads — salaries CSV, project tasks CSV

## Dependencies

- Phase E (Core `:list_users` code interface exists)
- No dependency on phases F or other G steps — can be done in parallel with G1-G6
