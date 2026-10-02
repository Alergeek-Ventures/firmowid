#!/usr/bin/env bash
# Private runtime helper for Mix.Tasks.Chatgpt.Tunnel, not a target-selection CLI.
# Mix supplies its numeric OS PID, a resolved trusted executable and fixed args.
# No credentials in argv. No process-group/global kills or independent watchdog.
set +x
set -u

[[ $# -ge 2 && $1 =~ ^[1-9][0-9]*$ && $2 == /* && -x $2 ]] || exit 64
parent_pid=$1
shift
child_pid=
pending_signal=
pending_status=0

cleanup() {
  local status=$?
  # Ignore further shutdown signals while doing bounded cleanup. Never write to
  # stdout/stderr: the BEAM may already be dead and its log pipe closed.
  trap '' INT TERM HUP PIPE
  trap - EXIT
  if [[ -n $child_pid ]]; then
    kill -TERM "$child_pid" 2>/dev/null || :
    for ((attempt = 0; attempt < 50; attempt++)); do
      kill -0 "$child_pid" 2>/dev/null || break
      sleep 0.1
    done
    if kill -0 "$child_pid" 2>/dev/null; then
      kill -KILL "$child_pid" 2>/dev/null || :
    fi
    wait "$child_pid" 2>/dev/null || :
  fi
  exit "$status"
}

forward() {
  local signal=$1 status=$2
  if [[ -z $child_pid ]]; then
    # A trap can run between background launch and recording $!. Defer exit
    # until that PID is owned, so even startup-time signals cannot orphan it.
    pending_signal=$signal
    pending_status=$status
    return
  fi
  # Give the forwarded signal a short grace period before EXIT sends TERM;
  # otherwise adjacent signals can coalesce before the client handles INT/HUP.
  if kill -"$signal" "$child_pid" 2>/dev/null; then
    sleep 0.2
  fi
  exit "$status"
}

trap cleanup EXIT
trap 'forward INT 130' INT
trap 'forward TERM 143' TERM
trap 'forward HUP 129' HUP
trap '' PIPE

kill -0 "$parent_pid" 2>/dev/null || exit 1
# HTTP-only client; stdin is deliberately unavailable. Cloudflare and stdio
# subprocess targets are disabled by Mix, so only this direct child is owned.
"$@" </dev/null &
child_pid=$!
if [[ -n $pending_signal ]]; then
  forward "$pending_signal" "$pending_status"
fi

# Poll in this supervisor, not a separate watchdog that could outlive it. Bash
# reaps completed background children; wait below preserves the client's status.
while kill -0 "$child_pid" 2>/dev/null; do
  kill -0 "$parent_pid" 2>/dev/null || exit 1
  sleep 0.2
done
wait "$child_pid"
status=$?
child_pid=
exit "$status"
