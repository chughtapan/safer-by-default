#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/../test-helpers.sh"

PLUGIN_DIR="$(cd "$HERE/../.." && pwd)"
BIN="$PLUGIN_DIR/bin/safer-update-check"

test_fresh_cache_quiet() {
  local state
  state=$(mktemp -d)
  echo "$(date +%s)" > "$state/last-update-check"
  local out
  out=$(SAFER_STATE_DIR="$state" "$BIN")
  rm -rf "$state"
  # Fresh cache should produce no output
  assert_equal "$out" "" "fresh cache → no output"
}

test_no_network_silent() {
  local state
  state=$(mktemp -d)
  # Force poll with an unreachable URL
  local out
  out=$(SAFER_STATE_DIR="$state" SAFER_FORCE_POLL=1 \
        SAFER_REMOTE_URL="http://127.0.0.1:1/VERSION" "$BIN" 2>/dev/null)
  rm -rf "$state"
  assert_equal "$out" "" "unreachable remote → silent"
}

test_mock_upgrade_available() {
  local state fakedir
  state=$(mktemp -d)
  fakedir=$(mktemp -d)
  echo "9.9.9" > "$fakedir/VERSION"
  # Serve the fake VERSION via file:// URL
  local out
  out=$(SAFER_STATE_DIR="$state" SAFER_FORCE_POLL=1 \
        SAFER_REMOTE_URL="file://$fakedir/VERSION" "$BIN" 2>/dev/null)
  rm -rf "$state" "$fakedir"
  # Expect upgrade available with the fake version
  assert_contains "$out" "UPGRADE_AVAILABLE" "upgrade detected"
  assert_contains "$out" "9.9.9" "remote version present"
}

test_versions_match_silent() {
  local state fakedir local_ver
  state=$(mktemp -d)
  fakedir=$(mktemp -d)
  local_ver=$(tr -d '[:space:]' < "$PLUGIN_DIR/VERSION")
  echo "$local_ver" > "$fakedir/VERSION"
  local out
  out=$(SAFER_STATE_DIR="$state" SAFER_FORCE_POLL=1 \
        SAFER_REMOTE_URL="file://$fakedir/VERSION" "$BIN" 2>/dev/null)
  rm -rf "$state" "$fakedir"
  assert_equal "$out" "" "matching versions → no output"
}

test_missing_version_file_silent() {
  local state fakedir
  state=$(mktemp -d)
  fakedir=$(mktemp -d)
  local out rc
  out=$(SAFER_STATE_DIR="$state" SAFER_FORCE_POLL=1 \
        SAFER_REMOTE_URL="file://$fakedir/NOTEXIST" \
        PLUGIN_DIR="$fakedir" "$BIN" 2>/dev/null); rc=$?
  rm -rf "$state" "$fakedir"
  assert_zero "$rc" "missing VERSION → exit 0"
  assert_equal "$out" "" "missing VERSION → silent"
}

test_stale_cache_triggers_poll() {
  local state fakedir
  state=$(mktemp -d)
  fakedir=$(mktemp -d)
  # Write a cache timestamp far in the past (7200s ago = stale)
  echo "$(($(date +%s) - 7200))" > "$state/last-update-check"
  echo "9.9.9" > "$fakedir/VERSION"
  local out
  out=$(SAFER_STATE_DIR="$state" \
        SAFER_REMOTE_URL="file://$fakedir/VERSION" "$BIN" 2>/dev/null)
  rm -rf "$state" "$fakedir"
  assert_contains "$out" "UPGRADE_AVAILABLE" "stale cache triggers poll"
}

test_garbage_cache_treated_as_zero() {
  local state fakedir
  state=$(mktemp -d)
  fakedir=$(mktemp -d)
  # Non-numeric cache file → LAST=0 → treated as stale
  echo "not-a-number" > "$state/last-update-check"
  echo "9.9.9" > "$fakedir/VERSION"
  local out
  out=$(SAFER_STATE_DIR="$state" \
        SAFER_REMOTE_URL="file://$fakedir/VERSION" "$BIN" 2>/dev/null)
  rm -rf "$state" "$fakedir"
  assert_contains "$out" "UPGRADE_AVAILABLE" "garbage cache → stale → polls"
}

run_test "safer-update-check stays silent with fresh cache" test_fresh_cache_quiet
run_test "safer-update-check is silent on network failure" test_no_network_silent
run_test "safer-update-check emits UPGRADE_AVAILABLE when mismatch" test_mock_upgrade_available
run_test "safer-update-check: matching versions → silent" test_versions_match_silent
run_test "safer-update-check: missing VERSION file → silent exit 0" test_missing_version_file_silent
run_test "safer-update-check: stale cache triggers poll" test_stale_cache_triggers_poll
run_test "safer-update-check: garbage cache file treated as stale" test_garbage_cache_treated_as_zero
report
