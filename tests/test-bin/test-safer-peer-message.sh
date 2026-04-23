#!/usr/bin/env bash
# Tests for bin/safer-peer-message CLI (SPEC r4.1 §5(d)).
# Exercises each named exit code path; does not reach real transport.

set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/../test-helpers.sh"

REPO_ROOT="$(cd "$HERE/../.." && pwd)"
CLI="$REPO_ROOT/bin/safer-peer-message"

# run_cli [--env K=V ...] <flag> <arg> ... → echoes the CLI's exit code.
run_cli() {
  local env_args=()
  while [ "${1:-}" = "--env" ]; do
    env_args+=("$2")
    shift 2
  done
  local rc=0
  env -i HOME="$HOME" PATH="$PATH" "${env_args[@]}" "$CLI" "$@" >/dev/null 2>&1 </dev/null || rc=$?
  echo "$rc"
}

test_usage_missing_to_role() {
  local rc; rc=$(run_cli --kind status-update --body-stdin)
  assert_equal "$rc" "64" "missing --to-role is UsageError"
}

test_usage_flag_without_value() {
  # --to-role with no trailing value must be UsageError (not a shift-2 crash).
  local rc; rc=$(run_cli --to-role)
  assert_equal "$rc" "64" "value-taking flag with no value is UsageError"
}

test_usage_invalid_to_role() {
  local rc; rc=$(run_cli --to-role rogue --kind status-update --body-stdin)
  assert_equal "$rc" "64" "invalid --to-role is UsageError"
}

test_usage_invalid_kind() {
  local rc; rc=$(run_cli --to-role reviewer --kind greet --body-stdin)
  assert_equal "$rc" "64" "invalid --kind is UsageError"
}

test_usage_no_body_source() {
  local rc; rc=$(run_cli --to-role reviewer --kind review-request)
  assert_equal "$rc" "64" "no body source is UsageError"
}

test_transport_failed_missing_env() {
  local rc; rc=$(run_cli --to-role reviewer --kind review-request \
                        --artifact-url https://x --body-stdin)
  assert_equal "$rc" "30" "missing MoltZap env is TransportFailed"
}

test_channel_disallowed_architect_to_implementer() {
  local rc; rc=$(run_cli \
    --env MOLTZAP_LOCAL_SENDER_ID=sender-a --env AO_SESSION=sess-a \
    --env AO_CALLER_TYPE=worker --env MOLTZAP_SESSION_ROLE=architect \
    --to-role implementer --kind status-update --body-stdin)
  assert_equal "$rc" "20" "architect→implementer direct is ChannelDisallowed"
}

test_channel_disallowed_reviewer_sideways() {
  local rc; rc=$(run_cli \
    --env MOLTZAP_LOCAL_SENDER_ID=sender-r --env AO_SESSION=sess-r \
    --env AO_CALLER_TYPE=worker --env MOLTZAP_SESSION_ROLE=reviewer \
    --to-role reviewer --kind review-request --body-stdin)
  assert_equal "$rc" "20" "reviewer→reviewer is ChannelDisallowed"
}

test_usage_worker_without_session_role() {
  # Env-var misconfig caught at the CLI layer is UsageError, not a
  # payload DecodeFailed — the flags are well-formed; the session env
  # is incomplete.
  local rc; rc=$(run_cli \
    --env MOLTZAP_LOCAL_SENDER_ID=sender-w --env AO_SESSION=sess-w \
    --env AO_CALLER_TYPE=worker \
    --to-role orchestrator --kind status-update --body-stdin)
  assert_equal "$rc" "64" "worker without MOLTZAP_SESSION_ROLE is UsageError"
}

test_usage_worker_cannot_spoof_orchestrator() {
  # SPEC §5(a) / Invariant 2: a worker session MUST NOT mint itself as
  # the orchestrator. MOLTZAP_SESSION_ROLE=orchestrator with
  # AO_CALLER_TYPE=worker is a UsageError.
  local rc; rc=$(run_cli \
    --env MOLTZAP_LOCAL_SENDER_ID=sender-w --env AO_SESSION=sess-w \
    --env AO_CALLER_TYPE=worker --env MOLTZAP_SESSION_ROLE=orchestrator \
    --to-role orchestrator --kind status-update --body-stdin)
  assert_equal "$rc" "64" "worker cannot spoof orchestrator role"
}

test_usage_unreadable_body_file() {
  # Create a file with no read permission and confirm UsageError (64),
  # not the set-e generic exit 1 from cat.
  local tmpf; tmpf=$(mktemp)
  chmod 000 "$tmpf"
  local rc; rc=$(run_cli \
    --env MOLTZAP_LOCAL_SENDER_ID=sender-a --env AO_SESSION=sess-a \
    --env AO_CALLER_TYPE=worker --env MOLTZAP_SESSION_ROLE=architect \
    --to-role orchestrator --kind status-update --body-file "$tmpf")
  chmod 644 "$tmpf" 2>/dev/null || true
  rm -f "$tmpf"
  assert_equal "$rc" "64" "unreadable --body-file is UsageError"
}

test_transport_failed_without_shim() {
  local rc; rc=$(run_cli \
    --env MOLTZAP_LOCAL_SENDER_ID=sender-a --env AO_SESSION=sess-a \
    --env AO_CALLER_TYPE=worker --env MOLTZAP_SESSION_ROLE=architect \
    --to-role orchestrator --kind status-update --body-stdin)
  assert_equal "$rc" "30" "valid call without transport shim is TransportFailed"
}

echo "[test-safer-peer-message]"
run_test "missing --to-role is UsageError"              test_usage_missing_to_role
run_test "value-taking flag with no value is UsageError" test_usage_flag_without_value
run_test "invalid --to-role is UsageError"              test_usage_invalid_to_role
run_test "invalid --kind is UsageError"                 test_usage_invalid_kind
run_test "no body source is UsageError"                 test_usage_no_body_source
run_test "missing MoltZap env is TransportFailed"       test_transport_failed_missing_env
run_test "architect→implementer is ChannelDisallowed"   test_channel_disallowed_architect_to_implementer
run_test "reviewer→reviewer is ChannelDisallowed"       test_channel_disallowed_reviewer_sideways
run_test "worker without session role is UsageError"    test_usage_worker_without_session_role
run_test "worker cannot spoof orchestrator role"        test_usage_worker_cannot_spoof_orchestrator
run_test "unreadable --body-file is UsageError"         test_usage_unreadable_body_file
run_test "valid call without transport shim is TF"      test_transport_failed_without_shim

report
