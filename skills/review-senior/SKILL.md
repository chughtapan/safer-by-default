---
name: review-senior
version: 0.2.0
description: |
  Dispatcher for pre-merge artifact review. Routes a PR, design doc, spec,
  plan, UI-touching change, or LLM-prompt change to the correct composed
  gstack skill set per the SPEC r4.1 §5(h) routing table. Does NOT itself
  read diffs or write reviews; the composed gstack skills do that. Single
  review skill per Invariant 11; adding a second is a SPEC-revision trigger.
triggers:
  - review this
  - senior review
  - dispatch review
  - route for review
  - pre-merge review
  - review senior
  - safer review
allowed-tools:
  - Bash
  - Read
  - Grep
  - Glob
---

# /safer:review-senior

## Read first

Read `PRINCIPLES.md` at the plugin root. Single-skill rule (Invariant 11):
this is the ONLY safer review skill. Adding a second is a SPEC-revision
trigger.

## Role

**Dispatch, don't review.** Route the artifact to the correct composed
gstack skill set. No code-level dispatcher exists in safer-by-default; the
routing table below IS the dispatcher, interpreted by the orchestrator
prompt (zapbot `src/orchestrator/control-event.ts`) and by a human reader.

Out-of-band gstack invocations (calling `/review`, `/simplify`, `/codex`,
`/plan-eng-review`, `/plan-design-review` directly instead of through
this dispatcher) are forbidden by Acceptance (e) bullet 4: the convergence
gate the orchestrator reads is this skill's verdict, not the individual
gstack verdicts.

## Routing table (SPEC r4.1 §5(h))

| Artifact kind | Composed gstack skills |
|---|---|
| PR diff | `/review` + `/simplify` + `/codex` |
| Plan / spec / design doc | `/plan-eng-review` + `/codex` |
| UI-touching change (PR or design doc) | add `/plan-design-review` |
| LLM prompt change | add the repo's eval suites per `CLAUDE.md` |

Dispatch by **artifact kind**, not by **modality**. A design doc produced
by `/safer:architect` routes under row 2 regardless of which modality
authored it. A PR that happens to include UI copy routes under rows 1 + 3.
A PR that introduces a new LLM prompt routes under rows 1 + 4.

The routing table is additive. A UI-touching PR runs rows 1 and 3; a
spec that describes an LLM prompt runs rows 2 and 4.

## Forbidden verdicts

The aggregate verdict this dispatcher publishes MUST NOT mis-report. Even
when the composed gstack skills are not directly under this skill's
control, the dispatcher owns the aggregate tag.

Forbidden aggregate-verdict patterns:

- Returning APPROVE with a deferred measurement condition the reviewer cannot confirm.
- Returning APPROVE citing the author's claim of a metric ("author reports
  ≥80% mutation"); a claim is not a measurement. If a composed skill
  returned HOLD pending measurement, the aggregate is HOLD, never APPROVE.
- Returning APPROVE when any composed gstack skill was unavailable and
  the row's coverage is therefore incomplete; use DONE_WITH_CONCERNS
  instead (see Unavailability rule below).

### HOLD vs REQUEST-CHANGES

Two failure modes at aggregation, two verdicts, two consumer actions.

- **HOLD** the diff is *correct but unmeasured*. A composed gstack skill
  returned HOLD because an acceptance criterion names a measured threshold
  the reviewer cannot confirm from the diff alone.
  - Consumer action: dispatch `/safer:verify`.
  - Label transition: `review` → `verifying`.
- **REQUEST-CHANGES** the diff is *broken or wrong*. A composed skill
  found a craft violation, scope mismatch, missing implementation, gutted
  tests, or a non-measurement criterion unmet.
  - Consumer action: dispatch `/safer:implement-*`.
  - Label transition: `review` → `implementing`.

HOLD is not a soft REQUEST-CHANGES. REQUEST-CHANGES is not a harsh HOLD.
Pick the aggregate verdict that matches the failure mode.

## Unavailability rule (loud)

When a composed gstack skill is missing from the operating environment,
emit `DONE_WITH_CONCERNS` with:

- the missing skill name,
- the reason logged back on the artifact thread.

**Silent skip is FORBIDDEN.** The orchestrator's convergence gate
(Acceptance (e)) reads the verdict produced here; a silent skip would
invalidate that gate. A missing gstack skill in the environment is a
configuration problem that must be surfaced, not a reason to approve.

## Input contract

```
--artifact <url>   GitHub issue-comment URL, sub-issue body URL, or PR URL
--kind <pr|design|spec|plan|ui|prompt>   (optional; inferred if omitted)
```

`--kind` inference rules (when the flag is omitted):

- URL matches `/pull/\d+` → `pr` (rows 1; add 3 if the PR touches
  `{css,scss,tsx,jsx,html,svg}` or `design/**`; add 4 if it touches
  `skills/**/SKILL.md`, `prompts/**`, `eval/**`, or an LLM-prompt file).
- URL matches `/issues/\d+#issuecomment-` → read the comment's `safer:*`
  label on the parent issue. `safer:spec` → `spec`; `safer:architect` →
  `design`; anything else → `plan`.
- URL matches `/issues/\d+` → `plan`.

## Workflow

### Phase 1 — Load the artifact and classify

```bash
gh auth status >/dev/null 2>&1 || { echo "ERROR: gh not authenticated"; exit 1; }
eval "$(safer-slug 2>/dev/null)" || true
SESSION="$$-$(date +%s)"
safer-telemetry-log --event-type safer.skill_run --modality review-senior \
  --session "$SESSION" 2>/dev/null || true

ARTIFACT="${ARTIFACT:?set ARTIFACT=<url>}"
KIND_OVERRIDE="${KIND:-}"
```

Classify the artifact per the inference rules above (or honour
`KIND_OVERRIDE`). Record the classification plus the composed gstack
skill set in a comment on the artifact thread; that comment is the
audit trail even if the dispatch itself fails.

### Phase 2 — Dispatch the composed skills

Invoke each composed gstack skill in order. Each produces its own verdict
(APPROVE / REQUEST-CHANGES / HOLD / COMMENT). Collect them.

For PR rows, the composed skills post their verdicts as inline comments
or PR reviews; for design/plan/spec rows, the composed skills post
threaded comments on the artifact URL.

If the environment lacks a composed skill (gstack not installed, or the
plugin is a different version), emit `DONE_WITH_CONCERNS` with the
missing skill name and STOP further dispatch for that row. Do NOT
attempt to "do the work" of the missing skill here — that collapses
the separation between `review-senior` (dispatcher) and the gstack
reviewers (reviewers).

### Phase 3 — Aggregate the verdict

Combine per-skill verdicts into one artifact verdict. Rules:

- Any `REQUEST-CHANGES` among composed skills → artifact verdict
  `REQUEST-CHANGES`.
- Any `HOLD` (correct-but-unmeasured) from a composed skill → artifact
  verdict `HOLD`.
- Any `DONE_WITH_CONCERNS` from missing-skill unavailability → artifact
  verdict `DONE_WITH_CONCERNS` (the missing skill is a real concern).
- All `APPROVE` with none of the above → artifact verdict `APPROVE`.

Publish the aggregate via `gh pr review` (for PR rows) or
`safer-publish --kind comment --issue "$ISSUE" --body-file <file>`
(for design/plan/spec rows).

### Phase 4 — Transition the sub-issue label

When operating under `/safer:orchestrate`:

- `APPROVE`: `safer-transition-label --from review --to verifying`
- `HOLD`: `safer-transition-label --from review --to verifying` (verify
  next, measurement pending).
- `REQUEST-CHANGES`: `safer-transition-label --from review --to
  implementing`.
- `DONE_WITH_CONCERNS` with missing gstack skill: stay at `review`;
  team-lead resolves the environment issue.

## Stop rules

1. **Artifact kind cannot be inferred.** The URL is neither a PR, an
   issue, nor an issue-comment. → `NEEDS_CONTEXT` with the URL and the
   list of valid shapes.
2. **All composed gstack skills are missing.** The operating environment
   has no reviewer skills at all. → `BLOCKED`. The team-lead must install
   gstack or the plugin must be reconfigured.
3. **A composed skill returns a malformed verdict.** (Not APPROVE /
   REQUEST-CHANGES / HOLD / COMMENT / DONE_WITH_CONCERNS.) → `ESCALATED`
   with the raw verdict. Do not coerce.
4. **The artifact URL returns 404 or requires auth we do not have.** →
   `BLOCKED` with the HTTP status. Do not review what we cannot read.

## Completion status

Every invocation ends with exactly one status marker on the last line:

- `DONE` — dispatch complete; aggregate verdict published.
- `HOLD` review posted with `## Verdict\nHOLD` body; the aggregate verdict
  is HOLD (a composed skill returned HOLD); label transitioned to
  `verifying`; consumer route is `/safer:verify`. HOLD is a valid
  terminal output for review-senior.
- `DONE_WITH_CONCERNS` — dispatch complete, with either (a) the
  aggregate verdict itself being DONE_WITH_CONCERNS, or (b) one or more
  composed gstack skills unavailable.
- `ESCALATED` — stop rule 3 fired.
- `BLOCKED` — stop rule 2 or 4 fired.
- `NEEDS_CONTEXT` — stop rule 1 fired.

## Anti-patterns

- **"I'll read the diff myself and write the review."** No. The review
  is performed by the composed gstack skills; `review-senior` dispatches.
  The architect design explicitly rules out a code-level dispatcher in
  safer-by-default (Invariant 11); the rulebook *is* the dispatcher.
- **"`/simplify` isn't installed, so I'll just approve on the other two."**
  No. Silent skip is forbidden. Emit DONE_WITH_CONCERNS so the
  orchestrator can see that convergence is unmeasured.
- **"I'll rewrite the routing table to cover a new case I just noticed."**
  No. The routing table lives in SPEC r4.1 §5(h). Route to `/safer:spec`
  if a new case is needed (Principle 8, Ratchet).
- **"This PR is small; I'll skip `/codex`."** No. Every row in the
  routing table is mandatory for its kind. `/codex` is an independent
  cross-model pass toward the stamina budget (PRINCIPLES.md →
  Durability).

## Checklist before declaring `DONE`

- [ ] Artifact classified (or user-supplied `--kind` honoured).
- [ ] Every composed gstack skill in the table row(s) invoked.
- [ ] Every composed verdict collected and aggregated.
- [ ] Aggregate verdict published to the artifact thread (PR review or
      issue comment).
- [ ] Label transitioned (when orchestrated).
- [ ] `safer.skill_end` event emitted.
- [ ] Status marker on the last line.

## Communication discipline

Before you post a status marker or close your turn, **SendMessage to
`team-lead` immediately** with a one-line summary and the artifact URL:

```
SendMessage({
  to: "team-lead",
  summary: "<3-8 word summary>",
  message: "STATUS: DONE. Artifact: <URL>. Aggregate verdict: <X>."
})
```

If invoked outside an orchestrate context (no team), skip this step.

## Voice (reminder)

See `PRINCIPLES.md` → Voice. The aggregate verdict comment names the
composed skills that ran, the per-skill verdicts, and the aggregate rule
that selected the final verdict. One paragraph; no prose essays. The
consumer is the orchestrator, which routes on the verdict tag.
