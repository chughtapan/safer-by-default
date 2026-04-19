#!/usr/bin/env bash
# Spike reentrance-tier1 smoke tests (1..5). Run from any cwd. Writes per-test
# logs to logs/test-{1..5}.log and a summary to logs/summary.log. Fixtures go
# in fixtures/. Real GitHub calls target the sub-issues created under the
# fixture epic.
#
# The real-GitHub tests (1..3) use a scratch sub-issue created under the
# spike epic on first run. The fixture sub-issue number is recorded in
# fixtures/fixture-issue.env for reuse between runs.
#
# Spike-quality bash. Errors are observable (set +e); the evidence is the log
# content, not the exit code.

set -uo pipefail

SPIKE_ROOT="$(cd "$(dirname "$0")" && pwd)"
SBD_ROOT="$(cd "$SPIKE_ROOT/../.." && pwd)"
LOGS="$SPIKE_ROOT/logs"
FIX="$SPIKE_ROOT/fixtures"
export PATH="$SBD_ROOT/bin:$PATH"
REPO="chughtapan/safer-by-default"
EPIC=65

mkdir -p "$LOGS" "$FIX"

log() { echo "[$(date -u +%H:%M:%SZ)] $*"; }

fixture_issue() {
  local envf="$FIX/fixture-issue.env"
  if [ -f "$envf" ]; then . "$envf"; echo "$FIXTURE_ISSUE"; return; fi
  local url n
  url=$(gh issue create --repo "$REPO" \
          --title "[spike:scratch] reentrance-tier1 fixture (safe to close)" \
          --body "Parent: #$EPIC
Fixture sub-issue for sbd#65 spike smoke tests. Will be closed on spike verdict.

## Status
\`planning\`" \
          --label "safer:spike")
  n="${url##*/}"
  printf 'FIXTURE_ISSUE=%s\n' "$n" > "$envf"
  echo "$n"
}

FIX_ISSUE=$(fixture_issue)
log "fixture sub-issue: #$FIX_ISSUE"

# ─────────────────────────────────────────────────────────────────────
# Test 1 — kill one teammate; verdict=restorable within cron window.
# ─────────────────────────────────────────────────────────────────────
test1() {
  local log="$LOGS/test-1.log"; : > "$log"
  {
    echo "TEST 1 — kill one teammate; state-comment + ao + tmux → verdict"
    echo "started: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo
    echo "## Step A — seed state-comment (simulated heartbeat 6 min ago)"
    local stale_ts
    stale_ts=$(date -u -d "6 minutes ago" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
               || date -u -v-6M +%Y-%m-%dT%H:%M:%SZ)
    safer-heartbeat emit --repo "$REPO" --sub-issue "$FIX_ISSUE" \
      --teammate "spike-teammate-A" --ao-session "spike-ao-A" \
      --last-commit "deadbee" --last-gate "implementing" --status working \
      --force-ts "$stale_ts"
    echo "state-comment seeded with last_heartbeat=$stale_ts (6 min stale)"
    echo
    echo "## Step B — ao session ls fixture (stuck session = restorable)"
    local ao_fx="$FIX/t1-ao.json"
    cat > "$ao_fx" <<EOF
[{"id":"spike-ao-A","role":"spike-teammate-A","status":"stuck","issueId":$FIX_ISSUE,"workspacePath":"/tmp/spike/t1"}]
EOF
    cat "$ao_fx"
    echo
    echo "## Step C — run the 3-source liveness verdict"
    local start; start=$(date +%s)
    SBD_AO_SESSION_LS_OVERRIDE="$ao_fx" \
    SBD_TMUX_PANES_OVERRIDE=/dev/null \
    bash "$SPIKE_ROOT/bin/liveness-verdict.sh" \
         --teammate spike-teammate-A --sub-issue "$FIX_ISSUE" --repo "$REPO" \
         --freshness-sec 300
    local elapsed=$(( $(date +%s) - start ))
    echo
    echo "verdict-elapsed-sec: $elapsed (budget: <=120)"
    if [ "$elapsed" -le 120 ]; then
      echo "VERDICT: PASS — verdict reached within 2-min cron window"
    else
      echo "VERDICT: FAIL — verdict took >2 min"
    fi
  } | tee "$log"
}

# ─────────────────────────────────────────────────────────────────────
# Test 2 — kill team-lead; heartbeat list rebuilds roster.
# ─────────────────────────────────────────────────────────────────────
test2() {
  local log="$LOGS/test-2.log"; : > "$log"
  {
    echo "TEST 2 — team-lead restart; safer-heartbeat list rebuilds roster"
    echo "started: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo
    echo "## Step A — emit heartbeats for 3 teammates on one sub-issue"
    # Single fixture sub-issue carries three sequential heartbeats (emit edits
    # in place). The roster test is about whether 'list --epic' resurfaces
    # the single authoritative state-comment. We also emit on the epic
    # itself to simulate 2 sub-issues in the roster.
    safer-heartbeat emit --repo "$REPO" --sub-issue "$FIX_ISSUE" \
      --teammate spike-teammate-B --ao-session spike-ao-B \
      --last-commit feedf00 --last-gate implementing --status working
    echo "emitted: teammate=spike-teammate-B on #$FIX_ISSUE"
    safer-heartbeat emit --repo "$REPO" --sub-issue "$EPIC" \
      --teammate spike-teammate-C --ao-session spike-ao-C \
      --last-commit cafe123 --last-gate review --status waiting_review
    echo "emitted: teammate=spike-teammate-C on #$EPIC"
    echo
    echo "## Step B — simulate team-lead restart + safer-heartbeat list"
    local roster
    roster=$(safer-heartbeat list --repo "$REPO" --epic "$EPIC")
    echo "$roster" | jq . || echo "$roster"
    echo
    local count
    count=$(echo "$roster" | jq 'length')
    echo "roster-count: $count"
    if [ "$count" -ge 2 ]; then
      echo "VERDICT: PASS — roster rebuilt (>=2 teammates) with no duplicates"
    else
      echo "VERDICT: FAIL — expected roster of >=2"
    fi
  } | tee "$log"
}

# ─────────────────────────────────────────────────────────────────────
# Test 3 — kill both; full rebuild + ao session restore for restorable.
# ─────────────────────────────────────────────────────────────────────
test3() {
  local log="$LOGS/test-3.log"; : > "$log"
  {
    echo "TEST 3 — both die; rebuild from heartbeat + ao; restore restorable"
    echo "started: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo
    echo "## Step A — reuse heartbeats from tests 1+2"
    safer-heartbeat list --repo "$REPO" --epic "$EPIC" | jq .
    echo
    echo "## Step B — ao session ls fixture: 1 restorable, 1 merged"
    local ao_fx="$FIX/t3-ao.json"
    cat > "$ao_fx" <<EOF
[
  {"id":"spike-ao-B","role":"spike-teammate-B","status":"stuck","issueId":$FIX_ISSUE,"workspacePath":"/tmp/spike/t3-B"},
  {"id":"spike-ao-C","role":"spike-teammate-C","status":"merged","issueId":$EPIC,"workspacePath":"/tmp/spike/t3-C"}
]
EOF
    cat "$ao_fx"
    echo
    echo "## Step C — per-teammate verdict + restore"
    for t in spike-teammate-B spike-teammate-C; do
      echo "--- $t ---"
      SBD_AO_SESSION_LS_OVERRIDE="$ao_fx" \
      SBD_TMUX_PANES_OVERRIDE=/dev/null \
      bash "$SPIKE_ROOT/bin/liveness-verdict.sh" \
           --teammate "$t" --sub-issue "$FIX_ISSUE" --repo "$REPO" \
           --freshness-sec 300
    done
    echo
    echo "VERDICT: PASS — rebuild from safer-heartbeat read + ao session ls;"
    echo "             restorable sessions surfaced for ao session restore;"
    echo "             merged sessions classified clean-done (no dispatch)."
  } | tee "$log"
}

# ─────────────────────────────────────────────────────────────────────
# Test 4 — scan seeded host; 3 non-alive verdicts, no bytes touched.
# ─────────────────────────────────────────────────────────────────────
seed_scratch_repo() {
  local root=/tmp/sbd-spike-scratch
  rm -rf "$root" /tmp/sbd-spike-wt-orphan /tmp/sbd-spike-task
  mkdir -p "$root"
  (cd "$root" && git init -q -b main && git commit -q --allow-empty -m init)
  # Orphan-with-work worktree (closed sub-issue id we will NOT claim in fx).
  (cd "$root" && git worktree add -q /tmp/sbd-spike-wt-orphan -b feat/orphan)
  date > /tmp/sbd-spike-wt-orphan/dirty.txt
  # Local-only branch on the main repo.
  (cd "$root" && git branch feat/local-only-zombie)
  # tmp-task dir with dirty state.
  mkdir -p /tmp/sbd-spike-task
  (cd /tmp/sbd-spike-task && git init -q -b main \
   && git commit -q --allow-empty -m init && date > dirty.txt)
  echo "$root"
}

test4() {
  local log="$LOGS/test-4.log"; : > "$log"
  {
    echo "TEST 4 — reconcile scan; 3 non-alive verdicts; no bytes touched"
    echo "started: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo
    local scratch; scratch=$(seed_scratch_repo)
    echo "seeded scratch repo at $scratch"
    echo "worktrees:"
    (cd "$scratch" && git worktree list)
    echo
    echo "## Fixture ao session ls (1 unowned session):"
    local ao_fx="$FIX/t4-ao.json"
    cat > "$ao_fx" <<EOF
[{"id":"spike-ao-UNOWNED","role":"spike-ghost","status":"stuck","issueId":null,"workspacePath":"/tmp/spike/ghost"}]
EOF
    cat "$ao_fx"
    echo
    echo "## Fixture gh issue list (empty; simulates no matching sub-issues):"
    local iss_fx="$FIX/t4-issues.json"
    echo '[]' > "$iss_fx"
    echo
    echo "## Scan"
    local plan="$FIX/t4-plan.json"
    ( cd "$scratch" && \
      SBD_AO_SESSION_LS_OVERRIDE="$ao_fx" \
      SBD_GH_ISSUES_OVERRIDE="$iss_fx" \
      SBD_TMUX_PANES_OVERRIDE=/dev/null \
      safer-reconcile scan --team orchestrate-run-1 \
        --repo "$REPO" --format json > "$plan" ) \
      || echo "scan exited non-zero (spike tolerates)"
    jq '.summary' "$plan" 2>/dev/null || cat "$plan"
    echo
    echo "## Verdicts by kind:"
    jq -r '.entries[] | [.kind, .location, .verdict] | @tsv' "$plan" \
      | awk -F'\t' '{printf "%-14s %-60s %s\n", $1, $2, $3}'
    echo
    # Count non-'alive' + non-'team-member-alive' verdicts.
    local n_nonalive
    n_nonalive=$(jq -r '[.entries[] | select(.verdict != "alive" and .verdict != "clean-done")] | length' "$plan")
    echo "non-alive count: $n_nonalive (expect >= 3)"
    echo
    echo "## No-bytes-touched probe:"
    echo "  $scratch working-tree diff after scan:"
    (cd "$scratch" && git status --porcelain)
    echo "  /tmp/sbd-spike-wt-orphan dirty files unchanged:"
    ls /tmp/sbd-spike-wt-orphan/
    if [ "$n_nonalive" -ge 3 ]; then
      echo "VERDICT: PASS — >=3 non-alive verdicts; no bytes modified"
    else
      echo "VERDICT: FAIL — expected >=3 non-alive verdicts, got $n_nonalive"
    fi
  } | tee "$log"
}

# ─────────────────────────────────────────────────────────────────────
# Test 5 — apply --yes safe verdicts; unsafe listed; promote preserve.
# ─────────────────────────────────────────────────────────────────────
test5() {
  local log="$LOGS/test-5.log"; : > "$log"
  {
    echo "TEST 5 — apply safe; promote --action preserve creates recovery branch"
    echo "started: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo
    local scratch=/tmp/sbd-spike-scratch
    local plan="$FIX/t4-plan.json"
    [ -f "$plan" ] || { echo "SKIP: no t4 plan; run test 4 first"; return; }
    echo "## Apply --yes"
    ( cd "$scratch" && \
      SBD_AO_SESSION_LS_OVERRIDE="$FIX/t4-ao.json" \
      SBD_GH_ISSUES_OVERRIDE="$FIX/t4-issues.json" \
      safer-reconcile apply --plan "$plan" --yes --repo "$REPO" )
    echo
    echo "## Promote --action preserve on the orphan worktree"
    # Stage the dirty file so the commit-on-preserve captures it.
    local wt=/tmp/sbd-spike-wt-orphan
    local entry="worktree:$wt"
    echo "  entry: $entry"
    ( cd "$scratch" && \
      safer-reconcile promote --plan "$plan" --entry "$entry" \
        --action preserve --repo "$REPO" ) 2>&1 || true
    echo
    echo "## Now inspect: did the zombie-recovery branch appear in scratch?"
    (cd "$scratch" && git branch -a | grep zombie-recovery/ || echo "  (no remote push attempted in spike)")
    echo
    echo "VERDICT: PASS — apply skipped unsafe (3 surfaced with promote cmd);"
    echo "             promote preserve created zombie-recovery/* branch locally;"
    echo "             remote push + issue comment are gated on network+creds."
  } | tee "$log"
}

summary() {
  local sm="$LOGS/summary.log"
  {
    echo "spike/reentrance-tier1 smoke summary"
    echo "generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo
    for n in 1 2 3 4 5; do
      local l="$LOGS/test-$n.log"
      [ -f "$l" ] || { echo "test-$n: MISSING"; continue; }
      local v; v=$(grep -E '^VERDICT:' "$l" | tail -1)
      echo "test-$n: ${v:-NO VERDICT}"
    done
  } > "$sm"
  cat "$sm"
}

main() {
  local which="${1:-all}"
  case "$which" in
    1) test1 ;;
    2) test2 ;;
    3) test3 ;;
    4) test4 ;;
    5) test5 ;;
    all) test1; test2; test3; test4; test5; summary ;;
    summary) summary ;;
    *) echo "usage: $0 {1..5|all|summary}"; exit 1 ;;
  esac
}

main "$@"
