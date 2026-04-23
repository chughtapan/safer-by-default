#!/usr/bin/env bash
# Tests for bin/safer-peer-message CLI (SPEC r4.1 §5(d)).
# Exercises each named exit code path; does not reach real transport.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CLI="$REPO_ROOT/bin/safer-peer-message"

_fail=0
_pass=0
_total=0

_log() { printf '%s\n' "$*" >&2; }

assert_exit() {
  local expected=$1
  local desc=$2
  local actual=$3
  _total=$(( _total + 1 ))
  if [ "$actual" -eq "$expected" ]; then
    _pass=$(( _pass + 1 ))
    _log "  ✓ $desc (exit $actual)"
  else
    _fail=$(( _fail + 1 ))
    _log "  ✗ $desc: expected exit $expected, got $actual"
  fi
}

_run() {
  env -i HOME="$HOME" PATH="$PATH" "$@" </dev/null >/dev/null 2>&1 || true
  local rc=$?
  # With set -e disabled inside subshell, rc is the last command's exit.
  printf '%s' "$rc"
}

run_cli() {
  # Runs the CLI in a subshell with a controlled env. Prints only the
  # exit code.
  local env_args=()
  while [ "${1:-}" = "--env" ]; do
    env_args+=("$2")
    shift 2
  done
  local rc=0
  env -i HOME="$HOME" PATH="$PATH" "${env_args[@]}" "$CLI" "$@" >/dev/null 2>&1 || rc=$?
  echo "$rc"
}

_log "[test-safer-peer-message]"

# 64 UsageError — missing --to-role
rc=$(run_cli --kind status-update --body-stdin)
assert_exit 64 "missing --to-role is UsageError" "$rc"

# 64 UsageError — invalid --to-role
rc=$(run_cli --to-role rogue --kind status-update --body-stdin)
assert_exit 64 "invalid --to-role is UsageError" "$rc"

# 64 UsageError — invalid --kind
rc=$(run_cli --to-role reviewer --kind greet --body-stdin)
assert_exit 64 "invalid --kind is UsageError" "$rc"

# 64 UsageError — neither body-file nor body-stdin
rc=$(run_cli --to-role reviewer --kind review-request)
assert_exit 64 "no body source is UsageError" "$rc"

# 30 TransportFailed — valid flags but no MoltZap env
rc=$(run_cli --to-role reviewer --kind review-request --artifact-url https://x --body-stdin)
assert_exit 30 "missing MoltZap env is TransportFailed" "$rc"

# 20 ChannelDisallowed — architect→implementer direct (must go through orchestrator)
rc=$(run_cli \
  --env MOLTZAP_LOCAL_SENDER_ID=sender-a --env AO_SESSION=sess-a \
  --env AO_CALLER_TYPE=worker --env MOLTZAP_SESSION_ROLE=architect \
  --to-role implementer --kind status-update --body-stdin)
assert_exit 20 "architect→implementer direct is ChannelDisallowed" "$rc"

# 20 ChannelDisallowed — reviewer→reviewer sideways
rc=$(run_cli \
  --env MOLTZAP_LOCAL_SENDER_ID=sender-r --env AO_SESSION=sess-r \
  --env AO_CALLER_TYPE=worker --env MOLTZAP_SESSION_ROLE=reviewer \
  --to-role reviewer --kind review-request --body-stdin)
assert_exit 20 "reviewer→reviewer is ChannelDisallowed" "$rc"

# 22 DecodeFailed — worker without MOLTZAP_SESSION_ROLE
rc=$(run_cli \
  --env MOLTZAP_LOCAL_SENDER_ID=sender-w --env AO_SESSION=sess-w \
  --env AO_CALLER_TYPE=worker \
  --to-role orchestrator --kind status-update --body-stdin)
assert_exit 22 "worker without session role is DecodeFailed" "$rc"

# 30 TransportFailed — valid all around, but no safer-peer-outbound-client on PATH
rc=$(run_cli \
  --env MOLTZAP_LOCAL_SENDER_ID=sender-a --env AO_SESSION=sess-a \
  --env AO_CALLER_TYPE=worker --env MOLTZAP_SESSION_ROLE=architect \
  --to-role orchestrator --kind status-update --body-stdin)
assert_exit 30 "valid call without transport shim is TransportFailed" "$rc"

# Exit 0 is unreachable without a real shim; we intentionally do not test it.

echo ""
echo "[test-safer-peer-message] $_pass/$_total passed"
if [ "$_fail" -gt 0 ]; then
  exit 1
fi
exit 0
