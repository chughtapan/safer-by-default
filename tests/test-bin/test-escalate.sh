#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/../test-helpers.sh"

PLUGIN_DIR="$(cd "$HERE/../.." && pwd)"
BIN="$PLUGIN_DIR/bin/safer-escalate"

test_requires_args() {
  local rc
  "$BIN" >/dev/null 2>&1; rc=$?
  assert_nonzero "$rc" "no args should fail"
  "$BIN" --from contract >/dev/null 2>&1; rc=$?
  assert_nonzero "$rc" "missing --to --cause should fail"
}

test_validates_status() {
  local rc
  "$BIN" --from contract --to architect --cause x --status INVALID >/dev/null 2>&1; rc=$?
  assert_nonzero "$rc" "invalid --status should fail"
}

test_validates_confidence() {
  local rc
  "$BIN" --from contract --to architect --cause x --confidence MEDIUM >/dev/null 2>&1; rc=$?
  assert_nonzero "$rc" "invalid --confidence should fail"
}

test_full_output() {
  local out
  out=$("$BIN" \
    --from implement-junior --to architect --cause "module boundary" \
    --issue 42 --parent 10 --status ESCALATED --confidence HIGH \
    --attempted 'tried local patch\nreverted' \
    --blocked 'need type change' \
    --recommendation 'open architect sub-task')
  assert_contains "$out" "# Escalation from implement-junior" "title"
  assert_contains "$out" "\`ESCALATED\`" "status"
  assert_contains "$out" "implement-junior → architect" "routing"
  assert_contains "$out" "Cause:** module boundary" "cause"
  assert_contains "$out" "Issue: #42" "issue"
  assert_contains "$out" "Parent epic: #10" "parent"
  assert_contains "$out" "- tried local patch" "attempted bullet"
  assert_contains "$out" "- reverted" "attempted bullet 2"
  assert_contains "$out" "\`HIGH\`" "confidence"
}

run_test "safer-escalate requires --from/--to/--cause" test_requires_args
run_test "safer-escalate validates --status" test_validates_status
run_test "safer-escalate validates --confidence" test_validates_confidence
run_test "safer-escalate emits full markdown" test_full_output
report
