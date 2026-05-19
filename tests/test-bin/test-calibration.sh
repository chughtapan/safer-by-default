#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/../test-helpers.sh"

PLUGIN_DIR="$(cd "$HERE/../.." && pwd)"
BIN="$PLUGIN_DIR/bin/safer-calibration"
LOG="$PLUGIN_DIR/bin/safer-telemetry-log"

# Seed a state dir with a known set of events
seed_state() {
  local state="$1"
  mkdir -p "$state/analytics"
  # Use safer-telemetry-log so timestamps are current (within window)
  # Healthy modality: contract (5 runs, 1 escalation)
  for _ in 1 2 3 4 5; do
    SAFER_STATE_DIR="$state" "$LOG" --event-type safer.skill_run --modality contract --session t-$RANDOM >/dev/null 2>&1
  done
  SAFER_STATE_DIR="$state" "$LOG" --event-type safer.escalation_triggered --modality contract --session t-$RANDOM >/dev/null 2>&1
  # Gate candidate: verify (12 runs, 0 stop/escl)
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12; do
    SAFER_STATE_DIR="$state" "$LOG" --event-type safer.skill_run --modality verify --session t-$RANDOM >/dev/null 2>&1
  done
  # Calibration issue: implement-junior (5 runs, 2 reverts = 40%)
  for _ in 1 2 3 4 5; do
    SAFER_STATE_DIR="$state" "$LOG" --event-type safer.skill_run --modality implement-junior --session t-$RANDOM >/dev/null 2>&1
  done
  SAFER_STATE_DIR="$state" "$LOG" --event-type safer.scope_reverted --modality implement-junior --session t-$RANDOM >/dev/null 2>&1
  SAFER_STATE_DIR="$state" "$LOG" --event-type safer.scope_reverted --modality implement-junior --session t-$RANDOM >/dev/null 2>&1
}

test_no_events() {
  local state
  state=$(mktemp -d)
  mkdir -p "$state/analytics"
  : > "$state/analytics/events.jsonl"
  local out
  out=$(SAFER_STATE_DIR="$state" "$BIN" 7d 2>&1)
  rm -rf "$state"
  assert_contains "$out" "no events yet" "empty events handled"
}

test_tags_healthy() {
  local state
  state=$(mktemp -d)
  seed_state "$state"
  local out
  out=$(SAFER_STATE_DIR="$state" "$BIN" 7d 2>&1)
  rm -rf "$state"
  assert_contains "$out" "contract" "contract row present"
  assert_contains "$out" "HEALTHY" "HEALTHY tag present somewhere"
}

test_tags_gate_candidate() {
  local state
  state=$(mktemp -d)
  seed_state "$state"
  local out
  out=$(SAFER_STATE_DIR="$state" "$BIN" 7d 2>&1)
  rm -rf "$state"
  # Find the verify row
  local verify_line
  verify_line=$(printf '%s\n' "$out" | grep "^verify ")
  assert_contains "$verify_line" "GATE_CANDIDATE" "verify has GATE_CANDIDATE"
}

test_tags_calibration_issue() {
  local state
  state=$(mktemp -d)
  seed_state "$state"
  local out
  out=$(SAFER_STATE_DIR="$state" "$BIN" 7d 2>&1)
  rm -rf "$state"
  local junior_line
  junior_line=$(printf '%s\n' "$out" | grep "^implement-junior")
  assert_contains "$junior_line" "CALIBRATION_ISSUE" "implement-junior flagged"
}

run_test "calibration handles empty events" test_no_events
run_test "calibration tags HEALTHY modalities" test_tags_healthy
run_test "calibration tags GATE_CANDIDATE" test_tags_gate_candidate
run_test "calibration tags CALIBRATION_ISSUE" test_tags_calibration_issue
report
