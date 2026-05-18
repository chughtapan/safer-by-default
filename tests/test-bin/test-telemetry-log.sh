#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/../test-helpers.sh"

PLUGIN_DIR="$(cd "$HERE/../.." && pwd)"
BIN="$PLUGIN_DIR/bin/safer-telemetry-log"

test_requires_event_type() {
  local rc
  "$BIN" >/dev/null 2>&1; rc=$?
  assert_nonzero "$rc" "missing --event-type should fail"
}

test_writes_event() {
  local state
  state=$(mktemp -d)
  SAFER_STATE_DIR="$state" "$BIN" --event-type safer.skill_run --modality contract --session abc-123
  local out
  out=$(cat "$state/analytics/events.jsonl")
  rm -rf "$state"
  assert_contains "$out" '"event_type":"safer.skill_run"' "event_type present"
  assert_contains "$out" '"modality":"spec"' "modality present"
  assert_contains "$out" '"session":"abc-123"' "session present"
  assert_contains "$out" '"ts":"' "timestamp present"
}

test_numeric_fields() {
  local state
  state=$(mktemp -d)
  SAFER_STATE_DIR="$state" "$BIN" --event-type safer.skill_end \
    --modality contract --duration-s 42 --issue 7
  local out
  out=$(cat "$state/analytics/events.jsonl")
  rm -rf "$state"
  assert_contains "$out" '"duration_s":42' "duration unquoted"
  assert_contains "$out" '"issue":7' "issue unquoted"
}

test_escapes_quotes() {
  local state
  state=$(mktemp -d)
  SAFER_STATE_DIR="$state" "$BIN" --event-type safer.stop_rule_fired \
    --modality implement-junior --cause 'needs "escape"'
  local out
  out=$(cat "$state/analytics/events.jsonl")
  rm -rf "$state"
  # JSON escape is \" (one backslash + quote). In single quotes, this
  # literal sequence is preserved.
  assert_contains "$out" '"cause":"needs \"escape\""' "quotes escaped"
}

run_test "safer-telemetry-log requires --event-type" test_requires_event_type
run_test "safer-telemetry-log writes structured event" test_writes_event
run_test "safer-telemetry-log numeric fields unquoted" test_numeric_fields
run_test "safer-telemetry-log escapes quotes in strings" test_escapes_quotes
report
