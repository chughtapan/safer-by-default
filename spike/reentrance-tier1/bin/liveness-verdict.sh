#!/usr/bin/env bash
# liveness-verdict.sh — spike helper that realizes the Phase 5d 3-source
# liveness composition for one (sub-issue, teammate) pair. Reads the
# state-comment via safer-heartbeat read, the ao session list via the env
# overrides in safer-reconcile, and the tmux pane list similarly. Emits a
# single-line verdict + chosen action.
set -uo pipefail

TEAM=""; SUB=""; REPO=""; FRESH=300
while [ $# -gt 0 ]; do
  case "$1" in
    --teammate)      TEAM="$2"; shift 2 ;;
    --sub-issue)     SUB="$2"; shift 2 ;;
    --repo)          REPO="$2"; shift 2 ;;
    --freshness-sec) FRESH="$2"; shift 2 ;;
    *) shift ;;
  esac
done
[ -n "$TEAM" ] && [ -n "$SUB" ] || { echo "need --teammate --sub-issue" >&2; exit 1; }

HB=$(safer-heartbeat read --repo "$REPO" --sub-issue "$SUB" 2>/dev/null)
HB_TEAM=$(jq -r '.teammate // empty' <<<"$HB")
HB_TS=$(jq -r '.last_heartbeat // empty' <<<"$HB")
HB_COMMIT=$(jq -r '.last_commit // empty' <<<"$HB")

now=$(date -u +%s)
hb_epoch=0
if [ -n "$HB_TS" ]; then
  hb_epoch=$(date -u -d "$HB_TS" +%s 2>/dev/null || echo 0)
fi
age=$(( now - hb_epoch ))

# ao signal
AO_JSON=$(cat "${SBD_AO_SESSION_LS_OVERRIDE:-/dev/null}" 2>/dev/null || echo "[]")
AO_STATUS=$(jq -r --arg t "$TEAM" '.[] | select(.role == $t) | .status' <<<"$AO_JSON" | head -1)
AO_ID=$(jq -r --arg t "$TEAM" '.[] | select(.role == $t) | .id' <<<"$AO_JSON" | head -1)

# tmux signal (override or real)
PANES=$(cat "${SBD_TMUX_PANES_OVERRIDE:-/dev/null}" 2>/dev/null \
        || tmux list-panes -a -F '#{pane_id}' 2>/dev/null || true)

# Compose
verdict="unknown"
action="skip (default)"
if [ "$HB_TEAM" = "$TEAM" ] && [ "$age" -le "$FRESH" ]; then
  verdict="alive"
  action="skip"
elif [ -n "$AO_ID" ] && [ "$AO_STATUS" = "merged" ]; then
  verdict="clean-done"
  action="prune from roster"
elif [ -n "$AO_ID" ] && [ "$AO_STATUS" != "active" ] && [ "$AO_STATUS" != "ready" ]; then
  verdict="restorable"
  action="ao session restore $AO_ID; skip cleanStaleWorktree"
elif [ -z "$AO_ID" ]; then
  verdict="fresh"
  action="dispatch fresh teammate; resume-prompt at last_commit=$HB_COMMIT"
fi

cat <<EOF
teammate:       $TEAM
sub_issue:      $SUB
hb_teammate:    ${HB_TEAM:-<none>}
hb_last_commit: ${HB_COMMIT:-<none>}
hb_age_sec:     $age (fresh-threshold=$FRESH)
ao_id:          ${AO_ID:-<none>}
ao_status:      ${AO_STATUS:-<none>}
tmux_panes:     $(printf '%s' "$PANES" | wc -w)
verdict:        $verdict
action:         $action
EOF
