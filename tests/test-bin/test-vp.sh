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
    SAFER_STATE_DIR="$state" "$LOG" --event-type safer.skill_run --modality spec --session t-$RANDOM >/dev/null 2>&1
  done
  local out
  out=$(SAFER_STATE_DIR="$state" "$BIN" 7d --repo unknown 2>&1)
  rm -rf "$state"
  assert_contains "$out" "spec" "modality row shown"
}

test_no_bare_zero_in_in_flight() {
  local state fake_gh out
  state=$(mktemp -d)
  fake_gh=$(mktemp -d)
  mkdir -p "$state/analytics"
  : > "$state/analytics/events.jsonl"
  # Stub gh so the In-flight loop runs with REPO != "unknown" but counts are 0.
  cat > "$fake_gh/gh" <<'EOF'
#!/usr/bin/env bash
for arg in "$@"; do
  if [ "$arg" = "nameWithOwner" ]; then
    echo "fake/repo"; exit 0
  fi
done
echo "[]"
exit 0
EOF
  chmod +x "$fake_gh/gh"
  out=$(PATH="$fake_gh:$PATH" SAFER_STATE_DIR="$state" "$BIN" 7d 2>&1)
  rm -rf "$state" "$fake_gh"
  assert_contains "$out" "In flight" "in-flight section runs"
  # Fail if any line is just "0" with nothing else.
  if printf '%s\n' "$out" | grep -qE '^0$'; then
    echo "    FAIL (bare zero line present)"
    printf '%s\n' "$out" | sed 's/^/      /'
    return 1
  fi
  return 0
}

run_test "safer-vp runs without events or gh" test_runs_without_events
run_test "safer-vp shows calibration rows when events exist" test_shows_calibration_with_events
run_test "safer-vp emits no bare 0 line for zero counts" test_no_bare_zero_in_in_flight
report
