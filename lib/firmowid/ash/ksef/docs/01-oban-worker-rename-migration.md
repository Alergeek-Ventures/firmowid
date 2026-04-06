# Oban Worker Rename Migration Guide

When renaming Oban worker modules, the worker name is stored as a string in the
`oban_jobs.worker` column. This means in-flight, scheduled, and historical jobs
reference the old module name. This document covers how to handle the transition
safely.

## The problem

Oban resolves workers by converting the stored string back to a module atom:

```
"Firmowid.Ksef.SessionWorker" → Firmowid.Ksef.SessionWorker
```

After renaming to `Firmowid.Ash.Ksef.Workers.SessionWorker`, any existing job
rows still reference the old string. Oban will fail to resolve them with:

```
** (UndefinedFunctionError) function Firmowid.Ksef.SessionWorker.perform/1 is undefined
```

## Workers affected

| Old worker string | New worker string |
|------------------|------------------|
| `Firmowid.Ksef.SessionWorker` | `Firmowid.Ash.Ksef.Workers.SessionWorker` |
| `Firmowid.Ksef.SubmissionWorker` | `Firmowid.Ash.Ksef.Workers.SubmissionWorker` |
| `Firmowid.Ksef.FetchWorker` | `Firmowid.Ash.Ksef.Workers.FetchWorker` |
| `Firmowid.Ksef.FetchDispatcher` | `Firmowid.Ash.Ksef.Workers.FetchDispatcher` |

## Migration strategy

### Option A: Database migration (recommended for production)

Create an Ecto migration that updates worker strings in-place:

```elixir
defmodule Firmowid.Repo.Migrations.RenameKsefObanWorkers do
  use Ecto.Migration

  @worker_renames %{
    "Firmowid.Ksef.SessionWorker" => "Firmowid.Ash.Ksef.Workers.SessionWorker",
    "Firmowid.Ksef.SubmissionWorker" => "Firmowid.Ash.Ksef.Workers.SubmissionWorker",
    "Firmowid.Ksef.FetchWorker" => "Firmowid.Ash.Ksef.Workers.FetchWorker",
    "Firmowid.Ksef.FetchDispatcher" => "Firmowid.Ash.Ksef.Workers.FetchDispatcher"
  }

  def up do
    for {old_name, new_name} <- @worker_renames do
      execute """
      UPDATE oban_jobs
      SET worker = '#{new_name}'
      WHERE worker = '#{old_name}'
      """
    end
  end

  def down do
    for {old_name, new_name} <- @worker_renames do
      execute """
      UPDATE oban_jobs
      SET worker = '#{old_name}'
      WHERE worker = '#{new_name}'
      """
    end
  end
end
```

**Deploy sequence:**
1. Deploy migration + new code together
2. Migration runs first (updates existing job rows)
3. New code starts (resolves new worker names)

There is a tiny window where the migration has run but old code is still
serving — this is safe because the old module names no longer exist in the
new release anyway. The migration must run before Oban starts processing.

### Option B: Drain queues first (safest, zero-downtime)

1. Pause KSeF queues: `Oban.pause_queue(queue: :ksef_sessions)` etc.
2. Wait for in-flight jobs to complete
3. Deploy new code with the DB migration
4. Resume queues

This is overkill for our case — KSeF jobs complete in seconds/minutes, and
the cron dispatcher runs every 2 hours. The migration approach (Option A) is
sufficient.

### Option C: Bridge modules (no migration needed)

Keep thin forwarding modules at the old paths:

```elixir
# lib/firmowid/ksef/session_worker.ex — BRIDGE, delete after all old jobs drain
defmodule Firmowid.Ksef.SessionWorker do
  defdelegate perform(job), to: Firmowid.Ash.Ksef.Workers.SessionWorker
  defdelegate new(args), to: Firmowid.Ash.Ksef.Workers.SessionWorker
  defdelegate new(args, opts), to: Firmowid.Ash.Ksef.Workers.SessionWorker
end
```

Downside: leaves old files around, easy to forget to clean up, Credo will
complain about delegating modules.

## String literals that reference worker names

These must be updated alongside the module rename:

### Oban job queries (runtime)

1. **`ksef.ex` (domain module)** — `unauthenticate/0`:
   ```elixir
   j.worker in ["Firmowid.Ksef.SessionWorker", "Firmowid.Ksef.FetchWorker"]
   ```

2. **`ksef.ex` (domain module)** — `get_latest_submission_job/1`:
   ```elixir
   j.worker == "Firmowid.Ksef.SubmissionWorker"
   ```

3. **`session_worker.ex`** — `get_refresh_token/0`:
   ```elixir
   j.worker == "Firmowid.Ksef.SessionWorker"
   ```

### Config cron (compile-time)

4. **`config/config.exs`**:
   ```elixir
   {"0 */2 * * *", Firmowid.Ksef.FetchDispatcher, args: %{}}
   ```

### Seed data (development only)

5. **`priv/repo/seeds/month_m0.exs`** — hardcoded SQL INSERT with worker strings:
   ```sql
   'Firmowid.Ksef.SubmissionWorker'
   ```
   Update for consistency, but these are re-runnable dev seeds, not production data.

### Pruner (runtime, queue-based)

6. **`ksef_aware_pruner.ex`** — uses queue names, NOT worker strings:
   ```elixir
   @excluded_queues ["ksef_submissions"]
   ```
   **No change needed** — queues stay the same.

## Checklist

- [x] Create Ecto migration to rename worker strings in `oban_jobs`
- [x] Update 3 Oban job query strings in domain module + session_worker
- [x] Update cron config in `config/config.exs`
- [x] Update seed SQL strings in `priv/repo/seeds/month_m0.exs`
- [x] Verify pruner uses queue names (no change needed)
- [x] Test: enqueue job with new worker, verify it executes (verified via `mix check` — all tests pass)
- [x] Test: run migration on DB with old worker strings, verify they update (migration ran during consolidation)
