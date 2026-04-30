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

## Iron rule

> **You comment; you do not edit. The author applies fixes.**

`/safer:review-senior` itself never writes to the diff. It dispatches
composed gstack skills; some of those (notably `/review`) may write
their own comments and some legacy flows write edits. The safer-side
posture is read-only review: you aggregate verdicts and publish a
comment, never a patch. If the instinct to "just fix this one line"
appears, it is the stop rule firing. Write the comment; let the author
push the fix.

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

## Craft checks the reviewer still owns (Principles 1-4)

gstack `/review` looks at structural issues, `/simplify` at reuse /
efficiency, `/codex` at independent cross-model signal. None of them
know the safer craft floor (see `PRINCIPLES.md`). Before publishing the
aggregate verdict, run these four checks against the diff or artifact
yourself and fold findings into the aggregate body:

- **P1 (Types beat tests).** New constraints should be encoded in types
  (branded types, discriminated unions, `NonEmptyArray`, literal-string
  unions), not enforced by runtime `assert`/`.length > 0`/`if (!x) throw`
  patterns a type would have made unnecessary. Flag `as T` casts across
  module boundaries.
- **P2 (Validate at boundaries).** Every new ingress point (HTTP handler,
  JSON parser, env-var read, file read, MoltZap inbound, CLI flag decode)
  must decode through a schema. `JSON.parse(x) as T`, `await r.json() as
  Body`, or `process.env.X!` far from boot is a finding.
- **P3 (Errors are typed, not thrown).** Flag `throw new Error(...)`
  outside startup validation, any `catch {}` or `catch (e) { return
  null }`, and any failure-capable function returning bare `Promise<T>`
  without an error channel in the type.
- **P4 (Exhaustiveness over optionality).** Every new `switch` over a
  union ends with `default: return absurd(x)` (or equivalent). Every
  new if-else chain terminates. Missing `never`-check on an internal
  discriminant is a finding even if the compiler still passes.

When operating as the aggregate dispatcher, record findings in a
"P1-P4 craft notes" section of the aggregate comment so the author knows
which violations came from the safer floor vs. the composed gstack
skills. If no composed skills ran (e.g. environment missing), these
four checks are the minimum the aggregate still carries.

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

### Fallback mode (no gstack available)

If NO composed gstack skills are available (full environment miss, not
partial), do NOT block the review. Other shipped skills — notably
`skills/orchestrate/SKILL.md` and `skills/stamina/SKILL.md` — treat
`/safer:review-senior` as the fallback reviewer; returning only
`BLOCKED` breaks those consumers.

Fallback reviewer workflow (only when every gstack skill in the
applicable table row is missing):

1. Run `safer-diff-scope --pr "$PR"` and record the observed shape.
2. Read the full diff via `gh pr diff "$PR"`.
3. Read the sub-issue body for acceptance criteria.
4. Walk each craft principle (P1–P4, above) against the diff; record
   findings with `file:line`.
5. Check scope alignment: each acceptance criterion is addressed, each
   addressed criterion is evidenced in the diff.
6. Check tests: success branch, each error tag, each named invariant.
7. Write a native GitHub PR review via `gh pr review`:
   - `--approve` when craft is green, scope aligns, and every
     acceptance criterion is directly verifiable from the diff or
     closed by an already-posted `/safer:verify` comment.
   - `HOLD` (published via `gh pr review --comment` with body prefixed
     `## Verdict\nHOLD`) when craft is green but a measured-threshold
     criterion is unproven.
   - `--request-changes` on craft violation, scope mismatch,
     non-measurement criterion unmet, gutted tests, or tests missing
     for non-trivial logic.
8. Post a verdict comment on the sub-issue and transition the label
   (`review` → `verifying` on approve/HOLD; `review` → `implementing`
   on request-changes).

Fallback mode is the read-only posture of the Iron Rule above: you
still do not edit source files. The fallback produces a review; it
does not patch the diff.

Unavailability tagging:

- Full miss (fallback fires): emit `DONE_WITH_CONCERNS` with a note
  that the aggregate verdict was produced by the fallback reviewer
  rather than the composed gstack pipeline, so team-lead can upgrade
  the environment before future runs.
- Partial miss (some composed skills present, some missing): run the
  available ones, emit `DONE_WITH_CONCERNS` naming the missing skill.

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

Partial-miss handling (SOME composed skills missing): emit
`DONE_WITH_CONCERNS` with the missing skill name; continue dispatch
to the skills that ARE available (do NOT stop on the first miss).
Do NOT attempt to "do the work" of a missing skill here — that
collapses the separation between dispatcher and reviewer.

Full-miss handling (EVERY composed skill in the row is missing):
fall through to the **Fallback reviewer workflow** above ("Fallback
mode (no gstack available)"). This is the explicit consumer contract
with `skills/orchestrate/SKILL.md` and `skills/stamina/SKILL.md`:
they treat review-senior as the fallback reviewer; emitting `BLOCKED`
here breaks them.

### Phase 3 — Aggregate the verdict

Code references in the verdict body use the canonical pinned form `path:N[-M]@<sha7>`. See `PRINCIPLES.md#code-references-are-pinned`.

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

---

## Composition with gstack

### Invokes

- `/review` — gstack's pre-landing review (SQL safety, LLM trust boundaries, conditional side effects).
- `/simplify` — diff de-duplication and simplification.
- `/codex review` — cross-model adversarial review.
- `/safer:dogfood` — cold-start read of the diff.
- `/security-review` — security-focused review pass.

For PRs touching public surface or escalating to staff tier, `/safer:stamina --pr` replaces this single-reviewer path with N≥3 independent reviewers (per `PRINCIPLES.md` → Durability).
