# Phase 5d rewrite proposal (state-comment + 3-source liveness)

Spike-local proposal for the `orchestrate/SKILL.md` Phase 5d auto-monitor.
Replaces the current single-signal `tmux list-panes -a` liveness check with a
three-source composition anchored on the Round 3 HTML-comment schema + ao
session file + tmux pane as tiebreaker. This file is the spike's design
evidence; merging the proposal into `skills/orchestrate/SKILL.md` is the
`/safer:spec` step, not the spike.

## What is being replaced

Phase 5d step 4 today harvests `$ALIVE` via `tmux list-panes -a -F '#{pane_id}'`
and uses pane-alive as the only process-death signal. This is a single-layer
detector on the most fragile signal (Round 6 of sbd#61). Path (a) (dead-pane
cleanup) fires whenever a pane is missing regardless of whether the teammate's
work survived durably.

## What replaces it

### Step 4' — ingest three liveness sources per teammate.

```bash
# Source A: GitHub state-comment (durable, cross-host, slow).
HB_JSON=$(safer-heartbeat list --epic "$PARENT" --repo "$REPO")

# Source B: ao session metadata (disk-durable, same-host, sub-minute).
AO_JSON=$(ao session ls --all --json 2>/dev/null || echo "[]")

# Source C: tmux pane id (noisy, live process only).
ALIVE=$(tmux list-panes -a -F '#{pane_id}' 2>/dev/null | sort -u)
```

Compose a three-source verdict per teammate (joining on `teammate` name + the
pane id in the team config):

| Source A      | Source B            | Source C  | Verdict        |
|---------------|---------------------|-----------|----------------|
| fresh (<5m)   | active / ready      | pane ok   | **alive**      |
| stale (>5m)   | restorable          | any       | **restorable** |
| stale         | merged / killed     | any       | **clean-done** |
| stale         | absent              | absent    | **fresh**      |
| absent        | absent              | any       | **fresh**      |
| fresh         | any                 | absent    | **alive** (pane briefly down; trust the heartbeat) |
| stale         | active              | pane ok   | **alive** (ao-writer lag; trust tmux + ao) |

Freshness threshold: state-comment `last_heartbeat` within 5 minutes. Same
threshold already in zapbot v1 (`heartbeat.ts:10-12`).

### Step 4'' — actions per verdict

- `alive`: skip (same as today).
- `restorable`: call `ao session restore <name>`; do NOT invoke
  `cleanStaleWorktree` (see zapbot fix at `src/agents/spawner.ts:151`). Append
  a state-comment heartbeat with `status=working`.
- `clean-done`: auto-delete from team roster (today's Path (b) path).
- `fresh`: reopen via Step 6 work-queue scan (today's path).

### Step 4''' — ownership atomic via state-comment

Before Step 6 dispatches a fresh teammate, re-read the state-comment:

```bash
OWNER=$(safer-heartbeat read --sub-issue "$N" | jq -r '.teammate // empty')
```

If `OWNER` is non-empty AND `last_heartbeat` is within the freshness window,
skip the dispatch even if the idempotency marker has expired. This is the
cooperative advisory-lock (Round 9). Hard-lock via `safer:owner-<name>` label
is deferred to Tier 3 (multi-orchestrator topology).

### Step 4'''' — local reconcile at team-lead cold-start

On team-lead startup, one-shot:

```bash
safer-reconcile scan --team "$TEAM" --repo "$REPO" --format json \
  > /tmp/scan-$$.json
safer-reconcile apply --plan /tmp/scan-$$.json --yes
```

Apply acts only on safe verdicts (`alive`, `restorable`, `fresh`,
`clean-done`). Unsafe verdicts (`orphan-with-work`, `zombie-with-work`,
`unowned-session`, `undocumented-work`, `partially-durable`) surface as a
summary comment on the parent epic; user decides via
`safer-reconcile promote`.

## What stays the same

- Step 1 (team roster read from `config.json`).
- Step 2 (review-ready sub-issue sweep).
- Step 3 (open PR status sweep).
- Step 5 (auto-gate + epic progress rewrite).
- Step 6 (work-queue scan + dispatch).

Only step 4 (tmux-only liveness) is replaced. The idempotency marker, the
pane-ceiling safety net, the 2-min cadence, and the fail-closed defaults all
carry over unchanged.

## Why this answers the spike question

The three-source composition satisfies the four recovery scenarios of
Round 3:

1. **Team-lead dies; teammates alive.** On restart, `safer-heartbeat list`
   rebuilds the roster from GitHub in one API call. Cross-check with
   `ao session ls`. Fresh dispatches fire only for pruned entries. — Test 2.
2. **Team-lead alive; teammate dies.** State-comment goes stale in 5 min;
   ao flips to `stuck`/`terminated`; tmux pane absent. Verdict: restorable
   (via ao) or fresh (no ao session). Dispatch resumes from `last_commit`. —
   Test 1.
3. **Both die.** Team-lead restart triggers the roster rebuild in scenario 1;
   per-teammate verdicts run as in scenario 2. — Test 3.
4. **VM dies.** Out of scope per spike; Tier 3 concern.

## Reconciliation slots in without new substrate

`safer-reconcile scan` reads the same ao session list Step 4' already loads,
plus `git worktree list` and local-branch scans. No new cron, no new endpoint,
no new daemon. The scan is read-only; the apply is bounded to the four safe
verdicts; the promote is one entry at a time with user attention. The
Round 7 rule — "GitHub wins on intent; local wins on bytes; user wins on
ambiguity" — is preserved mechanically.
