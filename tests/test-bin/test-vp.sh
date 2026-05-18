#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/../test-helpers.sh"

PLUGIN_DIR="$(cd "$HERE/../.." && pwd)"
BIN="$PLUGIN_DIR/bin/safer-vp"
LOG="$PLUGIN_DIR/bin/safer-telemetry-log"

test_runs_without_events() {
  local state
  state=$(mktemp -d)
  mkdir -p "$state/analytics"
  : > "$state/analytics/events.jsonl"
  local out
  out=$(SAFER_STATE_DIR="$state" "$BIN" 7d --repo unknown 2>&1)
  rm -rf "$state"
  assert_contains "$out" "VP Engineering" "header present"
  assert_contains "$out" "Calibration" "calibration section present"
}

test_shows_calibration_with_events() {
  local state
  state=$(mktemp -d)
  mkdir -p "$state/analytics"
  # Seed enough runs for calibration to produce output
  for _ in 1 2 3; do
    SAFER_STATE_DIR="$state" "$LOG" --event-type safer.skill_run --modality contract --session t-$RANDOM >/dev/null 2>&1
  done
  local out
  out=$(SAFER_STATE_DIR="$state" "$BIN" 7d --repo unknown 2>&1)
  rm -rf "$state"
  assert_contains "$out" "contract" "modality row shown"
}

run_test "safer-vp runs without events or gh" test_runs_without_events
run_test "safer-vp shows calibration rows when events exist" test_shows_calibration_with_events
report
