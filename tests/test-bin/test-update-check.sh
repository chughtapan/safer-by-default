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

run_test "safer-update-check stays silent with fresh cache" test_fresh_cache_quiet
run_test "safer-update-check is silent on network failure" test_no_network_silent
run_test "safer-update-check emits UPGRADE_AVAILABLE when mismatch" test_mock_upgrade_available
report
