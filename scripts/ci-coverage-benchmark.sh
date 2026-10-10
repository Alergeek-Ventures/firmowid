#!/usr/bin/env bash
# CI-only: all four samples use this job's runner, compiled code and catalog.
set -euo pipefail
[[ ${GITHUB_ACTIONS:-} == true && ${GITHUB_EVENT_NAME:-} == workflow_dispatch ]]
[[ ${GITHUB_REF:-} == refs/heads/* && ${GITHUB_REF:-} != refs/heads/main && ${MIX_ENV:-} == test ]]
[[ $(git rev-parse HEAD) == "$GITHUB_SHA" ]]

results="$RUNNER_TEMP/coverage-benchmark"
mkdir -p "$results"
export BENCHMARK_RESULTS="$results"
seed=424242
printf 'sample\tarm\tseconds\texit_status\n' > "$results/timings.tsv"

# Only an allowlist is recorded: never dump environment variables or Docker Env.
python3 - <<'PY' > "$results/provenance.json"
import hashlib, json, os, platform, subprocess
def output(*args):
    return subprocess.check_output(args, text=True).strip()
keys = ["GITHUB_SHA", "GITHUB_REF", "GITHUB_RUN_ID", "GITHUB_RUN_ATTEMPT",
        "GITHUB_WORKFLOW_REF", "GITHUB_WORKFLOW_SHA", "RUNNER_NAME", "RUNNER_OS",
        "RUNNER_ARCH", "ImageOS", "ImageVersion", "BENCHMARK_CATALOG_SHA",
        "BENCHMARK_OTP", "BENCHMARK_ELIXIR", "BENCHMARK_DB_IMAGE",
        "BENCHMARK_S3_IMAGE", "BENCHMARK_CACHE_KEY", "MIX_ENV", "KSEF_ENV",
        "POSTGRES_USER", "POSTGRES_HOST", "DB_PORT", "S3_HOST", "S3_PORT",
        "S3_SCHEME", "S3_BUCKET", "AWS_DEFAULT_REGION"]
data = {k: os.environ.get(k) for k in keys}
data.update(seed=424242, order=["coverage", "no-coverage", "no-coverage", "coverage"],
            kernel=platform.platform(), cpu=output("lscpu"), beam=output("elixir", "--version"))
data["sha256"] = {p: hashlib.sha256(open(p, "rb").read()).hexdigest() for p in
                  ["mix.lock", "scripts/ci-coverage-benchmark.sh", ".github/workflows/elixir-build-and-test.yml",
                   "priv/gettext/pl/LC_MESSAGES/default.po"]}
data["services"] = {}
for service, key in [("db", "BENCHMARK_DB_CONTAINER"), ("s3", "BENCHMARK_S3_CONTAINER")]:
    container = json.loads(output("docker", "inspect", os.environ[key]))[0]
    image = json.loads(output("docker", "image", "inspect", container["Image"]))[0]
    data["services"][service] = dict(container_id=container["Id"], image_id=container["Image"],
                                    repo_digests=image.get("RepoDigests"), mounts=container["Mounts"])
json.dump(data, __import__("sys").stdout, indent=2)
PY

s3_image_id=$(docker inspect --format '{{.Image}}' "$BENCHMARK_S3_CONTAINER")
docker stop "$BENCHMARK_S3_CONTAINER" > "$results/s3-stop.log" 2>&1
fresh_s3=''
cleanup() {
  if [[ -n "$fresh_s3" ]]; then
    docker rm --force --volumes "$fresh_s3" >> "$results/s3-cleanup.log" 2>&1 || true
  fi
}
trap cleanup EXIT

status=0
sample=0
for arm in coverage no-coverage no-coverage coverage; do
  sample=$((sample + 1))
  prefix="$results/$sample-$arm"
  # Recreate a blank S3 container from the already-resolved image ID; restarting
  # would retain uploaded objects. The original job service has no shared state.
  cleanup
  fresh_s3=''
  if ! fresh_s3=$(docker run --detach --publish 8333:8333 \
    --env AWS_ACCESS_KEY_ID --env AWS_SECRET_ACCESS_KEY "$s3_image_id" \
    2> "$prefix-s3-prep.log"); then
    echo "S3 container creation failed for sample $sample" >&2
    status=1
    break
  fi
  docker inspect --format '{{.Id}} {{.Image}}' "$fresh_s3" >> "$prefix-s3-prep.log"
  ready=false
  for _ in {1..60}; do
    if curl --silent --show-error --max-time 2 --output /dev/null http://localhost:8333 \
      2>> "$prefix-s3-prep.log"; then
      ready=true
      break
    fi
    sleep 1
  done
  if [[ "$ready" != true ]]; then
    docker logs "$fresh_s3" >> "$prefix-s3-prep.log" 2>&1
    echo "S3 preparation failed for sample $sample" >&2
    status=1
    break
  fi

  args=(--no-compile --seed "$seed" --slowest 20 --no-color)
  export BENCHMARK_LCOV_DIR="$prefix-cover"
  # Both native tasks run the project's test alias, including the same DB reset.
  # Measure the real CI commands instead of duplicating ExCoveralls internals.
  if [[ "$arm" == coverage ]]; then
    command=(mix coveralls.lcov --output-dir "$BENCHMARK_LCOV_DIR" "${args[@]}")
  else
    command=(mix test "${args[@]}")
  fi
  printf '%q ' "${command[@]}" > "$prefix-command.txt"
  printf '\n' >> "$prefix-command.txt"
  exit_status=0
  /usr/bin/time --format '%e' --output "$prefix-seconds.txt" \
    timeout --signal=TERM --kill-after=30s 15m "${command[@]}" \
    > "$prefix-test.log" 2>&1 || exit_status=$?
  # GNU time includes a diagnostic line for nonzero exits; its last line is time.
  seconds=$(tail -n 1 "$prefix-seconds.txt")
  if [[ "$arm" == coverage && "$exit_status" == 0 && ! -s "$BENCHMARK_LCOV_DIR/lcov.info" ]]; then
    echo "Coverage sample $sample succeeded without an LCOV report" >&2
    status=1
    printf '\nBenchmark validation: missing LCOV report; original command exited 0.\n' >> "$prefix-test.log"
  fi
  printf '%s\t%s\t%s\t%s\n' "$sample" "$arm" "$seconds" "$exit_status" >> "$results/timings.tsv"
  docker logs "$fresh_s3" > "$prefix-s3.log" 2>&1
  if [[ "$exit_status" != 0 ]]; then
    status=1
  fi
done

python3 - <<'PY' | tee "$results/summary.md" >> "$GITHUB_STEP_SUMMARY"
import csv, json, os, statistics
from pathlib import Path
root = Path(os.environ["BENCHMARK_RESULTS"])
p = json.loads((root / "provenance.json").read_text())
rows = list(csv.DictReader((root / "timings.tsv").open(), delimiter="\t"))
print("## Coverage ABBA benchmark (one runner)")
print(f"Code `{p['GITHUB_SHA']}`; catalog `{p['BENCHMARK_CATALOG_SHA']}`; seed `{p['seed']}`.")
print(f"Elixir `{p['BENCHMARK_ELIXIR']}` / OTP `{p['BENCHMARK_OTP']}`; runner `{p['RUNNER_NAME']}` / image `{p['ImageVersion']}`.")
print(f"Cache prefix `{p['BENCHMARK_CACHE_KEY']}` (isolated cold setup, excluded from timing).")
for name, service in p["services"].items():
    print(f"{name}: `{service['image_id']}`; registry digests `{service['repo_digests']}`.")
print("\n| Sample | Arm | Wall seconds | Exit |\n|---|---|---:|---:|")
for r in rows:
    print(f"| {r['sample']} | {r['arm']} | {r['seconds']} | {r['exit_status']} |")
valid = (len(rows) == 4 and all(r["exit_status"] == "0" for r in rows)
         and all((root / f"{r['sample']}-coverage-cover/lcov.info").is_file()
                 and (root / f"{r['sample']}-coverage-cover/lcov.info").stat().st_size > 0
                 for r in rows if r["arm"] == "coverage"))
if valid:
    means = {arm: statistics.mean(float(r["seconds"]) for r in rows if r["arm"] == arm)
             for arm in ("coverage", "no-coverage")}
    delta = means["coverage"] - means["no-coverage"]
    print(f"\nMean coverage {means['coverage']:.2f}s; no coverage {means['no-coverage']:.2f}s; "
          f"difference {delta:+.2f}s ({100 * delta / means['no-coverage']:+.1f}%).")
    for a, b in ((rows[0], rows[1]), (rows[3], rows[2])):
        print(f"Pair {a['sample']}/{b['sample']} coverage delta: "
              f"{float(a['seconds']) - float(b['seconds']):+.2f}s.")
else:
    print("\n**Incomplete or failed samples: do not interpret as a coverage comparison.**")
print("\nWall time includes VM/Mix startup, the shared DB-reset alias, test-file loading, "
      "application startup and LCOV analysis/write. Initial compilation and S3 preparation are outside timing; "
      "both Test tasks use --no-compile, but any alias-triggered recompilation must be checked in the logs. "
      "Both arms use `--slowest 20` (serial trace mode). "
      "See artifact for exact commands, environment allowlist, CPU, hashes, slowest-20 output and service logs.")
PY
exit "$status"
