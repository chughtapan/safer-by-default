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

TODO: spec-owned. Name the projection of PRINCIPLES.md onto this modality. At minimum:

- **Artifact discipline > Durability** — this skill is the enforcement mechanism for the Durability clause. The budget table lives there; this skill reads it.
- **Principle 5 (Junior Dev Rule)** — stamina routes; it does not review. Every verdict comes from a dispatched reviewer.
- **Principle 8 (Ratchet)** — any BLOCK verdict routes upstream (to the modality that authored the artifact), never sideways via a stamina-authored patch.
- **Artifact discipline > GitHub is the record** — the consolidated verdict is published to the target issue/PR; per-reviewer reports link to the reviewer's native artifact (`gh pr review`, issue comment).

Implementer: copy shape from `skills/review-senior/SKILL.md` and `skills/dogfood/SKILL.md`; stamina is a sibling, not a superset.

## Iron rule

> **Stamina routes; it does not review.**

TODO: architect-owned — expand in one paragraph. The pattern to prevent: stamina agent "weighing in" with its own reading of the diff after the dispatched reviewers finish. Any reading that is not attributed to a dispatched reviewer is a violation. If stamina needs a verdict that does not come from an existing review skill, the review family is incomplete — ratchet to spec, do not synthesize one inline.

## Role

TODO: spec-owned. One paragraph. Stamina is a fan-out adapter above the review family. Inputs: an artifact URL and a budget N. Output: one consolidated verdict comment on the artifact + one label transition. The body of the work is done by dispatched reviewers; stamina classifies, dispatches, aggregates, publishes.

## Inputs required

TODO: spec-owned. Must name:

- `--plan <sub-issue-URL>` or `--pr <pr-URL>` (exactly one).
- `gh` CLI authenticated.
- Blast-radius signal: `safer-diff-scope --pr <N>` output for `--pr` mode; sub-issue's `safer:<modality>` label for `--plan` mode.
- Optional: `--budget <N>` to override the auto-inferred N. User-raised N is recorded in telemetry.

### Preamble (run first)

TODO: architect-owned. Same shape as `skills/review-senior/SKILL.md` preamble — `gh auth status`, `safer-slug`, `safer-telemetry-log` (event `safer.skill_run`, modality `stamina`), `safer-update-check`. Emit `safer.stamina_gate` at start with chosen N and N-source (`table` vs `user-override`). Record the invocation mode (`plan` | `pr`).

## Scope

**In scope (TODO: spec-owned expand):**
- Classifying the artifact via `safer-diff-scope` (PR mode) or sub-issue modality label (plan mode) to select N.
- Selecting the dispatch set from the fixed review family for the chosen mode.
- Dispatching each selected reviewer via the `Agent` tool with a self-contained prompt (artifact URL + acceptance criteria + request to publish a verdict comment).
- Collecting each reviewer's published verdict from GitHub (not from agent return values).
- Aggregating verdicts under the consensus rule.
- Publishing one consolidated comment on the target issue/PR.
- Transitioning exactly one label on the target sub-issue (plans) or leaving the PR label alone (PRs — `/safer:verify` runs next).

**Forbidden (TODO: spec-owned expand):**
- Reading the diff or the plan body to form a first-party opinion.
- Editing source files, the plan, or any reviewer's output.
- Running the test suite (that is `verify`'s budget).
- Dispatching a reviewer outside the fixed review family.
- Running two instances of the same reviewer skill and counting them as two passes (independence rule).
- Proceeding on partial approve when any reviewer returned BLOCK.

## Scope budget

TODO: architect-owned. Key constraints:

1. One consolidated comment per invocation. Not one per reviewer — the dispatched reviewers publish their own native artifacts.
2. N is bounded: floor N=1, ceiling N=4 table-default, N>4 requires explicit user approval (captured in the `--budget` flag or `safer-escalate`).
3. Review family (PR mode): `/simplify`, `/review`, `/review-senior`, `/safer:dogfood`, `/codex`, `/security-review`. Fixed list; no additions in v1.
4. Review family (plan mode): `/safer:dogfood`, `/safer:review-senior` (re-targeted at the plan body), `/codex` (cross-model). Optionally `/autoplan` if non-interactive mode is available; otherwise skip.
5. Graceful degradation: if gstack is absent, the dispatch set is capped at `{/safer:review-senior, /safer:dogfood}` plus `/codex` if configured; the ceiling caps at N=3. The skill never hard-fails on a missing optional dep.
6. Persona diversity: every pass differs by *role* (acceptance-vs-diff, structural-diff, adversarial, security, simplification, cold-start-read) or by *model* (`/codex` is the cross-model channel). Two passes with the same role on the same model do not count as two passes.

## Workflow

TODO: architect-owned. Phase names only; bodies are implementer work.

### Phase 1 — Classify

TODO: architect-owned. Compute blast radius; select N; select the dispatch set; record both in telemetry.

### Phase 2 — Dispatch

TODO: architect-owned. Fan out over the dispatch set via `Agent` calls. Each reviewer agent is prompted with a self-contained context payload (artifact URL, acceptance criteria, request: publish your verdict to the artifact's thread and reply with the URL of the published comment). No session history leakage.

### Phase 3 — Collect

TODO: architect-owned. Read each reviewer's published verdict from GitHub (not from the agent return string). Parse status marker per the safer status vocabulary.

### Phase 4 — Aggregate under the consensus rule

TODO: architect-owned. Unanimous approve → proceed. Any BLOCK / `ESCALATED` / `--request-changes` → route upstream via `safer-escalate` to the artifact's authoring modality. Partial approve at N=ceiling with unresolved disagreement → `NEEDS_CONTEXT` to user.

### Phase 5 — Publish

TODO: architect-owned. One consolidated comment on the target issue/PR summarizing per-reviewer verdicts + consensus outcome + next route. Transition the sub-issue label (plan mode) or leave it for `/safer:verify` (PR mode).

### Phase 6 — Close out

TODO: architect-owned. Emit `safer.stamina_gate` end event (outcome, N, dispatch set, consensus result). Emit `safer.stamina_pass` per dispatched reviewer (role, verdict, artifact URL). `safer.skill_end`.

## Stop rules

TODO: architect-owned. At minimum:

1. **Reader, not writer.** If you start forming a first-party opinion on the artifact, iron rule fired. Dispatch or escalate; do not summarize a reading you did yourself.
2. **Homogeneous dispatch.** If the selected dispatch set is less than 2 roles at N≥2, the persona-diversity rule fired — escalate to user.
3. **Missing artifact.** Target PR or sub-issue URL is unresolvable → `NEEDS_CONTEXT`.
4. **No acceptance criteria.** Sub-issue has no acceptance checklist → `NEEDS_CONTEXT` to orchestrator.
5. **Reviewer dispatch failed.** Any dispatched reviewer did not publish within the invocation budget → `BLOCKED` with the reviewer name and last-known state.
6. **Partial approve at ceiling.** N=ceiling, verdicts split, no movement available → `NEEDS_CONTEXT` with the disagreement summary; user arbitrates.
7. **Budget override above 4.** User asked for N>4 without explicit approval artifact → `NEEDS_CONTEXT`.

## Completion status

TODO: spec-owned. Standard safer status vocabulary. Note:
- `DONE` — unanimous approve across the dispatch set; consolidated comment published; label transitioned.
- `DONE_WITH_CONCERNS` — approve with reviewer-named concerns; each concern attributed to its source reviewer.
- `ESCALATED` — any BLOCK fired; routed upstream via Ratchet.
- `BLOCKED` — reviewer dispatch failed or external dep unresolved.
- `NEEDS_CONTEXT` — partial approve at ceiling, or missing inputs.

## Publication map

TODO: architect-owned. Table:

| Artifact | Destination |
|---|---|
| Per-reviewer verdict | Native to the reviewer (`gh pr review`, sub-issue comment, etc.) — stamina does not own it |
| Consolidated stamina verdict | One comment on the target PR or sub-issue |
| Label transition | `safer-transition-label` on the target sub-issue (plan mode only) |
| Escalation | `safer-escalate` to the authoring modality; cross-linked on the target |
| Telemetry | `safer.stamina_gate` (per invocation), `safer.stamina_pass` (per reviewer), `safer.skill_run` / `safer.skill_end` |

Nothing stamina produces lives outside GitHub.

## Anti-patterns

TODO: architect-owned. At minimum:

- "I'll read the diff myself and confirm the reviewers are right." — Iron rule violation. Stamina routes; it does not review.
- "I'll run `/safer:review-senior` three times with different prompts to hit N=3." — Independence rule violation. Three passes of the same skill on the same model is N=1, not N=3.
- "Two reviewers approved, one hasn't replied; I'll ship." — Incomplete dispatch is not consensus. BLOCKED until the last reviewer publishes or times out.
- "One reviewer blocked on a nit; I'll downgrade their verdict to a concern." — Stamina does not grade reviewers. Any BLOCK routes upstream.
- "gstack isn't present, so stamina is a no-op." — Graceful degradation: cap at N=3 using pure-safer + `/codex` if configured. Do not skip.
- "I'll invoke stamina on my own output before handing back." — Principle 5 violation. Stamina is orchestrator-driven, not self-invoked.

## Checklist before declaring DONE

TODO: architect-owned. At minimum:

- [ ] Mode resolved (`--plan` or `--pr`) and target URL loaded.
- [ ] Blast radius computed; N and N-source recorded in telemetry.
- [ ] Dispatch set selected from the fixed review family; persona diversity ≥ N roles.
- [ ] Every reviewer in the set published its native verdict to GitHub.
- [ ] Consensus computed from GitHub-read verdicts (not agent return strings).
- [ ] Consolidated comment posted on the target.
- [ ] Label transition applied (plan mode) or deliberately skipped (PR mode).
- [ ] `safer.stamina_gate` end event emitted; one `safer.stamina_pass` per reviewer.
- [ ] Status marker on last line of reply.

## Voice (reminder)

See `PRINCIPLES.md > Voice`. Stamina's output is terse and structural. The consolidated comment is a routing table, not an essay. Per-reviewer findings live with the reviewer; stamina reports who ran, what they said, and the consensus outcome.

TODO: implementer — stamina's voice is the voice of the dispatcher, not the critic. If your output reads like a review, you are in the wrong modality.
