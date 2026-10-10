# CI-only coverage benchmark

The existing **Build and Test** workflow accepts the boolean dispatch input
`coverage-benchmark` (default `false`). Push/PR checks and their LCOV reporting
remain unchanged. An explicit `true` manual request on a **non-main branch** runs
the benchmark instead of the production test command; it never publishes coverage
comments or produces the required `Build and test` check. Secret scanning and
image validation still run.

After approval, commit/push this change to `poprawki-ci`, then dispatch the existing
workflow ID/path using that branch definition, e.g. the REST request body:

```json
{"ref":"poprawki-ci","inputs":{"coverage-benchmark":"true"}}
```

Endpoint: `POST /repos/Alergeek-Ventures/firmowid/actions/workflows/elixir-build-and-test.yml/dispatches`.
No new workflow, merge, deployment, local Mix execution or automatic dispatch is
part of this change. Dispatch availability depends on GitHub accepting the branch
definition of the existing workflow; a default-branch registration restriction
must be reported, not bypassed with a merge or another workflow.

## Measurement

One runner executes **coverage / no-coverage / no-coverage / coverage** (ABBA),
seed `424242`, four fresh VMs, bounded to 15 minutes each (120-minute job bound).
Both arms use the same exact SHA, compiled application, PO artifact, generated
keys, environment, OTP/Elixir installation, database service and resolved S3 image
ID. Both native commands drop/recreate/migrate the CI database through the same
project test alias inside the timed interval. Each sample starts a blank S3
container outside that interval. No persistent runner or local
development service is touched. OS/Postgres page caches can still warm during the
sequence; ABBA reduces linear order drift but is not a statistical confidence
interval. Repeat approved CI runs before deciding on small differences.

The normal translation writer is skipped. A read-only job resolves **main HEAD
once**, exports exactly that existing snapshot (`export --version FULL_SHA`, no
fallback or creation), validates its marker, and uploads one shared catalog.
Missing main HEAD snapshots fail explicitly. The branch snapshot is never created.
Main benchmark dispatch is rejected before Accent credentials are used.

The existing setup action is reused with a run/attempt-specific
`coverage-benchmark-RUN_ID-ATTEMPT` prefix for **all** its caches. This neither
restores nor overwrites production cache keys, and avoids competing with parallel
main cache experiments. It performs cold setup before measurement and saves
isolated caches; results are not estimates of whole-job time or production warm
cache hits. No existing cache is removed.
GitHub cache storage/quota is still repository-wide; these isolated saves can
contribute to ordinary quota-based eviction, even though keys never collide.

`/usr/bin/time` measures command startup through exit, including VM/Mix startup,
dependency checks, the shared database-reset alias, test-file loading/compilation,
app startup, ExUnit execution,
and (coverage arm only) instrumentation plus LCOV analysis/write. Initial
application and dependency compilation use the common setup outside timing.
Both Test tasks use `--no-compile`; inspect logs for any recompilation triggered
by the alias's Ash tasks instead of assuming it cannot happen.
Both arms retain `--slowest 20`; Mix makes this serial trace mode with module
preloading, matching the existing production command's diagnostic behavior.

### Verified task behavior

`mix.lock` installs **ExCoveralls 0.18.5**. Its installed
`deps/excoveralls/lib/mix/tasks.ex` forwards test flags and invokes
`Mix.Task.run("test", ["--cover" | args])`: it **does execute the project test
alias**, which drops and sets up the DB. Both arms deliberately use native
commands (`mix test` and `mix coveralls.lcov`) with identical test flags.

The reported difference is the practical command-level cost of coverage, not
pure instrumentation time. Database preparation is common to both arms but
introduces timing variance; compare ExUnit's own durations as well as wall time.
Using native tasks avoids maintaining a copy of ExCoveralls initialization or
changing the application's test alias. Command failure exits are preserved.
Each coverage sample writes LCOV into its own artifact directory, so a failed
later sample cannot be mistaken for the earlier sample's report.

Sources checked: installed ExCoveralls `lib/mix/tasks.ex` and `lib/excoveralls.ex`,
[current ExCoveralls task reference](https://github.com/parroty/excoveralls/blob/master/_autodocs/api-reference/mix-tasks.md),
and version-matched [Mix Test](https://github.com/elixir-lang/elixir/blob/v1.20.4/lib/mix/lib/mix/tasks/test.ex).

## Evidence and failures

Artifact `coverage-benchmark-RUN_ID-ATTEMPT` contains per-sample commands, full
stdout/stderr (including slowest 20), wall seconds, exit codes, preparation/service
logs, both available LCOV files, a summary and exact provenance: SHA/catalog/hash,
runtime versions, runner image/CPU, resolved container image IDs/registry digests,
and an environment allowlist (never credentials). The runner summary reports both
adjacent-pair deltas and arm means only if all four commands succeed. Failed test
samples do not prevent later samples; any failed sample fails the job. Preparation
failure aborts the sequence; evidence upload uses `always()`. A runner termination
can prevent complete evidence/summary, as with any hosted job.

Local verification is limited to Bash/YAML/static checks. Runtime correctness and
timings require the approved CI run; no local tests, compilation or services were
run for this implementation.
