#!/usr/bin/env bash
# test-workflow.sh — end-to-end verification of the safer-by-default workflow
# against a real GitHub repo.
#
# What this exercises:
#   safer-publish --kind epic         creates the parent epic
#   safer-publish --kind issue        creates a labeled sub-issue
#   safer-transition-label             changes state labels atomically
#   safer-load-context --issue --parent  fetches structured context
#   safer-telemetry-log                appends events to a temp state dir
#   safer-calibration / safer-vp       aggregate from events
#   safer-diff-scope                   tier classification on a synthetic diff
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
TMP_DIFF=$(mktemp)
CREATED_ISSUES=()

cleanup() {
  local rc=$?
  echo ""
  echo "── cleanup ──"
  for n in "${CREATED_ISSUES[@]}"; do
    gh issue close "$n" --repo "$REPO" --comment "integration test cleanup (auto)" >/dev/null 2>&1 && \
      echo "  closed #$n" || echo "  (could not close #$n; manual cleanup may be needed)"
  done
  rm -f "$TMP_BODY" "$TMP_DIFF"
  rm -rf "$STATE"
  exit "$rc"
}
trap cleanup EXIT

export SAFER_STATE_DIR="$STATE"

# --- 0. Prereqs ---
echo "── integration: prereqs ──"
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
echo "── integration: ensure labels ──"
LABELS_TO_ENSURE=(
  "safer:contract" "safer:architect" "safer:implement-junior" "safer:implement-senior"
  "safer:implement-staff" "safer:diagnose" "safer:spike" "safer:research"
  "safer:review-senior" "safer:verify"
  "planning" "review" "plan-approved" "implementing" "verifying" "done" "triaged" "abandoned"
)
for L in "${LABELS_TO_ENSURE[@]}"; do
  gh label create "$L" --repo "$REPO" --color "ededed" --force >/dev/null 2>&1 || true
done
echo "  ok  labels ensured"

# --- 2. Create parent epic via safer-publish ---
echo "── integration: create parent epic ──"
TS_SUFFIX=$(date +%s)
cat > "$TMP_BODY" <<EOF
## Intent
(integration test; will be auto-closed)

## Decomposition
| # | Modality | Depends on | Acceptance | Sub-issue |
|---|---|---|---|---|
| 1 | spec | — | criteria listed | TBD |
| 2 | implement-junior | 1 | PR merged | TBD |

[integration-test-marker: $TS_SUFFIX]
EOF

EPIC_OUT=$("$BIN/safer-publish" \
  --kind epic \
  --title "[test] integration workflow $TS_SUFFIX" \
  --body-file "$TMP_BODY" \
  --labels triaged \
  --repo "$REPO")
EPIC_NUM=$(echo "$EPIC_OUT" | grep -oE '[0-9]+$')
if [ -z "$EPIC_NUM" ]; then
  echo "  FAIL: could not parse epic number from: $EPIC_OUT"
  echo "  passed: 0"
  echo "  failed: 1"
  exit 1
fi
CREATED_ISSUES+=("$EPIC_NUM")
echo "  ok  created epic #$EPIC_NUM"

# --- 3. Create a sub-issue ---
echo "── integration: create sub-issue ──"
SUB_OUT=$("$BIN/safer-publish" \
  --kind issue \
  --title "[safer:contract] integration test spec $TS_SUFFIX" \
  --body "Integration test sub-issue. Parent epic: #$EPIC_NUM" \
  --parent "$EPIC_NUM" \
  --labels "safer:contract,planning" \
  --repo "$REPO")
SUB_NUM=$(echo "$SUB_OUT" | grep -oE '[0-9]+$')
if [ -z "$SUB_NUM" ]; then
  echo "  FAIL: could not parse sub-issue number from: $SUB_OUT"
  echo "  passed: 0"
  echo "  failed: 1"
  exit 1
fi
CREATED_ISSUES+=("$SUB_NUM")
echo "  ok  created sub-issue #$SUB_NUM (parent #$EPIC_NUM)"

# --- 4. Transition labels ---
echo "── integration: transition labels ──"
TRANS_OUT=$("$BIN/safer-transition-label" --issue "$SUB_NUM" --from planning --to review --repo "$REPO" 2>&1)
PASSED=0
FAILED=0
if echo "$TRANS_OUT" | grep -q "TRANSITIONED"; then
  echo "  ok  transitioned: $TRANS_OUT"
  PASSED=$((PASSED + 1))
else
  echo "  FAIL: transition did not succeed: $TRANS_OUT"
  FAILED=$((FAILED + 1))
fi

# --- 5. Load context ---
echo "── integration: load context ──"
CTX=$("$BIN/safer-load-context" --issue "$SUB_NUM" --parent --repo "$REPO" 2>&1)
if echo "$CTX" | grep -q "\"issue\":" && echo "$CTX" | grep -q "\"number\":$SUB_NUM"; then
  echo "  ok  issue + parent context loaded for #$SUB_NUM"
  PASSED=$((PASSED + 1))
else
  echo "  FAIL: load-context output:"
  echo "$CTX" | head -5 | sed 's/^/    /'
  FAILED=$((FAILED + 1))
fi

# --- 6. Telemetry + dashboards ---
echo "── integration: telemetry + dashboards ──"
"$BIN/safer-telemetry-log" --event-type safer.skill_run --modality contract --session "int-$TS_SUFFIX" --issue "$SUB_NUM" >/dev/null
"$BIN/safer-telemetry-log" --event-type safer.skill_end --modality contract --session "int-$TS_SUFFIX" --outcome success --duration-s 15 >/dev/null
"$BIN/safer-telemetry-log" --event-type safer.skill_run --modality implement-junior --session "int-$TS_SUFFIX" >/dev/null
"$BIN/safer-telemetry-log" --event-type safer.stop_rule_fired --modality implement-junior --cause "second module touched" >/dev/null

CAL=$("$BIN/safer-calibration" 7d 2>&1)
if echo "$CAL" | grep -qE "^spec " && echo "$CAL" | grep -qE "^implement-junior "; then
  echo "  ok  calibration shows spec and implement-junior rows"
  PASSED=$((PASSED + 1))
else
  echo "  FAIL: calibration output missing expected modalities:"
  echo "$CAL" | sed 's/^/    /'
  FAILED=$((FAILED + 1))
fi

VP=$("$BIN/safer-vp" 7d --repo "$REPO" 2>&1)
if echo "$VP" | grep -q "VP Engineering" && echo "$VP" | grep -qE "^spec "; then
  echo "  ok  VP dashboard renders"
  PASSED=$((PASSED + 1))
else
  echo "  FAIL: VP dashboard output:"
  echo "$VP" | sed 's/^/    /'
  FAILED=$((FAILED + 1))
fi

# --- 7. Diff-scope tier classification ---
echo "── integration: diff-scope tier classification ──"
cat > "$TMP_DIFF" <<'EOF'
diff --git a/src/auth/token.ts b/src/auth/token.ts
@@ -10,6 +10,7 @@ export function verify(x) {
-  return decode(x);
+  if (!x) return null;
+  return decode(x);
 }
EOF
CLASS=$("$BIN/safer-diff-scope" --diff "$TMP_DIFF")
if echo "$CLASS" | grep -q '"tier":"junior"'; then
  echo "  ok  single-file internal change classified as junior"
  PASSED=$((PASSED + 1))
else
  echo "  FAIL: diff-scope output: $CLASS"
  FAILED=$((FAILED + 1))
fi

# --- 8. Transition to done + verify ---
echo "── integration: transition to done ──"
"$BIN/safer-transition-label" --issue "$SUB_NUM" --from review --to done --repo "$REPO" >/dev/null 2>&1 && \
  PASSED=$((PASSED + 1)) && echo "  ok  transitioned to done" || \
  (FAILED=$((FAILED + 1)) && echo "  FAIL: could not transition to done")

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
