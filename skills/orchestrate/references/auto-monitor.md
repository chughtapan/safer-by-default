# Step 5d — Auto-monitor loop (MANDATORY)

**This step is mandatory for every orchestrate run that dispatches more than one teammate.** Skipping it is a stop-rule violation: orchestrate sitting idle between user prompts defeats the entire point of async dispatch.

Teammates complete asynchronously. Polling every sub-issue by hand is how orchestrate drifts into idle sit-and-wait. The loop runs the sweep for you.

**Why.** Without a loop, the team lead either spins waiting for prompts or wakes up only when the user nudges. Both defeat the point of orchestration. The loop is how orchestrate earns the "scrum master who reads `gh issue list`" framing at runtime.

**Install.** Run `CronCreate` **before your first dispatch**, not after. Session-only job (`recurring: true`, `durable: false`). Mandatory cadence is every 2 minutes:

```
CronCreate({
  schedule: "*/2 * * * *",
  recurring: true,
  durable: false,
  prompt: "<loop body, see below>"
})
```

Record the returned job id on the parent epic (comment) so the next operator can cancel it.

**Loop body.** Each tick does exactly the checks below, in order. The loop writes no code and makes no decisions that are not already encoded in an artifact.

1. **Team roster.** Read `~/.claude/teams/<team-name>/config.json` with `jq` to list teammates and their `isActive` flag. Example: `jq -r '.members[] | "\(.name)\t\(.isActive)\t\(.paneId // "-")"' ~/.claude/teams/<team-name>/config.json`.

1a. **Teammate pane stall check.** For every teammate (excluding `team-lead`) whose `tmuxPaneId` is in `$ALIVE`, capture the pane and regex-match for the claude-swarm permission dialog string. The Agent backend uses a separate tmux socket. Discover it once per tick, do NOT assume `default`:

    ```bash
    SWARM_SOCKET=$(ls /tmp/tmux-$(id -u)/claude-swarm-* 2>/dev/null | head -1)
    [ -z "$SWARM_SOCKET" ] && echo "swarm_socket_missing: skipping pane stall check" && return 0
    # The socket FILE can exist with no server listening (Conductor / non-tmux backends).
    # Probe for a live server, not just file existence; fail loud, not silent.
    tmux -S "$SWARM_SOCKET" list-sessions >/dev/null 2>&1 \
      || { echo "swarm_socket_dead: skipping pane stall check (socket file present, no server listening)"; return 0; }
    # Teammate pane ids must be tmux-native (%0, %1, ...). On non-tmux backends the
    # roster records macOS UUIDs, which are not valid -t targets; skip rather than scan blind.
    SAMPLE_ID=$(jq -r '.members[] | select(.name != "team-lead") | .tmuxPaneId // empty' \
                ~/.claude/teams/<team-name>/config.json | head -1)
    case "$SAMPLE_ID" in
      '%'*) ;;  # tmux-native; proceed
      ?*) echo "pane_backend: non-tmux id format ($SAMPLE_ID); pane stall check disabled this tick"; return 0 ;;
    esac

    for paneId in $(jq -r '.members[] | select(.name != "team-lead") | .tmuxPaneId // empty' \
                    ~/.claude/teams/<team-name>/config.json); do
      capture=$(tmux -S "$SWARM_SOCKET" capture-pane -t "$paneId" -p 2>/dev/null) || continue
      if echo "$capture" | grep -q 'Waiting for team lead approval'; then
        # Extract the requested tool + command from the last ~40 lines of the capture.
        # Surface as a sweep-summary anomaly. The team-lead MUST respond this tick
        # via the Phase 5e protocol, not the next.
        teammate=$(jq -r --arg pid "$paneId" \
          '.members[] | select(.tmuxPaneId == $pid) | .name' \
          ~/.claude/teams/<team-name>/config.json)
        echo "permission_stall: teammate=$teammate pane=$paneId"
        echo "$capture" | tail -40
      fi
    done
    ```

    Guardrails:
    - Never kill a pane that matched `Waiting for team lead approval`. Path (a) and Path (b) cleanup in step 4 do not apply to stalled panes; the work is alive, blocked on a decision.
    - Never auto-respond. The Phase 5e protocol below defines the team-lead's response mechanisms; this step only surfaces the anomaly.
    - If `$SWARM_SOCKET` is empty (claude-swarm not running, or socket name changed upstream), log `swarm_socket_missing` and skip the step. Do not fall back to the `default` socket. That would scan the wrong panes.

1b. **Contract-comment scan (mandatory).** Before any state-collection step, scan every parent epic this team owns for new contract-related comments since the last tick. Contract amendments must be applied first because they reshape the autonomy budget every other step reads.

```bash
for epic in $(jq -r '.epics[]?' ~/.claude/teams/<team-name>/config.json 2>/dev/null); do
  # Fetch comments since last tick (cursor stored at ~/.claude/teams/<team-name>/contract-cursor-<epic>.txt)
  CURSOR=$(cat ~/.claude/teams/<team-name>/contract-cursor-${epic//\//_}.txt 2>/dev/null || echo "1970-01-01T00:00:00Z")
  # `gh issue view` has no --argjson (that is a jq flag); emit the raw envelope and
  # pipe to jq, which does bind external JSON. `index` is portable across jq versions.
  gh issue view "$epic" --json comments \
    | jq --argjson collab "$(gh api repos/$REPO/collaborators --jq '[.[].login]')" \
        ".comments[] | select(.createdAt > \"$CURSOR\") | select(.author.login as \$a | \$collab | index(\$a))" \
    > /tmp/new-contract-comments.jsonl
  date -u +%Y-%m-%dT%H:%M:%SZ > ~/.claude/teams/<team-name>/contract-cursor-${epic//\//_}.txt
done
```

For each comment body, scan in priority order:

   - **`STOP CONTRACT: <reason>`.** Highest priority. Pause every in-flight teammate on this epic via SendMessage. Set every open sub-issue label to `paused`. Post a confirmation comment on the epic naming the stop reason and the user. Do not process subsequent steps for this epic on this tick. The user must comment `AMEND CONTRACT:` or `STOP CONTRACT: abandon` to either resume or close the chain.

   - **`AMEND CONTRACT: <change>`.** Read the change. Update the parent epic's `## Autonomy contract` section: re-derive Goal / Acceptance / Autonomy budget / Always-park reflecting the change. Append a new entry to `## Autonomy contract history` with the timestamp, user, and original comment URL. If the amendment unblocks a sub-issue currently labeled `awaiting-amendment`, remove that label so the next contract-budget check reads green. Post a confirmation comment on the epic naming what changed.

   - **`OK`.** Only meaningful on a draft contract that has not yet been recorded (Phase 1a awaiting confirmation). Move the draft contract from `## Autonomy contract (draft)` to `## Autonomy contract` with `OK'd: <ts> by <user>` line; create the parent-epic decomposition (Phase 2) and first sub-issues (Phase 4). Do not respond to `OK` after the contract is already recorded.

   - **`REVISE: <reason>`** posted on a sub-issue (not the epic). Route per Phase 6 (Backtrack) back to the artifact's authoring modality with the user's revision note in the brief.

   - **🛠️ reaction on a park comment.** Detect via `gh api repos/$REPO/issues/$N/comments/$CID/reactions`. If a 🛠️ reaction was added since last tick from an authorized user, post a numbered-options comment offering the most-likely amendments derived from the park reason. The user replies with a number; the next tick's contract-comment scan picks up the reply, converts to canonical `AMEND CONTRACT: <change>`, applies, and removes the placeholder comment. The user-facing UX is reaction → reply with `1` (or `2`, etc.) → orchestrator amends. The audit trail records the canonical `AMEND CONTRACT:` entry.

   Authorization: only repo collaborators can amend, stop, or OK. Comments matching the grammar from non-collaborators are surfaced to the team-lead via SendMessage but otherwise ignored.

2. **Review-ready sub-issues.** `gh issue list --label review --json number,title,url,labels` for this repo. Any hit is a candidate for Step 5c.
3. **Open PRs.** `gh pr list --json number,url,isDraft,mergeable,statusCheckRollup` to see which draft PRs are green.
4. **Auto-shutdown + auto-delete idle done teammates.** Two paths run on every tick. The `shutdown_request` protocol is unreliable, teammates' system prompts frequently do not handle it, so direct pane kill plus roster rewrite is the reliable path.

   **First, compute the authoritative list of live panes.** This is the one command the loop depends on getting right:

   ```bash
   ALIVE=$(tmux list-panes -a -F '#{pane_id}' 2>/dev/null | sort -u)
   ```

   On non-tmux pane backends (Conductor / macOS UUID `tmuxPaneId`s), `$ALIVE` cannot be
   enumerated. Every roster id would test as "dead" and trigger a false dead-pane cleanup.
   Gate path (a)/(b) on a tmux-native id sample; downgrade loudly otherwise:

   ```bash
   SAMPLE_ID=$(jq -r '.members[] | select(.name != "team-lead") | .tmuxPaneId // empty' \
               ~/.claude/teams/<team-name>/config.json | head -1)
   case "$SAMPLE_ID" in
     '%'*) ;;  # tmux-native; proceed with path (a)/(b)
     ?*) echo "pane_backend: non-tmux id format ($SAMPLE_ID); Step 4 path (a)/(b) disabled this tick"; return 0 ;;
   esac
   ```

   **Do NOT** use `tmux list-panes -a | awk '{print $NF}'` to harvest pane IDs. `tmux list-panes -a` prints the literal string `(active)` as the last whitespace-separated field on any pane that is currently the active pane in its window. `awk '{print $NF}'` on that output returns `(active)`, NOT the pane id, and the resulting set silently drops every active pane. Producing false "dead" verdicts on the panes the loop most needs to protect. Use `-F '#{pane_id}'`. Always.

   **Path (a): dead-pane cleanup.** For every teammate (other than `team-lead`), if their `tmuxPaneId` is NOT in `$ALIVE` (`echo "$ALIVE" | grep -qx "<paneId>"` returns false), their process is already gone. Remove them from the roster; no kill command needed:

   ```bash
   jq --arg name "<teammate-name>" \
      '.members |= map(select(.name != $name))' \
      ~/.claude/teams/<team-name>/config.json > /tmp/team.tmp \
      && mv /tmp/team.tmp ~/.claude/teams/<team-name>/config.json
   ```

   **Path (b): done-teammate cleanup.** For every teammate whose pane IS alive but whose assigned sub-issue is in a terminal state (`done`, `abandoned`, closed) OR whose assigned PR is merged, kill the pane and rewrite the roster:

   ```bash
   tmux kill-pane -t <paneId>
   jq --arg name "<teammate-name>" \
      '.members |= map(select(.name != $name))' \
      ~/.claude/teams/<team-name>/config.json > /tmp/team.tmp \
      && mv /tmp/team.tmp ~/.claude/teams/<team-name>/config.json
   ```

   Guardrails (the loop enforces these before touching anything):
   - Never delete `team-lead` from the roster. Never kill the team-lead pane.
   - Path (b) requires BOTH pane-alive AND sub-issue-terminal. Neither alone is enough.
   - **A teammate waiting on you is not terminal, however terminal its label looks.** One whose last SendMessage reported `NEEDS_CONTEXT` or `BLOCKED`, with no team-lead reply since, is alive and load-bearing: interactive skills escalate taste decisions and pending input up to the orchestrator, which surfaces them to the user. The reply is what unblocks it. Killing it discards the in-progress reasoning and buys nothing.
   - Path (a) requires only pane-missing from `$ALIVE`. A teammate whose work is incomplete but whose process died is still removed. Their pane is gone either way, and the work needs to be re-dispatched.
   - When uncertain whether a teammate is truly done, leave them. A held pane is cheaper than lost work.

5. **Auto-gate + update epic progress.** For each sub-issue whose acceptance is mechanically verifiable (clean draft PR green on CI, review-ready comment matching the acceptance criterion, etc.), run **Step 5c.1 and Step 5c.2**: transition `review → plan-approved`, post the gating comment, close the sub-issue, then rewrite the parent epic's `## Progress` section. Skip the sub-issue when tests are red, CI is pending, or the acceptance artifact requires human judgment (any criterion the modality delegates to `/safer:review-senior`). Before any auto-gate transition fires, run **Step 5c.0** against the linked PR's reviewer body; skip the sub-issue if any of the four condition patterns matches.

   **Implement-\* gate carries a mandatory verify dispatch.** For sub-issues with `safer:implement-*` modality, the auto-gate does NOT close at `plan-approved`. The full lifecycle is:

   1. `review → plan-approved` (this auto-gate step). Review verdict accepted, PR is merge-ready.
   2. PR is merged (team-lead-driven, possibly user-authorized; not auto-merged by this loop).
   3. `plan-approved → verifying` (next auto-monitor tick after merge): dispatch `/safer:verify` against the merged commit per the verify dispatch template. The verify dispatch is unconditional. Verify is the default merge gate for every implement-\* sub-issue, not a per-team customization. Skip only when a `/safer:verify` sub-issue already exists for this commit (idempotency).
   4. `verifying → done` (after verify emits SHIP): post the gating comment with the verify verdict URL, close the sub-issue. On HOLD: route per Phase 6 (typically back to `/safer:implement-*` with the verify findings).

   The auto-gate never skips verify on implement-\* sub-issues. A sub-issue at `plan-approved` whose PR is merged and has no verify verdict on the merge commit is a candidate for auto-dispatch to verify on every tick until the verdict lands.

5a. **Surface process issues from teammate SendMessages (mandatory).** Per PRINCIPLES.md → Process issues are first-class artifacts, every teammate's closing SendMessage carries a `Process issues:` field. The orchestrator scans the SendMessage stream each tick and:

   - Aggregates non-empty `Process issues` entries from this tick's teammates.
   - Surfaces them to the user as a one-line summary in the next status update. NOT buried in a verdict body, NOT silently dropped because the substantive verdict was APPROVE.
   - For structural issues (the same `Process issues:` line recurring across multiple dispatches), files a follow-up sub-issue against the parent epic so the doctrine catches the pattern.

   The failure mode this rule prevents: a teammate completes the assigned task, gets a clean APPROVE, the user moves on. And the friction the teammate hit recurs on every subsequent dispatch because no one ever named it. The orchestrator is the only seat that sees enough dispatches to spot the pattern; if the orchestrator buries it, no one fixes it.

   "Empty" (`Process issues: none`) is a valid value and not surfaced. The rule fires only on non-empty entries.

5b. **Live `## Status` section rewrite (mandatory).** After every state-change in this tick (label transition, dispatch, contract amendment, park, stop), rewrite the parent epic's `## Status` section. The section is the cold-start reader's at-a-glance view; a fresh agent landing on the epic at any moment should read this section and know current state without scrolling comments.

   Format:

   ```markdown
   ## Status

   **Updated:** <ISO timestamp>

   **Contract:** <one-line summary derived from Goal>; <budget summary, e.g., "diagnose → impl-junior → review → verify → merge"> (`OK'd <ts>`).

   **In flight:**
   - #<N> <modality>: <state, e.g., "implementing">; teammate: <name>; PR: <url or none>.
   - #<N> <modality>: <state>; teammate: <name>.

   **Awaiting amendment:** <list of sub-issues labeled `awaiting-amendment`, with reason in one line each>; or "none".

   **Last 3 actions:**
   - <ts> dispatched <modality> on #<N>
   - <ts> auto-gated #<N> review → plan-approved
   - <ts> opened PR #<M> for #<N>

   **Next action:** <what the next cron tick will do, in one line>.
   ```

   The section is replaced wholesale on every rewrite (no diff-merge complexity). Rewrite the parent epic body in place via `gh issue edit "$EPIC" --body "$NEW_BODY"`. Idempotency: if no state changed this tick, do not rewrite; the timestamp would change for nothing.

5c. **Wake-up digest on autopilot completion.** When every sub-issue is in `done` or `abandoned` state AND the parent epic is in autopilot mode (the contract authorized merge without parking), post one consolidated digest comment on the epic before closing it. The digest is the user's "I went to bed; here's the night" artifact.

   Digest template:

   ```markdown
   ## Wake-up digest

   **Session:** <SESSION>
   **Started:** <epic created ts> · **Finished:** <ts>
   **Duration:** <human-readable>

   **Contract goal.** <Goal from contract, one paragraph>

   **What shipped.**
   - <PR URL>: <one-line PR title> (verify: <SHIP|HOLD>)
   - <PR URL>: <title> (verify: <verdict>)

   **Contract events.**
   - <ts> contract OK'd
   - <ts> AMEND CONTRACT: <one-line change> by <user>
   - <ts> sub-issue #<N> parked (reason: <one-line>); resumed <ts>
   - <ts> wake-up digest

   **Process issues seen.** <bulleted list of non-empty Process issues entries from teammate SendMessages, deduplicated; or "none">.

   **Acceptance.**
   - [x] <criterion>: <evidence URL>
   - [x] <criterion>: <evidence URL>

   **Health note.** <one line: any flake, transient infra, or recurring friction worth flagging next session; or "clean run">.
   ```

   Post once per epic; subsequent ticks read the existing digest comment and skip. Idempotency key: presence of a comment whose body starts with `## Wake-up digest` and matches this epic's session.

6. **Auto-dispatch pending work (work-queue scan).** The prior steps react to state the loop already knows about. Step 6 is the proactive scan: enumerate pending sub-issues across every repo this team serves, filter out the ones that are already in flight, prioritize what is left, and dispatch up to the per-tick cap. Without this step the orchestrator idles between user prompts even when work is queued. Step 6 is mandatory once a team is installed.

**Step 6a: enumerate pending work.** Scan every repo this team watches (`~/.claude/teams/<team-name>/config.json` carries `repos: []`; fall back to the current repo if the field is absent). For each, list open sub-issues whose labels name a dispatchable modality:

```bash
for repo in $(jq -r '.repos[]?' ~/.claude/teams/<team-name>/config.json 2>/dev/null || echo "$REPO"); do
  gh issue list --repo "$repo" --state open --limit 200 \
    --json number,title,labels,url,body \
    --jq '.[] | select(.labels | map(.name) | any(test("^safer:(implement-(junior|senior|staff)|verify|spike|research|requirements)$")))'
done > /tmp/orch-queue.jsonl
```

Filter the queue in-process. The first two filters are body-only and cheap; the deferral and idempotency markers require per-candidate `gh issue view --json comments` calls and should run last so we only pay for survivors:

- Drop any row whose title or body references a teammate already in `config.json` `.members[].name` (already in flight).
- Drop any row whose parent epic (from `## Parent` or `Parent: #N` in the body) has a linked open PR authored by the dispatching team (somebody is on it).
- For each surviving candidate, check the `safer:deferred` label and deferral marker (see subsection below).
- For each surviving candidate, fetch comments and scan for the idempotency marker. The marker is `<!-- orchestrate:dispatched teammate=<name> at=<iso> -->`; drop the candidate if any comment matches and its `at=` timestamp is within the last 30 minutes (re-entrance guard against a team-lead crash mid-tick):

  ```bash
  window_start=$(date -u -d '30 minutes ago' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
              || date -u -v-30M +%Y-%m-%dT%H:%M:%SZ)
  marker_ts=$(gh issue view "$N" --repo "$repo" --json comments \
    --jq '.comments[].body
      | capture("<!-- orchestrate:dispatched teammate=[A-Za-z0-9_-]+ at=(?<ts>[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z) -->")
      | .ts' \
    | sort | tail -1)
  if [ -n "$marker_ts" ] && [ "$marker_ts" \> "$window_start" ]; then
    # marker is fresh, skip this candidate
    continue
  fi
  ```

## Deferral marker

A sub-issue labeled `safer:deferred` carries a structured comment that records why it is held and until when. The filter drops deferred sub-issues whose `until` condition has not been satisfied.

**Writing markers: use `safer-defer`.** Never add the `safer:deferred` label by hand; the only sanctioned way to defer a sub-issue is the `safer-defer` binary, which writes the marker comment AND adds the label in one operation. Self-validates against the marker grammar before publishing. Refuses to ship a malformed marker. This makes broken-marker silent-failure unrepresentable by construction (Principle 1: types beat tests; the broken state is impossible to write rather than detected after the fact):

```bash
safer-defer --issue 142 --reason "awaiting upstream API spec" \
            --until "2026-05-15T00:00:00Z"
safer-defer --issue 142 --reason "blocked by ENG-1234" \
            --until "condition:linear-ticket-ENG-1234-closed"
safer-defer --issue 142 --clear              # remove the deferral
safer-defer --issue 142 --check              # validate marker(s) on issue
```

Marker format (in an HTML comment on the sub-issue, written by `safer-defer`):

```
<!-- safer:deferred reason="<free-form string, quote-escaped>" until="<ISO8601|condition:...>" added-by="<team-member-name>" at="<ISO8601>" -->
```

`until` values:

| Shape | Semantics | Example |
|---|---|---|
| ISO8601 UTC | Filter drops sub-issue until wall-clock time ≥ `until` | `2026-04-20T00:00:00Z` |
| `condition:<freeform>` | Filter drops unconditionally; unblock requires `safer-defer --clear` (or human label removal) | `condition:upstream-pr-merged:chughtapan/cc-judge#14` |

Regex (ECMA/PCRE compatible; `until` field must be ISO8601 or `condition:*`):

```
<!-- safer:deferred reason="(?<reason>(?:[^"\\]|\\.)*)" until="((?:\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z)|(?:condition:[^"]+))" added-by="(?<by>[^"]+)" at="(?<at>\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z)" -->
```

Filter logic (fail-closed): Drop any sub-issue labeled `safer:deferred` unless its marker's `until` condition has passed. If the label is present but no marker comment is found, log `deferred_marker_missing: issue=#N` and surface in the next wake-up digest as a repair item, the user runs `safer-defer --check --issue N` to inspect, then either re-defers via `safer-defer` or clears via `safer-defer --clear`. Never silently re-park beyond one tick. If the marker is malformed (legacy hand-written marker that doesn't match the grammar), the same surface-and-repair path applies. With `safer-defer` as the canonical writer, both failure modes only occur on legacy state, not on new deferrals.

Pseudocode:

```bash
if gh issue view "$N" --repo "$repo" --json labels \
     --jq '.labels[].name' | grep -qx 'safer:deferred'; then
  marker=$(gh issue view "$N" --repo "$repo" --json comments --jq '
    .comments[].body |
    capture("<!-- safer:deferred reason=\"(?<r>(?:[^\"\\\\]|\\\\.)*)\" until=\"(?<u>(?:\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}Z)|(?:condition:[^\"]+))\" added-by=\"[^\"]+\" at=\"[^\"]+\" -->")
    | .u' | tail -1)
  case "$marker" in
    "")                 echo "deferred_marker_missing: issue=#$N"; continue ;;
    condition:*)        continue ;;
    ????-??-??T*)
      now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
      [ "$marker" \> "$now" ] && continue
      ;;
    *)                  echo "deferred_marker_malformed: issue=#$N marker=$marker"; continue ;;
  esac
fi
```

The surviving rows are the candidate queue. Record the count (`queue_len`) for the log line in 6b.

**Step 6b: compute capacity.** Pane ceiling is set to 20 based on an empirical observation that tmux starts rejecting splits as the pane count approaches that range on default kernels; `"no space for new pane"` from the Agent tool is the authoritative safety net if the ceiling is ever wrong in a given environment. Count live panes once per tick:

```bash
live_panes=$(tmux list-panes -a -F '#{pane_id}' 2>/dev/null | wc -l)
pane_ceiling=20
spare=$(( pane_ceiling - live_panes ))
per_tick_cap=3
budget=$(( spare < per_tick_cap ? spare : per_tick_cap ))
```

If `budget <= 0`: log `at capacity: panes=$live_panes, queue_len=$queue_len, skip dispatch`. Skip to the next tick. The cap of 3 new dispatches per tick is hard. Do not raise it even when `spare > 3`, so a single tick never over-saturates the team.

**Step 6c: prioritize pending.** Sort the surviving candidates by tier, then by parent-epic decomposition order within a tier. The four tiers, highest first:

1. **Blocker-level.** Sub-issue is on a parent epic's critical path AND is currently at label `review`. These gate downstream dispatches; unblocking them has the highest leverage.
2. **Spike or verify.** These unblock downstream implementation (spike answers a go/no-go; verify finalizes a PR).
3. **Implement-\***. Ordered by the parent epic's decomposition table (not arbitrary).
4. **Research.** Long-running, rarely merge-blocking.

Within a tier, break ties by oldest `createdAt`. Do not invent additional heuristics; the four tiers are the ceiling of complexity for this step.

Executable reference (feed `<tier>\t<created_at_epoch>\t<issue_number>` on stdin):

```bash
# tier: 1=blocker(review on critical path), 2=spike|verify, 3=implement-*, 4=research
priority_sort() {
  sort -k1,1n -k2,2n | cut -f3
}
```

**Step 6d: post marker first, then dispatch (order matters).** For each candidate in priority order, up to `budget`, dispatch using the inline template that matches its `safer:<modality>` label (see *Per-modality dispatch prompt templates* below). The marker MUST be posted before the `Agent` call so a concurrent next tick reading comments in Step 6a sees it and skips; if we dispatched first, a slow Agent spawn (>2 min) plus the cron interval could re-dispatch the same issue. Dispatch `Agent` call includes the `model` parameter per the Model routing table. Every modality has a default; override only if user explicitly names a different model.

For each candidate:

1. **Post the idempotency marker first** (reserves the sub-issue for this dispatch):

   ```bash
   TEAMMATE_NAME="<modality>-<issue-number>"
   MARKER_BODY="<!-- orchestrate:dispatched teammate=$TEAMMATE_NAME at=$(date -u +%Y-%m-%dT%H:%M:%SZ) -->"
   # gh issue comment prints the comment URL on success; parse the comment id
   # out of the `#issuecomment-<id>` fragment so step 3 can delete it on rollback.
   MARKER_URL=$(gh issue comment "$N" --repo "$repo" --body "$MARKER_BODY" 2>/dev/null) \
     || { echo "marker post failed; skip"; continue; }
   MARKER_ID="${MARKER_URL##*issuecomment-}"
   ```

2. **Dispatch the teammate.** Use `TeamCreate` (if the team does not exist) + `Agent` with `team_name` and the unique teammate `name`. Fill template placeholders per the schema in *Per-modality dispatch prompt templates*. Pass `source: orchestrate-auto-dispatch` in the prompt header so the audit trail is visible. Never standalone `Agent` without `team_name`; never invoke the modality via in-session `Skill`.

3. **On dispatch failure, delete the marker** so the next tick is free to retry. The Agent tool returning `"no space for new pane"`, a `TeamCreate` error, or any other dispatch error must roll back the reservation:

   ```bash
   gh api --method DELETE "repos/$repo/issues/comments/$MARKER_ID" >/dev/null 2>&1 || true
   ```

   Then break the dispatch loop (the ceiling was hit, or team state is bad); the remaining queue defers to the next tick.

The 30-minute freshness window in Step 6a is deliberate: if an Agent process crashed *after* posting the marker but *before* producing an artifact, the sub-issue is eligible for re-dispatch on the next tick past that window. Markers older than 30 minutes with no resulting PR are treated as stale reservations.

Stop iterating the moment any of these fire: `budget` reaches 0, the Agent tool returns `"no space for new pane"` (ceiling hit mid-tick; marker was already rolled back in step 3 above), or the candidate queue is empty.

**Failure modes Step 6 handles (fail-closed).** Every case below is a skip, not a fix.

- **Pane ceiling hit mid-dispatch.** Catch `"no space for new pane"` from the Agent tool. Log `pane_ceiling_hit: queued=<remaining>`. Break the dispatch loop; the remaining queue defers to the next tick.
- **Sub-issue already has an open PR.** Skip. The implementer is already working; re-dispatching would fork.
- **Sub-issue has a teammate in `config.json`.** Skip. Same reason.
- **Idempotency marker posted within the last 30 minutes.** Skip.
- **Label-to-modality mismatch.** If the sub-issue carries two `safer:*` modality labels, or a `safer:*` label not in the catalog, log `label_modality_mismatch: issue=#N labels=<list>` and skip. Never guess a modality.
- **`safer:implement-staff` without a `plan-approved` parent epic.** Skip. Staff-tier work requires an architect sign-off; auto-dispatching without one is a Ratchet violation.
- **`safer:verify` on a PR that is not `MERGEABLE state=CLEAN`.** Skip. Verify runs against a known-green PR; running it earlier produces noise that has to be re-run anyway.
- **Parent epic is missing or closed.** Skip. A sub-issue with no live parent is an orchestration artifact to be cleaned up by a human, not auto-dispatched.

**What the loop MUST NEVER do.**

- Kill the team-lead pane, or delete `team-lead` from the roster.
- Kill or delete a teammate whose `isActive == true`, or whose sub-issue is not terminal. Both conditions must hold, or the loop leaves them.
- Kill or delete a teammate whose latest team-lead message was `NEEDS_CONTEXT` or `BLOCKED` and is still awaiting a team-lead reply. Waiting-on-orchestrator state is alive state, not terminal state. The pane holds load-bearing in-progress reasoning context that gets lost on kill.
- Merge a PR with failing tests, failing CI, or unresolved review comments.
- Gate a sub-issue whose acceptance criteria require judgment the loop cannot encode (design review, spec approval, any criterion the modality's `review` step delegates to `/safer:review-senior`).
- Write code, edit files, or run `/safer:<modality>` skills in-session. Dispatch via teammate only.

If any check above is ambiguous, the loop skips that action and leaves it for the next human-driven tick. Ambiguity is not a bug; acting on ambiguity is.

**Tuning the interval.**

Default is `*/2 * * * *` (every 2 minutes) and you should not change it without a specific reason. Slower intervals make idle-teammate and merge-ready PR detection lag by multiple minutes and re-introduce the exact "orchestrate sits idle" failure this step exists to prevent.

| Epic shape | Interval |
|---|---|
| Any active epic with teammates dispatched | `*/2 * * * *` (2 min, mandatory default) |
| Single-modality task | no loop; orchestrate is the wrong skill |

**Cancel.** Keep the job id from `CronCreate`. To stop the loop: `CronDelete({ jobId: "<id>" })`. Also run this in Phase 7 at close-out (see below).

