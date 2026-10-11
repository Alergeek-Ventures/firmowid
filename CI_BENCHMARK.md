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
timings are verified on CI; no local tests, compilation or services were run for
this implementation.

## Recorded results

### Coverage A/B

[Run 38096764202](https://github.com/Alergeek-Ventures/firmowid/actions/runs/38096764202)
measured code `aa7f73712343b36b719172f85b456a1d422263ff`, catalog
`90be1aa8041c4da9b798d6fa2b640b98f92704a6`, Elixir 1.20.4 / OTP 29.0.6,
seed 424242. All four samples passed 686 tests/doctests; 7 external cases
were excluded in each sample. Both coverage samples produced LCOV.

| Sample | Coverage | Wall seconds | ExUnit seconds |
|---|---|---:|---:|
| 1 | yes | 113.87 | 37.0 |
| 2 | no | 93.07 | 42.8 |
| 3 | no | 88.16 | 37.2 |
| 4 | yes | 111.73 | 37.8 |

Mean command time: **112.80s with coverage vs 90.61s without**; difference
**+22.19s (+24.5%)**. Adjacent-pair differences were +20.80s and +23.57s.
This is one paired run, not a statistical confidence interval. Coverage remains
enabled in normal CI: this overhead does not justify removing its regression
signal.

Every sample recompiled 545 application files inside the native command despite
the Test task's `--no-compile`. These samples predate the test-alias correction
described below. Consequently the wall times include recompilation and the
DB-reset alias; they are **not pure coverage-instrumentation timings**.
ExUnit times alone do not demonstrate a stable coverage slowdown. The observed
recompilation was investigated separately, not treated as a reason to change
coverage policy or claim that the whole measured difference is instrumentation.

#### Test-alias compilation trigger

The test alias included `ash_postgres.drop --force --force-drop --quiet`.
In installed AshPostgres 2.13.1, `Drop.run/1` resolves repositories through
`AshPostgres.Mix.Helpers.repos!/2`. That helper passes the original arguments
unchanged to `Mix.Task.run("app.config", args)`, which in Elixir 1.20.4 forwards
them to `compile`. Thus the drop's confirmation flag `--force` also forces
application compilation before the test task can honor `--no-compile`.
Ecto's later `ensure_repo/2` removes `--force`, but that is too late for the
earlier AshPostgres helper.

The test alias now omits only `--force`: Ecto 3.14.2 already skips confirmation
when `start_permanent` is false, as it is in test. `--force-drop` remains, keeping
the database reset and forced connection termination. Compilation still runs
normally when source is stale, and CI's strict setup compile remains unchanged.
CI confirmed the correction: ordinary
[Build/Test 38099063734](https://github.com/Alergeek-Ventures/firmowid/actions/runs/38099063734)
and all four post-fix samples passed without application recompilation in the
test command; each passed 686 tests/doctests with 7 external cases excluded.

#### Post-fix coverage measurement

[Run 38099062933](https://github.com/Alergeek-Ventures/firmowid/actions/runs/38099062933)
used code `d7f7c2d4253affe75100bfe0edc3b93b5f4ade6a`, the same catalog,
toolchain, seed and image as the first ABBA run, but a different runner.

| Sample | Coverage | Wall seconds | ExUnit seconds |
|---|---|---:|---:|
| 1 | yes | 73.71 | 41.3 |
| 2 | no | 46.11 | 41.2 |
| 3 | no | 45.78 | 40.2 |
| 4 | yes | 73.80 | 41.3 |

Mean command time: **73.75s with coverage vs 45.95s without**; difference
**+27.81s (+60.5%)**, with adjacent-pair differences +27.60s and +28.02s.
Both coverage samples produced LCOV. This replaces the pre-fix run as the
estimate of practical coverage overhead without forced recompilation. It still
includes native command startup/reset/loading and LCOV output, not only
instrumentation. Coverage remains enabled.

Compared with the earlier runner, command means fell by about 39s with coverage
and 45s without. These are cross-run observations, not controlled same-runner
estimates of the alias correction's savings. The disappearance of the compile
lines in both ordinary tests and every sample confirms the intended behavior.

Primary sources:
[AshPostgres Drop](https://github.com/ash-project/ash_postgres/blob/v2.13.1/lib/mix/tasks/ash_postgres.drop.ex),
[repository loading helper](https://github.com/ash-project/ash_postgres/blob/v2.13.1/lib/mix/helpers.ex),
[Mix app.config](https://github.com/elixir-lang/elixir/blob/v1.20.4/lib/mix/lib/mix/tasks/app.config.ex),
[Ecto drop confirmation](https://github.com/elixir-ecto/ecto/blob/v3.14.2/lib/mix/tasks/ecto.drop.ex).

#### Local development implications

This is a shared project alias, not a CI-only workaround: the same forced
recompilation affected local `mix test`, including focused tests, and the test
stage of `mix check --quick`. Removing the confirmation flag preserves normal
incremental compilation in all those callsites.

There is also a separate, intentional full recompilation during
`gettext.extract --check-up-to-date`: installed Gettext explicitly runs
`compile --force-elixir` / `compile.elixir --force` to collect messages.
The full `mix check` includes that task; `mix check --quick` skips it. This
is not evidence that ordinary source edits or Phoenix reloads must rebuild
the whole project. The development server's incremental-compilation behavior
has not been measured here; do not generalize the test-alias finding to it.

### Cache first-main-scope / warm

Both attempts of each workflow used the identical main commit
`90be1aa8041c4da9b798d6fa2b640b98f92704a6`; no caches were deleted. End-to-end
seconds include runner/job preparation and reporting, not the sum of parallel
jobs:

| Workflow | First main-scope attempt | Warm attempt | Setup/build first → warm |
|---|---:|---:|---:|
| [Quality](https://github.com/Alergeek-Ventures/firmowid/actions/runs/38090823307/attempts/2) | 975 | 161 | 257 → 17 |
| [Build/Test](https://github.com/Alergeek-Ventures/firmowid/actions/runs/38090823330/attempts/2) | 451 | 288 | 243 → 20 |
| [Docker](https://github.com/Alergeek-Ventures/firmowid/actions/runs/38090823328/attempts/2) | 554 | 73 | 496 → 6 |

All attempts succeeded. Warm common setup compiled zero dependency/application
files in Quality and Build/Test. Gettext reused its exact-tree success marker
(48s → less than 1s); both PLT caches hit, eliminating 516s of PLT creation.
Dialyzer still analyzed the application (53s → 51s). Docker reused all executable
build layers; its first attempt was partially cached, not an empty-cache run.

The initial main misses were expected cache-scope isolation: matching PR merge-ref
caches cannot be restored by main. All warm PO files were byte-identical and
selected the exact main SHA. First-attempt artifact downloads returned 404 after
reruns, so baseline/warm PO byte equality could not be independently verified.
Build/Test's coverage command still recompiled 545 files in both attempts;
individual runner timings varied and are not the controlled coverage A/B result.

#### Compatible project PLT fallback

The test-alias correction also exposed over-invalidation of project PLTs:
the v2 exact key **and its only restore prefix** included the digest of all
`mix.exs`/config inputs. Even the removal of a test flag excluded still-existing
compatible main/PR PLTs despite identical dependencies and toolchain.
[Quality 38099063678](https://github.com/Alergeek-Ventures/firmowid/actions/runs/38099063678)
restored the core PLT, missed the project PLT, then added 9,119 modules in
10m57.12s before normal analysis passed. This was not cache eviction or a new
OTP/Elixir version.

The corrected workflow retains the strict exact-key inputs in a v3 namespace,
but allows partial restore with unchanged OS/architecture/Mix environment/exact
OTP and Elixir versions. A final v2 prefix imports existing compatible caches
instead of discarding them. The namespace transition ensures the first v3 run
exercises partial restore and validation rather than hitting an old exact entry.
On any non-exact hit/miss, `mix dialyzer --plt --force-check` checks retained
modules, removes obsolete ones and adds missing ones before saving under the
new exact key. The ordinary Dialyzer analysis remains mandatory; neither
`--no-check` nor `--no-plt` is used. The initial v3 migration's runtime results
are pending CI, so no fallback timing saving is claimed yet.

### Test-value audit and GoCardless

The three pre-change CI rankings consistently put the mocked institution HTTP
429 test at 6.5–6.8s. Req's default backoff sleeps accounted for the delay;
transactions retained their explicit single retry and approximately 0.9–1.0s
delays on 429/500/503. Test-only request options now set `retry_delay: 0`, without
altering production retry configuration or removing any error case. Existing
429 tests additionally assert four institution requests and two transaction
requests.

In [PR #50's ordinary test run](https://github.com/Alergeek-Ventures/firmowid/actions/runs/38096763440),
the two 429 tests passed in 9.2ms and 5.1ms respectively; 686 tests/doctests
passed overall. ABBA samples also retained those request-count assertions.
These timings demonstrate removal of mocked waiting, not an equivalent reduction
in total suite wall time, where async work can overlap.

Keep the valuable LiveView upload/deduplication paths, counterparty lifecycle,
OAuth/tenant/read-list regressions and KSeF XSD validation. No test was removed
solely because it appeared in the slowest-20 ranking. Other variable upload/DB
times and two 50ms PubSub sleeps are optional future investigations, not measured
benefits or blockers for the completed benchmark work.
