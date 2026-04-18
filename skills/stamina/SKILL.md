---
name: stamina
version: 0.1.0
description: |
  Fan-out review adapter. Routes a high-blast-radius artifact (plan or PR)
  through multiple heterogeneous review passes and gates on consensus. Does
  not review; dispatches existing review skills (/simplify, /review,
  /review-senior, /safer:dogfood, /codex, /security-review for PRs;
  /safer:dogfood + /safer:review-senior + /codex for plans) and aggregates
  their verdicts. N is set by the blast-radius x reversibility table in
  PRINCIPLES.md > Durability. Two invocation modes: --plan <sub-issue-URL>
  and --pr <pr-URL>. Use when the caller (typically /safer:orchestrate Phase
  5c) has decided the artifact warrants stamina. Do NOT self-invoke from the
  working modality; that is Principle 5 self-polishing.
triggers:
  - stamina review this PR
  - fan out reviewers
  - multi-persona review
  - run N review passes
  - gate on consensus
  - heterogeneous review
allowed-tools:
  - Bash
  - Read
  - Agent
---

# /safer:stamina

## Read first

Read `PRINCIPLES.md` at the plugin root before continuing. Your projection of the principles onto this modality:

- **Artifact discipline > Durability** — this skill is the enforcement mechanism for the Durability clause. The budget table lives there; this skill reads it, it does not override it.
- **Principle 5 (Junior Dev Rule)** — stamina routes; it does not review. Every verdict comes from a dispatched reviewer. If you find yourself forming an opinion on the artifact, the stop rule has already fired.
- **Principle 6 (Budget Gate)** — stamina's budget is N (count of passes) and the fixed review family. Inventing a new reviewer, reading the diff yourself, or running tests are all budget violations.
- **Principle 8 (Ratchet)** — any BLOCK verdict routes upstream (to the modality that authored the artifact), never sideways via a stamina-authored patch.
- **Artifact discipline > GitHub is the record** — the consolidated verdict is published to the target issue/PR; per-reviewer reports link to the reviewer's native artifact (`gh pr review`, issue comment).

## Iron rule

> **Stamina routes; it does not review.**

The failure pattern this rule prevents: the stamina agent, after the dispatched reviewers finish, "weighs in" with its own reading of the diff — a summary, a tiebreaker, a clarifying gloss. Any reading not attributed to a dispatched reviewer is a violation. If stamina needs a verdict that does not come from a reviewer in the fixed family, the family is incomplete — ratchet to spec, do not synthesize one inline. The consolidated comment is a routing table, not a review.

## Role

Stamina is a fan-out adapter above the review family. Inputs: one artifact URL (`--plan` or `--pr`) and an inferred or user-supplied N. Output: one consolidated verdict comment on the artifact, zero or one label transition, and telemetry events. The body of the critique is done by dispatched reviewers; stamina classifies, dispatches, collects from GitHub, aggregates under the consensus rule, and publishes.

## Inputs required

- Exactly one of `--plan <sub-issue-URL>` or `--pr <pr-URL>`.
- `gh` CLI authenticated (`gh auth status`).
- Blast-radius signal — resolved automatically:
  - PR mode: `safer-diff-scope --pr <N>` output.
  - Plan mode: sub-issue's `safer:<modality>` label.
- Optional `--budget <N>` user override; `1 ≤ N ≤ 4`. `N > 4` requires `safer-escalate --cause USER_BUDGET_OVERRIDE`; stamina does not grant it inline.

### Preamble (run first)

```bash
gh auth status >/dev/null 2>&1 || { echo "ERROR: gh not authenticated. Run: gh auth login"; exit 1; }
eval "$(safer-slug 2>/dev/null)" || true
SESSION="$$-$(date +%s)"
_TEL_START=$(date +%s)
safer-telemetry-log --event-type safer.skill_run --modality stamina --session "$SESSION" 2>/dev/null || true
_UPD=$(safer-update-check 2>/dev/null || true)
[ -n "$_UPD" ] && echo "$_UPD"
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || echo "unknown/unknown")
echo "REPO: $REPO  MODE: ${MODE:?set MODE=plan|pr}  TARGET: ${TARGET:?set TARGET=<url>}  SESSION: $SESSION"
```

Emit `safer.stamina_gate` at start, carrying chosen `N`, `n_source` (`table` | `user-override`), `mode` (`plan` | `pr`), and the target URL. Emit it again at close-out with the outcome (Phase 6).

## Scope

### In scope

- Classifying the artifact via `safer-diff-scope` (PR mode) or the sub-issue modality label (plan mode) to select N and the dispatch set.
- Enforcing persona diversity at dispatch: the dispatch set has as many distinct roles as the chosen N.
- Dispatching each selected reviewer via the `Agent` tool with a self-contained prompt (artifact URL + acceptance criteria + request to publish its native verdict).
- Collecting each reviewer's published verdict from GitHub — never from the `Agent` return string.
- Aggregating verdicts under the consensus rule in Phase 4.
- Publishing one consolidated comment on the target issue/PR.
- Transitioning exactly one label on the sub-issue (plan mode only). PR-mode label transitions are owned by `/safer:verify`.
- Escalating via `safer-escalate` on any BLOCK.
- Emitting `safer.stamina_gate` (per invocation) and `safer.stamina_pass` (per reviewer).

### Forbidden

- Reading the diff or plan body to form a first-party opinion.
- Editing source files, the plan, or any reviewer's output.
- Running the test suite (that is `verify`'s budget).
- Dispatching a reviewer outside the fixed review family.
- Running two instances of the same reviewer skill on the same model and counting them as two passes.
- Proceeding to `DONE` on partial approve when any reviewer returned BLOCK.
- Self-invoking from the authoring modality.

## Scope budget

1. **One consolidated comment per invocation.** Not one per reviewer — dispatched reviewers publish their own native artifacts.
2. **N is bounded.** Floor `N=1`, ceiling `N=4` table-default; `N>4` requires `safer-escalate --cause USER_BUDGET_OVERRIDE` recorded at dispatch.
3. **Review family (PR mode):** `/simplify`, `/review`, `/review-senior`, `/safer:dogfood`, `/codex`, `/security-review`. Fixed list for v1; no additions.
4. **Review family (plan mode):** `/safer:dogfood`, `/safer:review-senior` (re-targeted at the plan body), `/codex` (cross-model). `/autoplan` is omitted in v1 per architect open-question default.
5. **Graceful degradation.** If gstack is absent, the PR dispatch set drops to `{/safer:review-senior, /safer:dogfood}` (plus `/codex` if configured); ceiling caps at `N=3`. If the table calls for `N=4` under degraded deps, emit `NEEDS_CONTEXT` naming the missing dep. Never hard-fail on a missing optional dep; declare the gap explicitly in the consolidated comment.
6. **Persona diversity.** Every pass differs by *role* (acceptance-vs-diff, structural-diff, adversarial, security, simplification, cold-start-read) or by *model* (`/codex` is the cross-model channel). Two passes with the same role on the same model do not count as two passes. Dispatch refuses to launch a homogeneous pair.

## Workflow

### Phase 1 — Classify

Compute N and the dispatch set.

**PR mode.** Run `safer-diff-scope --pr "$PR"` and read `tier`, `exports`, `modules`, `new_deps`. Map to the Durability row:

| `safer-diff-scope` signal | Durability row | N |
|---|---|---|
| `tier=junior`, `exports=0`, `modules<=1`, `new_deps=0` | Internal only, high-rev | 1 |
| `tier=junior`, `modules>=2`, `exports=0` | Internal cross-module | 2 |
| `tier=senior`, `exports=0` | Internal cross-module, med-rev | 2 |
| `tier=senior`, `exports>0` | Public surface | 3 |
| `tier=staff` | Public surface / user-visible | 3 |
| `tier=staff`, `new_deps>0` OR diff matches `migrations/`, `migrate/`, `db/migrations/`, `DROP TABLE`, `ALTER COLUMN.*NOT NULL`, `DELETE FROM` | Destructive | 4 |

**Plan mode.** Read the sub-issue's `safer:<modality>` label and map:

| Sub-issue label | N |
|---|---|
| `safer:implement-junior` | 1 |
| `safer:implement-senior`, `safer:investigate`, `safer:spike`, `safer:research` | 2 |
| `safer:spec`, `safer:architect`, `safer:design-module` | 3 |
| `safer:implement-staff` | 3 (plan phase; PR-phase mapping applies at verify) |

If `--budget <N>` was passed, override. Record `n_source=user-override` and the delta (`table_n=<auto>`, `n=<user>`) in telemetry.

From N and mode, choose the dispatch set. Every entry in the set is a distinct role. Example PR-mode selections:

- `N=1` — `{/safer:review-senior}`.
- `N=2` — `{/safer:review-senior, /safer:dogfood}`.
- `N=3` — `{/safer:review-senior, /safer:dogfood, /codex}`; if gstack present, swap `/codex` for `/review` or add a fourth role only if N=4.
- `N=4` — `{/safer:review-senior, /safer:dogfood, /codex, /security-review}` OR include `/simplify` / `/review` when the diff shape rewards them (schema work → `/security-review`; large internal refactor → `/simplify`).

Plan-mode selections cap at `{/safer:dogfood, /safer:review-senior, /codex}`.

Record to telemetry: `safer.stamina_gate` with `mode`, `n`, `n_source`, `dispatch_set`.

### Phase 2 — Dispatch

Fan out each reviewer via the `Agent` tool. Each dispatch is a self-contained prompt; no session history leaks between dispatches. The prompt template:

```
You are invoking /<reviewer-skill> as a reviewer in a /safer:stamina fan-out.

Target artifact: <PR_URL or sub-issue_URL>
Acceptance criteria: <paste from sub-issue body>
Role: <acceptance-vs-diff | structural-diff | adversarial | security | simplification | cold-start-read>

Read PRINCIPLES.md at the plugin root before reviewing.

Publish your verdict as the reviewer's native artifact (PR review via
`gh pr review`, sub-issue comment, etc.). Your final output MUST end with
exactly one of: DONE, DONE_WITH_CONCERNS, ESCALATED, BLOCKED, NEEDS_CONTEXT.

Reply with the URL of the verdict you published. Do not paste the verdict body.
```

Dispatch discipline:

- Launch all reviewers in parallel (one `Agent` call per reviewer, in a single batch).
- Before launching, reject any dispatch set whose roles are not pairwise distinct. Homogeneous dispatch is the independence-rule violation the stop rule guards against.
- Emit `safer.stamina_pass` at dispatch with `reviewer`, `role`, `target`.
- If a reviewer's `Agent` call fails to return a URL, hold it for Phase 3 collection — the reviewer may have published before crashing.

### Phase 3 — Collect

For each dispatched reviewer, read the published verdict from GitHub — never from the `Agent` return string. A return string is the reviewer's self-report; the canonical artifact is the GitHub comment / review.

- PR mode: `gh pr view "$PR" --json reviews,comments` and filter by the reviewer's login or comment marker.
- Plan mode: `gh issue view "$N" --json comments` and match by role marker or comment author.

Parse the safer status marker on the last line of each verdict body. If a reviewer did not publish within the invocation window, stop rule 5 fires — `BLOCKED` with the reviewer name.

### Phase 4 — Aggregate under the consensus rule

Apply the consensus rule deterministically. Stamina never synthesizes a verdict; every outcome below is a function of the collected markers.

| Collected verdicts | Outcome |
|---|---|
| All markers in `{DONE}` | `DONE` |
| All markers in `{DONE, DONE_WITH_CONCERNS}`, at least one `DONE_WITH_CONCERNS` | `DONE_WITH_CONCERNS` (attribute each concern to its source) |
| Any `ESCALATED` or `BLOCKED` (reviewer blocked, not stamina) | `ESCALATED` — call `safer-escalate --from stamina --to <authoring-modality> --cause REVIEWER_BLOCK` |
| Any `--request-changes` on a `gh pr review` | `ESCALATED` (treat as BLOCK) |
| Any `NEEDS_CONTEXT` | `NEEDS_CONTEXT` (surface the question to the user) |
| Partial approve at `N=ceiling` with unresolved disagreement | `NEEDS_CONTEXT` (user arbitrates) |
| Reviewer dispatch failed, no verdict recorded | `BLOCKED` (stamina's own channel) |

If the function above is undefined on the observed inputs, stop rule 6 fires; emit `NEEDS_CONTEXT`. Stamina does not guess.

### Phase 5 — Publish

Produce one consolidated comment on the target. The body is a routing table, not a critique.

```markdown
# /safer:stamina — consolidated verdict

**Mode:** <plan | pr>
**Target:** <URL>
**N:** <n> (source: <table | user-override>, blast row: <Durability row>)
**Dispatch set:** <role → reviewer mapping>

## Per-reviewer

| Role | Reviewer | Verdict | Artifact |
|---|---|---|---|
| acceptance-vs-diff | /safer:review-senior | DONE | <URL to native verdict> |
| cold-start-read | /safer:dogfood | DONE_WITH_CONCERNS | <URL> |
| adversarial (cross-model) | /codex | DONE | <URL> |
| ... | | | |

## Consensus

<DONE | DONE_WITH_CONCERNS | ESCALATED | BLOCKED | NEEDS_CONTEXT>

## Concerns (if DONE_WITH_CONCERNS)

- <concern, one line, attributed to source reviewer via artifact URL>

## Next route

<one line naming the next modality / state transition / user question>

---
_Consolidated by /safer:stamina. Per-reviewer findings live with the reviewer._
```

Publish via `safer-publish`:

- PR mode: `safer-publish --kind pr-comment --pr "$PR" --body-file /tmp/stamina-verdict.md`.
- Plan mode: `safer-publish --kind issue-comment --issue "$N" --body-file /tmp/stamina-verdict.md`.

Label transitions:

- Plan mode, consensus `DONE` or `DONE_WITH_CONCERNS`: `safer-transition-label --issue "$N" --from review --to plan-approved`.
- Plan mode, consensus `ESCALATED`: `safer-transition-label --issue "$N" --from review --to planning`.
- PR mode: **no label transition**. `/safer:verify` owns that.

### Phase 6 — Close out

Emit telemetry and hand control back to the caller.

```bash
safer-telemetry-log --event-type safer.stamina_gate --modality stamina --session "$SESSION" \
  --outcome "<DONE|DONE_WITH_CONCERNS|ESCALATED|BLOCKED|NEEDS_CONTEXT>" \
  --n "$N" --n-source "$N_SOURCE" --mode "$MODE" 2>/dev/null || true

# One event per reviewer, already emitted at dispatch; emit a second one per reviewer at close-out carrying verdict.
for reviewer in $DISPATCH_SET; do
  safer-telemetry-log --event-type safer.stamina_pass --modality stamina --session "$SESSION" \
    --reviewer "$reviewer" --role "$ROLE" --verdict "$VERDICT" 2>/dev/null || true
done

safer-telemetry-log --event-type safer.skill_end --modality stamina --session "$SESSION" \
  --outcome success --duration-s "$(($(date +%s) - _TEL_START))" 2>/dev/null || true
```

Report status on the final line of your reply.

## Stop rules

Each fires on a specific condition. Each halts further dispatch and produces the matching status.

1. **Reader, not writer.** You start forming a first-party opinion on the artifact. Iron rule violated — dispatch or escalate; do not summarize a reading you did yourself.
2. **Homogeneous dispatch.** The selected dispatch set has fewer distinct roles than N at `N≥2`. Independence-rule violation — escalate to user (`NEEDS_CONTEXT`) naming which roles are missing.
3. **Missing artifact.** Target PR / sub-issue URL is unresolvable. → `NEEDS_CONTEXT`.
4. **No acceptance criteria.** Sub-issue body has no acceptance checklist. → `NEEDS_CONTEXT` to the orchestrator.
5. **Reviewer dispatch failed.** Any dispatched reviewer did not publish within the invocation budget. → `BLOCKED` naming the reviewer and last-known state.
6. **Undefined consensus.** The Phase 4 function is undefined on observed inputs. → `NEEDS_CONTEXT`; do not synthesize a verdict.
7. **Partial approve at ceiling.** `N=ceiling`, verdicts split, no movement available. → `NEEDS_CONTEXT` with the disagreement summary.
8. **Budget override above 4.** User requested `--budget >4` without a `safer-escalate` artifact. → `NEEDS_CONTEXT`.

## Completion status

Every invocation ends with exactly one marker on the final line of the reply:

- **`DONE`** — unanimous approve across the dispatch set; consolidated comment published; label transitioned (plan mode) or deliberately skipped (PR mode).
- **`DONE_WITH_CONCERNS`** — approve with reviewer-attributed concerns; each concern links to its source verdict.
- **`ESCALATED`** — any BLOCK / `--request-changes` / `ESCALATED` from a reviewer; routed upstream via `safer-escalate`.
- **`BLOCKED`** — reviewer dispatch failed or external dep unresolved; name the reviewer and the last-known state.
- **`NEEDS_CONTEXT`** — partial approve at ceiling, missing inputs, undefined consensus, or user-budget override without authorization; state the question.

## Publication map

| Artifact | Destination |
|---|---|
| Per-reviewer verdict | Native to the reviewer (`gh pr review`, sub-issue comment, etc.) — stamina does not own it |
| Consolidated stamina verdict | One comment on the target PR or sub-issue via `safer-publish` |
| Label transition (plan mode) | `safer-transition-label` on the sub-issue (`review → plan-approved` on approve; `review → planning` on escalate) |
| Label transition (PR mode) | Deferred to `/safer:verify` — stamina does not touch PR labels |
| Escalation | `safer-escalate --from stamina --to <authoring-modality> --cause REVIEWER_BLOCK`, cross-linked on the target |
| Telemetry | `safer.stamina_gate` (per invocation), `safer.stamina_pass` (per reviewer at dispatch and close-out), `safer.skill_run` / `safer.skill_end` |

Nothing stamina produces lives outside GitHub.

## Anti-patterns

- **"I'll read the diff myself and confirm the reviewers are right."** Iron rule violation. Stamina routes; it does not review.
- **"I'll run `/safer:review-senior` three times with different prompts to hit N=3."** Independence-rule violation. Three passes of the same skill on the same model is N=1.
- **"Two reviewers approved, one hasn't replied; I'll ship."** Incomplete dispatch is not consensus. `BLOCKED` until the last reviewer publishes or the invocation budget is exhausted.
- **"One reviewer blocked on a nit; I'll downgrade their verdict to a concern."** Stamina does not grade reviewers. Any BLOCK routes upstream.
- **"gstack isn't present, so stamina is a no-op."** Graceful degradation: cap at N=3 using pure-safer plus `/codex` if configured. Declare the missing dep in the consolidated comment; do not skip the gate.
- **"I'll invoke stamina on my own output before handing back."** Principle 5 violation. Stamina is orchestrator-driven, not self-invoked.
- **"The migration PR is urgent; I'll run stamina at N=2 to save time."** The urgency is the reason for N=4 (Durability row 5), not against it. Ratchet to user if N cannot be satisfied under current deps.
- **"The consensus rule is ambiguous; I'll pick the outcome that looks right."** Undefined consensus fires `NEEDS_CONTEXT`. Stamina does not guess.

## Checklist before declaring `DONE`

- [ ] Mode resolved (`--plan` or `--pr`) and target URL loaded.
- [ ] Blast radius computed; `N` and `n_source` recorded in telemetry.
- [ ] Dispatch set selected from the fixed review family; persona diversity ≥ N distinct roles.
- [ ] Every reviewer in the set published its native verdict to GitHub.
- [ ] Consensus computed from GitHub-read verdicts (not `Agent` return strings).
- [ ] Consolidated comment posted on the target via `safer-publish`.
- [ ] Label transition applied (plan mode) or deliberately skipped (PR mode).
- [ ] `safer.stamina_gate` end event emitted; one `safer.stamina_pass` per reviewer at dispatch and at close-out.
- [ ] Status marker on last line of reply.

If any box is unchecked, the status is not `DONE`.

## Voice (reminder)

See `PRINCIPLES.md > Voice`. Stamina's output is terse and structural. The consolidated comment is a routing table, not an essay. Per-reviewer findings live with the reviewer; stamina reports who ran, what role they carried, what they said, and the consensus outcome. If your output reads like a review, you are in the wrong modality.
