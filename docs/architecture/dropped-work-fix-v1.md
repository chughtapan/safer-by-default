# Dropped-Work Fix — Architecture v1

**Spec / parent issue:** https://github.com/chughtapan/safer-by-default/issues/71
**Investigator writeup:** https://github.com/chughtapan/safer-by-default/issues/71#issuecomment-4274793346
**Prior art:** https://github.com/chughtapan/safer-by-default/pull/67 (Step 6 work-queue scan)
**Status:** DONE_WITH_CONCERNS (2 open questions, listed in §8)

---

## 1. Summary

Two primitives close the 7 Class A + 2 Class D drops named in the sbd#71 investigation.

First, the cron prompt template that runs the orchestrator tick is rewritten to enumerate Step 6a–6d as mandatory tick work. Step 6 lives in `skills/orchestrate/SKILL.md` today as doctrine; the cron that actually drives the loop does not reference it by name and does not execute it. The fix is a prompt-template change, not a new control path — what the LLM reads per tick is what runs per tick.

Second, deferral is promoted from chat-string to GitHub metadata. A sub-issue gets the `safer:deferred` label and a structured comment (`<!-- safer:deferred reason=… until=… added-by=… -->`); the Step 6a filter drops deferred sub-issues whose `until` has not elapsed. Class D drops stop accruing because "holding pending user confirmation" becomes a label state, not a conversation memory.

Both primitives gate on a single regression test: any sub-issue that goes N=3 ticks without one of {teammate assigned, open PR, closed, `safer:deferred`} fails the guard.

## 2. Modules

Orchestrate is a skill, not a package. "Modules" below are the minimum-cohesion changes a reviewer can read as independent units. Each entry names the file that carries it, its responsibility, and its dependencies.

1. **`cron-prompt-template`** — `skills/orchestrate/SKILL.md` §Phase 5d, "Install" subsection.
   - *Purpose:* the string that `CronCreate({ prompt: … })` receives. Rewritten so the cron tick enumerates Step 6a–6d as mandatory, not as "auto-dispatch if capacity exists."
   - *Public surface:* the literal prompt body between the code fence.
   - *Depends on:* `deferred-filter` (Step 6a's drop predicate references the deferral marker grammar).
   - *Error channel:* cron prompt malformed ⇒ cron tick no-ops ⇒ regression guard (§4) detects stall.

2. **`deferred-marker-grammar`** — `skills/orchestrate/SKILL.md` §Phase 5d Step 6a, new subsection "Deferral marker."
   - *Purpose:* canonical comment format that records *why* a sub-issue is held and *until when*. Paired with the `safer:deferred` label.
   - *Public surface:* the regex / marker shape described in §3 below.
   - *Depends on:* the `safer:deferred` label being added to the sub-issue; `gh label create safer:deferred` is a one-time repo setup step.
   - *Error channel:* malformed marker ⇒ Step 6a treats the sub-issue as *not* deferred (fail-open to dispatch) and emits `deferred_marker_malformed: issue=#N`.

3. **`deferred-filter`** — `skills/orchestrate/SKILL.md` §Phase 5d Step 6a, new filter clause.
   - *Purpose:* Step 6a drops any sub-issue labeled `safer:deferred` whose structured comment carries an `until` that has not elapsed.
   - *Public surface:* a new bullet in the filter list; pseudocode in §3.
   - *Depends on:* `deferred-marker-grammar`.
   - *Error channel:* same as the marker grammar.

4. **`drop-detection-regression-guard`** — new test file `tests/orchestrate/drop-detection.test.ts` (language follows the repo's existing test harness; see §6).
   - *Purpose:* one integration test that files a synthetic sub-issue, runs N=3 simulated ticks, and asserts the sub-issue reaches one of {assigned, PR, closed, deferred}.
   - *Public surface:* one `it(...)` block.
   - *Depends on:* the cron-prompt-template change being wired; deferred-filter recognizing the marker.
   - *Error channel:* test failure — the exact regression the investigator named.

No other files change. The `safer:deferred` label itself is created once per watched repo via `gh label create` and is not a code module.

## 3. Interfaces

### 3.1 Cron prompt template (cron-prompt-template module)

The `CronCreate` prompt body is rewritten to enumerate Step 6 explicitly. The current prompt (approximated from PR#67) names auto-dispatch in the abstract. The replacement:

```
Each tick, in order:

1. Roster scan: read ~/.claude/teams/<team>/config.json; list active teammates + panes.
2. Review sweep: gh issue list --label review; queue for Step 5c gating.
3. PR sweep: gh pr list; note green drafts for 5c auto-gate.
4. Dead-pane + done-teammate cleanup: Phase 5d step 4(a) and 4(b).
5. Auto-gate + update epic progress (Step 5c.1 + 5c.2) for each mechanically-
   verifiable review-ready sub-issue.
6. Auto-dispatch pending work (MANDATORY — execute Step 6a–6d in order):
   6a. Enumerate: scan every repo in config.repos; filter out
       in-flight + already-marked + deferred sub-issues.
   6b. Capacity: compute `budget = min(spare-panes, per_tick_cap=3)`.
   6c. Prioritize: tier 1 blocker-review → 2 spike/verify → 3 implement-* → 4 research.
   6d. Post marker, then dispatch, up to `budget`. Rollback marker on dispatch failure.

If Step 6 would skip (budget=0, queue empty, all candidates deferred), log the
reason and emit one line: `tick_summary: scanned=<n> dispatched=<k> skipped=<reason>`.

Never write code. Never invoke modalities via in-session Skill. Standalone Agent
without team_name is forbidden. All dispatch routes through TeamCreate + Agent
with team_name per Phase 5a.
```

The numbered list is the interface. Step 6 is no longer "auto-dispatch if capacity" — it is a named sub-procedure with four enumerated parts that the LLM reading the prompt cannot collapse into a single vague bullet.

### 3.2 Deferral marker grammar (deferred-marker-grammar module)

One comment on the sub-issue. Two-part body: HTML-commented structured header, then human-readable prose.

```
<!-- safer:deferred reason="<free-form string, quote-escaped>" until="<ISO8601|condition>" added-by="<team-member-name>" at="<ISO8601>" -->

Deferred: <one-line reason, human-readable>.
Unblock when: <condition or date>.
```

Grammar (regex, one line; engine: ECMA/PCRE compatible):

```
<!-- safer:deferred
     reason="(?<reason>(?:[^"\\]|\\.)*)"
     until="(?<until>[^"]+)"
     added-by="(?<by>[^"]+)"
     at="(?<at>\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z)" -->
```

`until` values:

| Shape | Semantics | Example |
|---|---|---|
| ISO8601 UTC | `safer:deferred` filter drops the sub-issue until wall-clock time ≥ `until` | `2026-04-20T00:00:00Z` |
| `condition:<freeform>` | Filter drops unconditionally; unblock requires a human to remove the label | `condition:upstream-pr-merged:chughtapan/cc-judge#14` |

The label `safer:deferred` is the primary key the filter sees. The marker comment is the reason-of-record. Presence of label without marker ⇒ filter treats as malformed (fails open; logs).

### 3.3 Step 6a filter predicate (deferred-filter module)

New clause added to Step 6a's filter list, positioned *after* the body-only filters and *before* the idempotency-marker scan (so the cheap label check runs before the per-candidate `gh issue view --json comments` call):

```
- Drop any row whose labels include `safer:deferred`. For those rows, fetch
  the latest comment matching the deferred-marker regex (§3.2). If the
  marker's `until` is ISO8601 and the parsed timestamp is > now (UTC), skip
  the candidate. If the marker's `until` starts with `condition:`, skip
  unconditionally. If no marker is found, log
  `deferred_marker_missing: issue=#N` and skip (fail-closed for safety;
  the label alone signals human intent).
```

Pseudocode (shell; matches the style of the existing Step 6a block):

```bash
if gh issue view "$N" --repo "$repo" --json labels \
     --jq '.labels[].name' | grep -qx 'safer:deferred'; then
  marker=$(gh issue view "$N" --repo "$repo" --json comments --jq '
    .comments[].body |
    capture("<!-- safer:deferred reason=\"(?<r>(?:[^\"\\\\]|\\\\.)*)\" until=\"(?<u>[^\"]+)\" added-by=\"[^\"]+\" at=\"[^\"]+\" -->")
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

### 3.4 Regression test signature (drop-detection-regression-guard module)

One test, behavioral:

```
it("a filed sub-issue reaches assigned|pr|closed|deferred within N ticks", async () => {
  throw new Error("not implemented");
});
```

Constants: `N = 3`, `TICK_INTERVAL_SEC = 120`. Total wall-clock budget `360s`. Implementation belongs to `implement-senior` (§7).

## 4. Data flow

Tick-level flow (cron fires every 2 min):

```
  cron-tick
      │
      ▼
  Phase 5d (1 → 6) per cron prompt
      │
      ├─ 1-5: existing sweeps (unchanged)
      │
      └─ 6: Auto-dispatch
             │
             ▼
         6a. enumerate(repos)
             │
             ├─ body/title filters (cheap)
             │
             ├─ deferred-filter ──► safer:deferred label?
             │                        │
             │                        ├─ yes + marker.until in future → SKIP
             │                        ├─ yes + marker.until past       → keep
             │                        └─ yes + marker missing           → SKIP + log
             │
             └─ idempotency-marker scan (per-candidate gh issue view)
                    │
                    ▼
         6b. capacity(live_panes, per_tick_cap=3)
                    │
                    ▼
         6c. prioritize(tier 1 → 4, createdAt tiebreak)
                    │
                    ▼
         6d. for each candidate up to budget:
                post marker → Agent dispatch → (fail) rollback marker
```

Deferral flow (team-lead-initiated):

```
  team-lead decides "hold sub-issue #N"
      │
      ▼
  gh issue edit #N --add-label safer:deferred
      │
      ▼
  gh issue comment #N --body "<safer:deferred marker>"
      │
      ▼
  next cron tick: Step 6a deferred-filter drops #N
      │
      ▼
  (until elapses OR label removed)
      │
      ▼
  cron tick after unblock: Step 6a re-admits #N to the queue
```

Regression-guard flow (test-time):

```
  test setup: gh issue create --label safer:implement-junior,planning
      │
      ▼
  run 3 simulated ticks against the orchestrate prompt
      │
      ▼
  assert: #N now has at least one of
          { teammate in config.json, open PR referencing #N,
            state=closed, safer:deferred label }
      │
      ├─ yes → pass
      └─ no  → fail (this is the exact sbd#71 Class A drop)
```

## 5. Errors

Failure modes each module exposes, named explicitly so the implementer handles them at the site rather than "probably-ok" defaults.

| Module | Error tag | Trigger | Handler |
|---|---|---|---|
| cron-prompt-template | `tick_prompt_parse_fail` | LLM misreads prompt; step skipped | Regression guard (§4) fails if three consecutive ticks do not execute Step 6; operator re-installs cron. |
| deferred-marker-grammar | `deferred_marker_malformed` | Marker present but regex does not match | Log `issue=#N marker=<raw>`; Step 6a **skips the candidate** (fail-closed — absent a readable marker, do not re-dispatch a label a human added). |
| deferred-marker-grammar | `deferred_marker_missing` | `safer:deferred` label but no matching comment | Log + skip (fail-closed, same as malformed). |
| deferred-filter | `deferred_until_unparseable` | `until` neither ISO8601 nor `condition:*` | Log + skip. |
| deferred-filter | `deferred_label_missing_after_unblock` | Marker comment says expired but label still present | Filter admits the candidate; it is Step 6c's problem whether to dispatch. Label drift is eventually-consistent. |
| drop-detection-regression-guard | `drop_guard_timeout` | 3 ticks elapsed with no teammate, PR, close, or deferral | Test fails with the exact issue number, labels, and comment count; CI blocks the merge. |

No `throw new Error("…")` sites. Every module error is a log line with a named tag and a routed handler.

## 6. Dependencies

No new libraries. Every module is markdown text (in SKILL.md) or a test written in the repo's existing harness.

| Dependency | Version | License | Why |
|---|---|---|---|
| `gh` CLI | ≥ 2.40 | MIT | Already required by the orchestrate preamble; adds `gh label create`, `gh issue comment` calls the grammar needs. |
| `jq` | ≥ 1.6 | MIT | Already used by Step 6a for the marker regex; adds one more `capture(...)` call. |
| existing test harness | matches `spike/reentrance-tier1` branch setup | — | Drop-detection test piggybacks on whatever harness `tests/orchestrate/` already uses on main. If `main` has no such harness yet, `implement-senior` escalates (§8 Q2). |

The label `safer:deferred` is a one-time `gh label create` per watched repo. It is a runtime state, not a dependency.

## 7. Traceability

Each acceptance criterion in sbd#71 → the module that satisfies it.

| sbd#71 acceptance | Module(s) | Status |
|---|---|---|
| Step 6 invoked per tick (not doctrine-only) | `cron-prompt-template` | Designed. |
| Deferral stored as label + structured comment | `deferred-marker-grammar` | Designed. |
| Step 6a filter excludes deferred with future `until` | `deferred-filter` | Designed. |
| Team-lead posts marker on explicit defer | `deferred-marker-grammar` (grammar); team-lead docs update in `cron-prompt-template` | Designed. |
| Enumeration scope: scale concern at >4 repos | §8 Q1 (open question: keep current `config.repos`; cap at ~20) | Open. |
| Regression test for drop | `drop-detection-regression-guard` | Designed. |
| Routing: senior + junior sub-tasks | §8 (follow-up issues filed) | Designed. |

## 8. Open questions

Two. Each has a recommended default and an escalation target.

**Q1. Enumeration scale beyond 4 repos.** Today `config.repos: []` holds 4. At 20+ repos the per-tick `gh issue list --repo` fan-out + the per-candidate `gh issue view --json comments` marker scan could exceed the 2-minute cron window and eat into GitHub API rate limits (~5000 req/hr authenticated; ≈40 req/tick × 30 ticks/hr = 1200/hr at 4 repos — room to grow ~4×).

*Recommended default:* keep `config.repos` as the authoritative scope list. Document a soft cap of **20 repos per team** in `skills/orchestrate/SKILL.md` under Phase 5d Step 6a; beyond that, split into multiple teams (one cron each). No code change needed now.

*Escalation target:* `/safer:spec` if the cap proves wrong in practice (teams outgrow 20 before the soft-cap doc shows up in a retro).

**Q2. Regression-guard harness.** The repo's existing `tests/` layout varies by spike branch; `main` may not yet carry an `orchestrate/` test harness the drop-detection guard can plug into. Simulating "3 ticks" without a real cron may require either (a) a mocked cron runner or (b) a one-shot script that invokes the tick prompt 3× sequentially and then checks state.

*Recommended default:* (b) — a shell script `tests/orchestrate/drop-detection.sh` that creates a throwaway sub-issue in a dedicated `safer-drop-test` repo, invokes the orchestrator tick prompt 3× via the same mechanism the cron uses, then asserts via `gh issue view`. Keeps the test out of the TypeScript harness and avoids a new dev-dep.

*Escalation target:* `/safer:architect` of the test harness itself if the shell-script approach is rejected by `implement-senior`.

---

## Routing recommendations (per §7)

Two follow-up sub-issues. Sized.

### Follow-up A — `implement-senior`: Step 6 cron-invocation wiring

- **Scope:** rewrite `skills/orchestrate/SKILL.md` Phase 5d cron prompt template (§3.1 interface), add drop-detection regression guard (§3.4 interface, §8 Q2 recommended harness).
- **Acceptance:** (1) cron prompt template enumerates Step 6a–6d by name; (2) `tests/orchestrate/drop-detection.sh` (or equivalent) is committed; (3) running the test against the rewritten prompt passes; (4) `safer-diff-scope --head HEAD` reports `senior`.
- **Tier:** senior. Crosses `skills/orchestrate/SKILL.md` + new test file; within the Step 6 plan already approved in sbd#67.
- **Size estimate:** ~80-120 LOC (prompt string + regression test). One draft PR.

### Follow-up B — `implement-junior`: deferral label primitive

- **Scope:** add the "Deferral marker" subsection to `skills/orchestrate/SKILL.md` Phase 5d Step 6a (§3.2 interface), add the deferred-filter clause (§3.3 interface), document the `gh label create safer:deferred` one-time setup step.
- **Acceptance:** (1) marker grammar documented with regex; (2) Step 6a filter clause lands before the idempotency-marker scan; (3) `gh label create safer:deferred` appears in a setup doc or bin script; (4) both Class D candidates from sbd#71 (acg#12, acg#14) are listed in the PR body as the concrete repro.
- **Tier:** junior. Single module (one SKILL.md file), no new deps, no public surface change beyond doctrine.
- **Size estimate:** ~40-60 LOC (markdown + shell pseudocode). One draft PR.

Both follow-ups depend on this design doc being published. Neither depends on the other — they can run in parallel panes once dispatched.

## Confidence

**HIGH** on the root-cause-to-module mapping. Investigator's evidence (7/7 Class A same mechanism; 2/2 Class D same mechanism; Step 6 landed before sbd#69 dropped) is strong and repro steps are deterministic.

**MED-HIGH** on the cron-prompt-template choice (Option a). The alternative (Option c, `safer-orchestrate-tick` binary) is structurally cleaner — a binary cannot misread a numbered list — but the Agent tool that actually spawns teammates is LLM-only, so a binary can only own enumerate+filter+prioritize, not dispatch. Full-binary rewrite is a larger spec that should live as a follow-up if Option a's prompt-rewrite proves too fragile in practice. The 2-minute cron tick plus the regression guard catch Option a failure within one test cycle.

**MED** on the regression-guard mechanics (§8 Q2). Unknown whether `main` carries the harness the test needs; `implement-senior` will find out on first commit.

---

**Status:** DONE_WITH_CONCERNS
**Concerns:** Q1 (scale cap doc), Q2 (test harness shape). Both named, both routed.
