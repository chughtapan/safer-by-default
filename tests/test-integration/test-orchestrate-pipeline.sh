#!/usr/bin/env bash
# test-orchestrate-pipeline.sh — end-to-end integration test for the full
# orchestrate pipeline against a real GitHub repo.
#
# What this exercises:
#   safer-publish --kind epic          creates a parent epic
#   safer-publish --kind issue         creates labeled sub-issues with --parent
#   safer-transition-label             walks the sub-issue state machine
#   safer-telemetry-log                emits skill_run / skill_end /
#                                      stop_rule_fired / escalation_triggered /
#                                      modality_handoff events
#   safer-vp 7d                        aggregates events into the VP dashboard
#   safer-calibration 7d               per-modality health tags
#
# Requires: gh authenticated. Test repo override via SAFER_TEST_REPO env
# (default: chughtapan/safer-by-default). Creates temporary issues and closes
# them on exit (including partial failures).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/../test-helpers.sh"

PLUGIN_DIR="$(cd "$HERE/../.." && pwd)"
BIN="$PLUGIN_DIR/bin"
REPO="${SAFER_TEST_REPO:-chughtapan/safer-by-default}"

STATE=$(mktemp -d)
TMP_BODY=$(mktemp)
CREATED_ISSUES=()

PASSED=0
FAILED=0

cleanup() {
  local rc=$?
  echo ""
  echo "── cleanup ──"
  for n in "${CREATED_ISSUES[@]}"; do
    gh issue close "$n" --repo "$REPO" --comment "integration test cleanup (auto)" >/dev/null 2>&1 && \
      echo "  closed #$n" || echo "  (could not close #$n; manual cleanup may be needed)"
  done
  rm -f "$TMP_BODY"
  rm -rf "$STATE"
  exit "$rc"
}
trap cleanup EXIT

export SAFER_STATE_DIR="$STATE"

# Telemetry for the test run itself — per the assignment, emit a skill_run
# event with modality=implement-junior so the test shows up in calibration.
TEST_SESSION="orch-int-$$-$(date +%s)"
"$BIN/safer-telemetry-log" --event-type safer.skill_run \
  --modality implement-junior --session "$TEST_SESSION" >/dev/null 2>&1 || true

# --- 0. Prereqs ---
echo "── orchestrate-pipeline: prereqs ──"
if ! gh auth status >/dev/null 2>&1; then
  echo "  SKIP: gh not authenticated"
  echo "  passed: 0"
  echo "  failed: 0"
  exit 0
fi
if ! gh repo view "$REPO" >/dev/null 2>&1; then
  echo "  SKIP: $REPO not accessible"
  echo "  passed: 0"
  echo "  failed: 0"
  exit 0
fi
echo "  ok  gh authenticated; $REPO accessible"

# --- 1. Ensure required labels exist ---
echo "── orchestrate-pipeline: ensure labels ──"
LABELS_TO_ENSURE=(
  "safer:architect" "safer:diagnose" "safer:implement-junior"
  "planning" "review" "plan-approved" "done" "triaged"
)
for L in "${LABELS_TO_ENSURE[@]}"; do
  gh label create "$L" --repo "$REPO" --color "ededed" --force >/dev/null 2>&1 || true
done
echo "  ok  labels ensured"

# --- 2. Create parent epic ---
echo "── orchestrate-pipeline: create parent epic ──"
TS_SUFFIX=$(date +%s)
cat > "$TMP_BODY" <<EOF
## Intent
(integration test for orchestrate pipeline; auto-closed on exit)

## Decomposition
| # | Modality | Depends on | Acceptance | Sub-issue |
|---|---|---|---|---|
| 1 | architect   | — | design doc; walks planning→review→plan-approved→done | TBD |
| 2 | diagnose    | — | repro + codex verdict; walks planning→review→done       | TBD |

[integration-test-marker: $TS_SUFFIX]
EOF

EPIC_OUT=$("$BIN/safer-publish" \
  --kind epic \
  --title "[test] orchestrate pipeline $TS_SUFFIX" \
  --body-file "$TMP_BODY" \
  --labels triaged \
  --repo "$REPO")
EPIC_NUM=$(echo "$EPIC_OUT" | grep -oE '[0-9]+$')
if [ -z "$EPIC_NUM" ]; then
  echo "  FAIL: could not parse epic number from: $EPIC_OUT"
  echo "  passed: $PASSED"
  echo "  failed: $((FAILED + 1))"
  exit 1
fi
CREATED_ISSUES+=("$EPIC_NUM")
echo "  ok  created epic #$EPIC_NUM"
PASSED=$((PASSED + 1))

# --- 3. Create two sub-issues ---
echo "── orchestrate-pipeline: create sub-issue 1 (architect) ──"
SUB1_OUT=$("$BIN/safer-publish" \
  --kind issue \
  --title "[safer:architect] integration sub-1 $TS_SUFFIX" \
  --body "Integration test sub-1. Parent: #$EPIC_NUM" \
  --parent "$EPIC_NUM" \
  --labels "safer:architect,planning" \
  --repo "$REPO")
SUB1=$(echo "$SUB1_OUT" | grep -oE '[0-9]+$')
if [ -z "$SUB1" ]; then
  echo "  FAIL: sub-1 parse: $SUB1_OUT"
  echo "  passed: $PASSED"
  echo "  failed: $((FAILED + 1))"
  exit 1
fi
CREATED_ISSUES+=("$SUB1")
echo "  ok  created sub-1 #$SUB1 (parent #$EPIC_NUM)"
PASSED=$((PASSED + 1))

echo "── orchestrate-pipeline: create sub-issue 2 (diagnose) ──"
SUB2_OUT=$("$BIN/safer-publish" \
  --kind issue \
  --title "[safer:diagnose] integration sub-2 $TS_SUFFIX" \
  --body "Integration test sub-2. Parent: #$EPIC_NUM" \
  --parent "$EPIC_NUM" \
  --labels "safer:diagnose,planning" \
  --repo "$REPO")
SUB2=$(echo "$SUB2_OUT" | grep -oE '[0-9]+$')
if [ -z "$SUB2" ]; then
  echo "  FAIL: sub-2 parse: $SUB2_OUT"
  echo "  passed: $PASSED"
  echo "  failed: $((FAILED + 1))"
  exit 1
fi
CREATED_ISSUES+=("$SUB2")
echo "  ok  created sub-2 #$SUB2 (parent #$EPIC_NUM)"
PASSED=$((PASSED + 1))

# --- 4. Transition sub-1: planning → review → plan-approved → done ---
echo "── orchestrate-pipeline: sub-1 label transitions ──"
for pair in "planning:review" "review:plan-approved" "plan-approved:done"; do
  FROM="${pair%:*}"
  TO="${pair#*:}"
  TRANS=$("$BIN/safer-transition-label" --issue "$SUB1" --from "$FROM" --to "$TO" --repo "$REPO" 2>&1)
  if echo "$TRANS" | grep -q "TRANSITIONED"; then
    echo "  ok  sub-1 $FROM → $TO"
    PASSED=$((PASSED + 1))
  else
    echo "  FAIL: sub-1 $FROM → $TO: $TRANS"
    FAILED=$((FAILED + 1))
  fi
done

# --- 5. Transition sub-2: planning → review → done (skip plan-approved) ---
echo "── orchestrate-pipeline: sub-2 label transitions ──"
for pair in "planning:review" "review:done"; do
  FROM="${pair%:*}"
  TO="${pair#*:}"
  TRANS=$("$BIN/safer-transition-label" --issue "$SUB2" --from "$FROM" --to "$TO" --repo "$REPO" 2>&1)
  if echo "$TRANS" | grep -q "TRANSITIONED"; then
    echo "  ok  sub-2 $FROM → $TO"
    PASSED=$((PASSED + 1))
  else
    echo "  FAIL: sub-2 $FROM → $TO: $TRANS"
    FAILED=$((FAILED + 1))
  fi
done

# --- 5b. Step 5 → Step 6 auto-dispatch handoff (enumerate + marker filter) ---
# sbd#66/H1 acceptance: the auto-gate step (5) hands off to the work-queue scan
# (6); cover that seam live against gh. Creates a pending implement-junior
# sub-issue, runs Step 6a's enumerate query, confirms the row appears, posts
# the Step 6d idempotency marker as a comment, re-runs the filter and confirms
# the row is now dropped.
echo "── orchestrate-pipeline: step 5 → step 6 auto-dispatch enumerate + filter ──"
SUB3_OUT=$("$BIN/safer-publish" \
  --kind issue \
  --title "[safer:implement-junior] integration sub-3 $TS_SUFFIX" \
  --body "Integration test sub-3. Parent: #$EPIC_NUM
Acceptance: enumerate finds this issue; marker filter drops it." \
  --parent "$EPIC_NUM" \
  --labels "safer:implement-junior,planning" \
  --repo "$REPO")
SUB3=$(echo "$SUB3_OUT" | grep -oE '[0-9]+$')
if [ -z "$SUB3" ]; then
  echo "  FAIL: sub-3 parse: $SUB3_OUT"
  FAILED=$((FAILED + 1))
else
  CREATED_ISSUES+=("$SUB3")
  echo "  ok  created sub-3 #$SUB3 (safer:implement-junior, planning)"
  PASSED=$((PASSED + 1))

  # Step 6a enumerate: exactly the jq the skill snippet pins.
  MODALITY_REGEX='^safer:(implement-(junior|senior|staff)|verify|spike|research|spec)$'
  ENUM_JSON=$(gh issue list --repo "$REPO" --state open --limit 200 \
    --json number,title,labels,url,body \
    --jq ".[] | select(.labels | map(.name) | any(test(\"$MODALITY_REGEX\"))) | .number" \
    2>/dev/null | grep -x "$SUB3" || true)
  if [ "$ENUM_JSON" = "$SUB3" ]; then
    echo "  ok  step 6a enumerate picks up pending sub-3"
    PASSED=$((PASSED + 1))
  else
    echo "  FAIL: step 6a enumerate did not return #$SUB3"
    FAILED=$((FAILED + 1))
  fi

  # Step 6d: post the idempotency marker as a comment (simulating a dispatch
  # reservation). Step 6a filter should then drop the candidate.
  MARKER_BODY="<!-- orchestrate:dispatched teammate=impl-junior-$SUB3 at=$(date -u +%Y-%m-%dT%H:%M:%SZ) -->"
  if gh issue comment "$SUB3" --repo "$REPO" --body "$MARKER_BODY" >/dev/null 2>&1; then
    echo "  ok  step 6d marker posted on sub-3"
    PASSED=$((PASSED + 1))
  else
    echo "  FAIL: could not post step 6d marker"
    FAILED=$((FAILED + 1))
  fi

  # Step 6a marker filter: per-candidate comment scan. Pins the fix for I1 —
  # reading --json body missed comment-based markers; per-candidate
  # --json comments catches them.
  FRESH_MARKER=$(gh issue view "$SUB3" --repo "$REPO" --json comments \
    --jq '.comments[].body
      | capture("<!-- orchestrate:dispatched teammate=[A-Za-z0-9_-]+ at=(?<ts>[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z) -->")
      | .ts' 2>/dev/null | sort | tail -1)
  if [ -n "$FRESH_MARKER" ]; then
    echo "  ok  step 6a filter finds marker on sub-3 (would skip re-dispatch)"
    PASSED=$((PASSED + 1))
  else
    echo "  FAIL: step 6a filter could not read marker via --json comments"
    FAILED=$((FAILED + 1))
  fi
fi

# --- 6. Telemetry ---
echo "── orchestrate-pipeline: emit telemetry ──"
SUB_SESSION="orch-sub-$TS_SUFFIX"
"$BIN/safer-telemetry-log" --event-type safer.skill_run \
  --modality architect --session "$SUB_SESSION" --issue "$SUB1" >/dev/null
"$BIN/safer-telemetry-log" --event-type safer.skill_run \
  --modality diagnose --session "$SUB_SESSION" --issue "$SUB2" >/dev/null
"$BIN/safer-telemetry-log" --event-type safer.skill_end \
  --modality architect --session "$SUB_SESSION" --outcome success --duration-s 12 >/dev/null
"$BIN/safer-telemetry-log" --event-type safer.skill_end \
  --modality diagnose --session "$SUB_SESSION" --outcome success --duration-s 9 >/dev/null
"$BIN/safer-telemetry-log" --event-type safer.stop_rule_fired \
  --modality diagnose --session "$SUB_SESSION" \
  --cause "simulated re-triage" --issue "$SUB2" >/dev/null
"$BIN/safer-telemetry-log" --event-type safer.escalation_triggered \
  --modality diagnose --session "$SUB_SESSION" \
  --from-modality diagnose --to-modality architect --cause "scope miscalibration" >/dev/null
"$BIN/safer-telemetry-log" --event-type safer.modality_handoff \
  --modality diagnose --session "$SUB_SESSION" \
  --from-modality diagnose --to-modality architect >/dev/null

EVENTS_FILE="$STATE/analytics/events.jsonl"
if [ -s "$EVENTS_FILE" ]; then
  EVENT_COUNT=$(wc -l < "$EVENTS_FILE" | tr -d ' ')
  echo "  ok  $EVENT_COUNT events written to $EVENTS_FILE"
  PASSED=$((PASSED + 1))
else
  echo "  FAIL: no events file at $EVENTS_FILE"
  FAILED=$((FAILED + 1))
fi

# --- 7. Close sub-issues (they're in `done` state, now close the GH issue) ---
echo "── orchestrate-pipeline: close sub-issues ──"
for N in "$SUB1" "$SUB2"; do
  if gh issue close "$N" --repo "$REPO" >/dev/null 2>&1; then
    echo "  ok  closed #$N"
  else
    echo "  WARN: could not close #$N"
  fi
done

echo "── orchestrate-pipeline: verify sub-issues closed ──"
CLOSED_COUNT=0
for N in "$SUB1" "$SUB2"; do
  STATE_VAL=$(gh issue view "$N" --repo "$REPO" --json state -q .state 2>/dev/null || echo "")
  if [ "$STATE_VAL" = "CLOSED" ]; then
    CLOSED_COUNT=$((CLOSED_COUNT + 1))
  else
    echo "  FAIL: #$N state is '$STATE_VAL' (expected CLOSED)"
    FAILED=$((FAILED + 1))
  fi
done
if [ "$CLOSED_COUNT" -eq 2 ]; then
  echo "  ok  0 open sub-issues (both closed)"
  PASSED=$((PASSED + 1))
fi

# --- 8. safer-vp 7d dashboard ---
echo "── orchestrate-pipeline: safer-vp 7d ──"
VP=$("$BIN/safer-vp" 7d --repo "$REPO" 2>&1)
if echo "$VP" | grep -q "VP Engineering"; then
  echo "  ok  VP dashboard header present"
  PASSED=$((PASSED + 1))
else
  echo "  FAIL: VP dashboard header missing"
  echo "$VP" | sed 's/^/    /'
  FAILED=$((FAILED + 1))
fi
if echo "$VP" | grep -qE "^architect " && echo "$VP" | grep -qE "^diagnose "; then
  echo "  ok  calibration rows show architect + diagnose"
  PASSED=$((PASSED + 1))
else
  echo "  FAIL: calibration rows missing expected modalities:"
  echo "$VP" | sed 's/^/    /'
  FAILED=$((FAILED + 1))
fi

# --- 9. safer-calibration 7d ---
echo "── orchestrate-pipeline: safer-calibration 7d ──"
CAL=$("$BIN/safer-calibration" 7d 2>&1)
# architect row has 0 stops, 0 escalations, 1 run → HEALTHY
if echo "$CAL" | grep -qE "^architect .*HEALTHY$"; then
  echo "  ok  architect tagged HEALTHY (no stops, no escalations)"
  PASSED=$((PASSED + 1))
else
  echo "  FAIL: architect row not HEALTHY:"
  echo "$CAL" | sed 's/^/    /'
  FAILED=$((FAILED + 1))
fi
# implement-junior (the test run itself) should also be HEALTHY
if echo "$CAL" | grep -qE "^implement-junior .*HEALTHY$"; then
  echo "  ok  implement-junior (test self) tagged HEALTHY"
  PASSED=$((PASSED + 1))
else
  echo "  FAIL: implement-junior row not HEALTHY:"
  echo "$CAL" | sed 's/^/    /'
  FAILED=$((FAILED + 1))
fi

# Emit skill_end for the test run itself on the happy path.
"$BIN/safer-telemetry-log" --event-type safer.skill_end \
  --modality implement-junior --session "$TEST_SESSION" \
  --outcome success --duration-s "$(($(date +%s) - TS_SUFFIX))" >/dev/null 2>&1 || true

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  passed: $PASSED"
echo "  failed: $FAILED"
if [ "$FAILED" -eq 0 ]; then
  echo "  INTEGRATION: PASS"
  exit 0
else
  echo "  INTEGRATION: FAIL"
  exit 1
fi
