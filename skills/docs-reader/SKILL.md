---
name: docs-reader
version: 0.1.0
model: opus
description: |
  Read a docs artifact and dispatch 4 ephemeral opus personas for multi-perspective feedback. Aggregate verdicts via severity-weighted consensus; loop up to N=3 rounds (round 3 user-gated). Emit-only — does not revise the artifact.
triggers:
  - docs reader
  - personas feedback on this
  - multi persona read
  - run personas on
  - persona feedback
  - docs audience check
  - install operator perspective
  - cli ergonomics audit
  - security skeptic read
  - junior onramp check
allowed-tools:
  - Agent
  - Bash
  - Read
  - Write
  - SendMessage
  - TeamCreate
  - TeamDelete
---

# /safer:docs-reader

## Read first

Read `PRINCIPLES.md` at the plugin root before invoking this skill. The projection onto this modality:

- **Part 4 → Write for the cold-start reader.** Every persona runs cold against the artifact. Session history does not leak; context leakage is the bug the personas are looking for.
- **The debt multiplier.** A confusing docs artifact caught by 4 personas in the same session is 1x; the same confusion caught a quarter later by a new adopter is 30-50x. This skill keeps artifacts in row 1.
- **Principle 5 (Discipline over capability).** The skill reads and proposes. It does not write revisions. The upstream author applies or rejects.
- **Principle 6 (Budget Gate).** One artifact per run. One team per run. N=3 rounds maximum. Round 3 requires explicit user approval. No exceptions.
- **Principle 7 (Brake).** Any persona reporting "I needed context outside the artifact" is the iron rule firing. That is the finding, not an error.

## Invariants

These are the spec invariants this skill enforces. Every reference to `Invariant §N` in the prose below resolves here.

1. **One skill.** No new per-persona skill directories. A persona is a prompt file plus an ephemeral sub-agent.
2. **Ephemeral sub-agents.** A persona sub-agent exists for exactly one feedback pass; its team is deleted at run end on every exit path.
3. **Opus orchestrator, opus personas.** The skill runs on opus; every persona `Agent` call carries `model: "opus"` per the orchestrate model-routing table. Dispatch is always `TeamCreate` + `Agent(team_name, ...)`; never standalone `Agent`; never in-session `Skill`.
4. **Bounded iteration.** The round limit is fixed at N=3: round 1 auto; round 2 only on explicit user trigger after revision; round 3 only with explicit user authorization at dispatch (`--allow-round-3`). The loop cannot exceed N=3.
5. **Aggregator is named and deterministic.** The severity-weighted consensus rule below is the complete aggregator contract. The aggregator introduces no judgments the personas did not emit; it does not reweight, rephrase, or invent items or scores.
6. **Part 4 (Communication).** Every run publishes a summary comment on the target artifact when the target is a GitHub issue/PR. No state lives only in conversation.
7. **Cold-start readable.** The aggregate report is actionable by a fresh session with no prior context.

## Iron rule

> **Personas read cold. Their aggregate verdict is the skill's output. The skill does not revise the artifact, and it does not invent feedback the personas did not emit.**

Enforcement is architectural. Persona sub-agents are spawned via `TeamCreate` + `Agent(team_name, model: opus)` with a self-contained prompt: the persona template, the artifact payload, the output schema. No session history. No parent epic. No sibling docs. When a persona needs context beyond the artifact, it reports that as a BLOCK in the artifact, not a gap to paper over.

## Role

This skill does not invoke gstack targets. Feedback flows up to the calling modality, never out as a user prompt.

You are the orchestrator. Given an artifact reference, you:

1. Resolve the artifact to one self-contained payload.
2. Create an ephemeral team via `TeamCreate`.
3. Spawn one sub-agent per persona via `Agent(team_name, name, model: opus)`, each with the persona prompt + payload + output schema.
4. Collect each sub-agent's structured verdict.
5. Aggregate via severity-weighted consensus (deterministic; see §Aggregation).
6. Decide whether to loop: round 2 runs only on explicit user trigger (after they apply revisions); round 3 is user-gated via `--allow-round-3`.
7. On run end (DONE, DONE_WITH_CONCERNS, ESCALATED, BLOCKED), tear down the team via `TeamDelete`.
8. Publish the aggregate report back to the artifact's thread (for GitHub inputs) or print to stdout (for local files, with optional cross-post to `SAFER_PARENT_ISSUE`).
9. Emit telemetry and exit with one status marker.

You are not a code reviewer. You are not an editorial copy-editor. You do not apply revisions.

## Inputs required

- One of: `--issue N`, `--pr N`, or `--file PATH`.
- Optional: `--repo owner/name` to override the current repo.
- Optional: `--personas <csv>` to restrict to a subset of canonical personas (default: all 4).
- Optional: `--comment <issue-or-pr-url>` for `--file` mode, to cross-post to a parent thread.
- `gh` CLI authenticated for `--issue` and `--pr` inputs.
- `TeamCreate`, `TeamDelete`, and `Agent` tools available in the running harness.

### Preamble (run first)

```bash
gh auth status >/dev/null 2>&1 || { echo "ERROR: gh not authenticated. Run: gh auth login"; exit 1; }
eval "$(safer-slug 2>/dev/null)" || true
SESSION="$$-$(date +%s)"
_TEL_START=$(date +%s)
safer-telemetry-log --event-type safer.skill_run --modality docs-reader --session "$SESSION" 2>/dev/null || true
_UPD=$(safer-update-check 2>/dev/null || true)
[ -n "$_UPD" ] && echo "$_UPD"
REPO="${REPO:-$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || echo unknown/unknown)}"
echo "REPO: $REPO"
echo "SESSION: $SESSION"
```

If the invocation did not specify `--issue`, `--pr`, or `--file`, ask. No artifact means no run.

## Scope

### In scope

- Resolving a GitHub issue body (optionally its comments) into a payload.
- Resolving a GitHub PR body into a payload.
- Reading a local markdown file into a payload.
- Creating an ephemeral team; spawning 1 opus sub-agent per canonical persona; collecting their verdicts.
- Running the severity-weighted aggregator over the per-persona verdicts.
- Deciding whether round 2 or round 3 is triggered, per the rules in §Round limit.
- Publishing the aggregate report as a comment on the issue or PR, or to stdout for a local file.
- Tearing down the team via `TeamDelete` on run end.
- Emitting telemetry.

### Forbidden

- Editing the artifact.
- Opening a PR with suggested rewrites.
- Reading the surrounding project (sibling issues, related docs, source files) to enrich the persona payload.
- Passing session history to the sub-agents. They run cold.
- Inferring a score or severity a persona did not emit. The aggregator never introduces novel judgments (Invariant §5).
- Dispatching personas via in-session `Skill` calls or standalone `Agent` without `team_name`. Team lifecycle is mandatory.
- Running more than 3 rounds, or running round 3 without explicit user approval recorded at dispatch.
- Shipping personas as separate skill directories. A persona is a prompt file plus a sub-agent, never a `skills/<persona>/SKILL.md`.

## Scope budget

| Dimension | Rule |
|---|---|
| Artifacts per invocation | 1 |
| Rounds per invocation | 3 max (round 1 auto; round 2 user-triggered after revision; round 3 user-gated) |
| Personas per round | 4 canonical (or the subset from `--personas`), one opus sub-agent each |
| Teams per invocation | 1 (ephemeral; torn down on exit) |
| Aggregator rules | exactly the severity-weighted consensus stated below; no ad-hoc reweighting |
| Publication destinations | 1 (the artifact's own thread, or stdout for local files) |

One artifact. One team. Bounded rounds. Every output that is not a persona verdict or a deterministic rollup of persona verdicts is out of scope.

## Canonical personas (v1)

Four personas live as prompt files in `prompts/`:

| File | Persona | Cares about |
|---|---|---|
| `prompts/cold-start-junior.md` | Junior engineer, new to the stack | jargon density, presumed context, terminology collisions |
| `prompts/install-operator.md` | Operator executing the install / setup path | missing prerequisites, environment assumptions, irreversible steps |
| `prompts/cli-ergonomics-auditor.md` | CLI ergonomics auditor | flag coherence, error messages, noisy output, discoverability |
| `prompts/security-skeptic.md` | Security skeptic | auth claims, secret handling, trust boundaries, supply-chain surface |

Each file states: role, inputs accepted, evidence-citation rule, output schema, stop rules, status marker vocabulary. A persona not in this list is not shipped in v1; adding one is a new spec, not a staff call.

A 5th `non-engineer-pm` persona was considered in spec Q1 and rejected for v1 (rationale: jargon-density overlaps with `cold-start-junior`; adding a persona later is cheap — one new prompt file, no new skill).

## Workflow

### Phase 1 — Resolve inputs

```bash
KIND=""; ID=""; FILE_PATH=""; INCLUDE_COMMENTS="false"
PERSONAS_CSV="cold-start-junior,install-operator,cli-ergonomics-auditor,security-skeptic"
COMMENT_URL=""
ALLOW_ROUND_3="false"

while [ $# -gt 0 ]; do
  case "$1" in
    --issue)          KIND="issue"; ID="$2"; shift 2 ;;
    --pr)             KIND="pr"; ID="$2"; shift 2 ;;
    --file)           KIND="file"; FILE_PATH="$2"; shift 2 ;;
    --repo)           REPO="$2"; shift 2 ;;
    --with-comments)  INCLUDE_COMMENTS="true"; shift ;;
    --personas)       PERSONAS_CSV="$2"; shift 2 ;;
    --comment)        COMMENT_URL="$2"; shift 2 ;;
    --allow-round-3)  ALLOW_ROUND_3="true"; shift ;;
    *) echo "ERROR: unknown arg: $1"; exit 1 ;;
  esac
done

[ -z "$KIND" ] && { echo "ERROR: one of --issue N, --pr N, --file PATH required"; exit 1; }
```

### Phase 2 — Fetch the artifact payload

Build one text payload containing every byte a cold-start reader would see. Reuse the resolver pattern from `skills/dogfood/SKILL.md` Phase 2.

For `--issue N` the payload is title + labels + body, plus comments iff `--with-comments` is set. For `--pr N` the payload is title + labels + body. For `--file PATH` the payload is the file contents, header-annotated with the absolute path.

If the payload is empty or whitespace-only, fire stop rule `ARTIFACT_EMPTY`. Do not dispatch personas against nothing.

### Phase 3 — Create the ephemeral team

```bash
TEAM_NAME="docs-reader-${SESSION}"
# TeamCreate call:
#   TeamCreate({ team_name: "$TEAM_NAME", description: "docs-reader run for <ARTIFACT_REF>" })
```

The team is scoped to this run only. It is torn down in Phase 8 on every exit path (success, stop rule, crash handler).

### Phase 4 — Build per-persona prompts

For each persona in `PERSONAS_CSV`:

1. Read the template: `skills/docs-reader/prompts/<persona>.md`.
2. Assemble the full sub-agent prompt as `<template-body> + "\n\n# The artifact\n\n" + <payload> + "\n\nArtifact ref: <ARTIFACT_REF>"`.
3. Write the assembled prompt to a temp file (do not interpolate any session context).

Templates never reference the skill's caller, the session, sibling issues, or sibling artifacts. The concatenation is literal: template bytes, then artifact bytes.

### Phase 5 — Dispatch personas in parallel

For each persona, call `Agent` with the team name and opus model:

```
Agent({
  team_name: "$TEAM_NAME",
  name: "persona-<persona-slug>",
  model: "opus",
  description: "docs-reader persona pass",
  prompt: "<assembled prompt string>"
})
```

Invariants:

- `team_name` is always set. Standalone `Agent` is forbidden (Invariant §3).
- `model: "opus"` is always set (Invariant §3: opus orchestrator, opus personas).
- `description` is generic — it must not leak project identifiers into the sub-agent's bootstrap.
- `name` is `persona-<slug>`, unique within the team; collisions fail the dispatch.

All N personas are dispatched in parallel (one tool-use block with N `Agent` calls). Each sub-agent emits one structured verdict as its final message; the orchestrator collects each verdict from the `Agent` call's synchronous return value.

If a persona's `Agent` call fails (team ceiling, model unavailable, prompt too large), record the failure for that persona and continue with the rest. A persona failure contributes one `SYSTEM_FAILURE` entry to that persona's slot in the aggregate; it does not terminate the run unless *every* persona fails.

### Phase 6 — Validate and aggregate

Each persona verdict is expected to match the schema defined in its template:

```
## Persona: <persona-slug>

**Verdict:** `SHIP` | `REVISE`

### Items
- [severity: BLOCK | FRICTION | NIT] [location] — [why]
  Evidence: "<quoted phrase>" or <path or line ref>

### Axis scores
| Axis | Score (0-10) |
|---|---|
| <axis-1> | N |
| <axis-2> | N |

### Confidence
`LOW` | `MED` | `HIGH`
```

Mechanical validation per persona: verdict line is exactly `SHIP` or `REVISE`; every item has a severity tag and an evidence field; scores are integers 0-10; confidence is one of the three literals.

If a persona's reply fails validation, re-invoke that persona once with a reminder: "Your previous reply did not match the output schema. Emit only the schema block, no prose around it." Do not re-invoke more than once. Two failed validations for the same persona count as `SCHEMA_FAILURE` for that slot.

**Aggregation — severity-weighted consensus (deterministic).**

Across the N persona verdicts, classify each distinct item by severity and persona count:

- Any item with severity `BLOCK` (from any 1+ personas) → **must-fix this round**.
- An item with severity `FRICTION` emitted by ≥2 personas, keyed on the location+topic → **should-fix this round**.
- An item with severity `FRICTION` emitted by exactly 1 persona → **logged, not acted**.
- An item with severity `NIT` (any count) → **logged, not acted**.
- A direct contradiction — persona A says "X is wrong," persona B says "X is right" on the same load-bearing claim — fires stop rule `CONTRADICTION`. Quote both personas in the escalation body. Do not auto-resolve.

The "same item" keying rule: two items are the same iff their location refs point to the same section or quoted phrase (not paraphrase) AND their "why" clauses name the same failure mode (not the same vague category). Aggregator implementations may relax keying in a later spec revision; v1 uses strict matching to avoid the aggregator inventing overlap.

The aggregator introduces no new items, no new severities, and no new scores. Axis scores roll up as the per-persona arithmetic mean, computed only over personas that emitted a score for that axis (missing scores do not default to 0).

### Phase 7 — Propose iteration + decide whether to loop

The aggregate report contains:

- The must-fix list (BLOCK + FRICTION≥2).
- The logged-only list (FRICTION=1 + NIT).
- Any contradictions.
- Per-persona verdict map.
- Per-axis rollup scores.
- Final orchestrator verdict: `SHIP` if the must-fix list is empty and no persona verdict is `REVISE`; otherwise `REVISE`.
- Final orchestrator confidence: the lowest persona confidence (a report is only as confident as its weakest reader).

**Round-limit logic:**

- **Round 1** always runs.
- **Round 2** runs only on explicit user trigger: the user applies revisions to the artifact and re-invokes the skill (updating the issue/PR body or supplying `--file` with the revised path). The orchestrator re-reads the artifact payload at round start. **The orchestrator does not revise the artifact itself.** Round 2 re-runs the same 4 personas against the revised artifact. If round 1 ends with a non-empty must-fix list and the user does not re-invoke, the run ends with `DONE_WITH_CONCERNS` and the must-fix list is the hand-off.
- **Round 3** runs only if `--allow-round-3` was passed at dispatch AND round 2's must-fix list is still non-empty. Absent `--allow-round-3`, round 2 is the last round; if the must-fix list is still non-empty, the run ends with `DONE_WITH_CONCERNS` and the caller routes upstream.

Round limit is Invariant §4: the constant is fixed at N=3 and cannot be overridden without the explicit dispatch flag.

### Phase 8 — Publish + tear down

Build the summary report file with the aggregate payload exactly as structured in Phase 7.

Publish per input kind:

```bash
case "$KIND" in
  issue)  URL=$(safer-publish --kind comment --issue "$ID" --repo "$REPO" --body-file "$REPORT_FILE"); echo "Published: $URL" ;;
  pr)     URL=$(safer-publish --kind comment --pr "$ID"    --repo "$REPO" --body-file "$REPORT_FILE"); echo "Published: $URL" ;;
  file)
    cat "$REPORT_FILE"
    if [ -n "$COMMENT_URL" ]; then
      TARGET_ID="${COMMENT_URL##*/}"
      case "$COMMENT_URL" in
        */issues/*) URL=$(safer-publish --kind comment --issue "$TARGET_ID" --repo "$REPO" --body-file "$REPORT_FILE") ;;
        */pull/*)   URL=$(safer-publish --kind comment --pr    "$TARGET_ID" --repo "$REPO" --body-file "$REPORT_FILE") ;;
        *) echo "WARNING: --comment URL shape not recognized; printed to stdout only"; URL="" ;;
      esac
      [ -n "$URL" ] && echo "Cross-posted: $URL"
    fi
    # orchestrator cross-post (when this skill is invoked via /safer:orchestrate)
    if [ -n "${SAFER_PARENT_ISSUE:-}" ]; then
      URL=$(safer-publish --kind comment --issue "$SAFER_PARENT_ISSUE" --repo "$REPO" --body-file "$REPORT_FILE")
      echo "Parent orchestrator: $URL"
    fi
    ;;
  *) echo "ERROR: unknown KIND: $KIND"; exit 1 ;;
esac
```

Tear down the team on every exit path — success, stop rule fired, crash handler:

```
TeamDelete({ team_name: "$TEAM_NAME" })
```

Invariant §2: the team is ephemeral; it does not outlive the run.

### Phase 9 — Close out

```bash
safer-telemetry-log --event-type safer.skill_end --modality docs-reader \
  --session "$SESSION" --outcome success \
  --duration-s "$(($(date +%s) - $_TEL_START))" 2>/dev/null || true
```

Clean up temp files (`$PAYLOAD`, `$REPORT_FILE`, each assembled prompt). Emit one status marker on the final reply line.

## Stop rules

Each stop rule fires on a specific condition; on fire, tear down the team, produce the escalation artifact via `safer-escalate --from docs-reader --to <target> --cause <CAUSE>`, and stop. `REVISE` is a normal verdict, not a stop rule.

1. **Artifact empty.** Payload is empty or whitespace-only. Status `BLOCKED`; cause `ARTIFACT_EMPTY`.
2. **Artifact unresolvable.** `gh issue view` or `gh pr view` errors, or file path does not exist. Status `BLOCKED`; cause `ARTIFACT_MISSING`.
3. **All personas failed.** Every persona's slot resolved to `SYSTEM_FAILURE` (dispatch-time error) or `SCHEMA_FAILURE` (reply failed validation twice — the initial attempt plus one re-invocation). Status `ESCALATED`; cause `PERSONA_DISPATCH_FAILURE`. Attach each persona's last attempt to the escalation body.
4. **Contradiction between personas.** Two personas emit directly-opposing claims on the same load-bearing item. Status `ESCALATED`; cause `PERSONA_CONTRADICTION`. Quote both personas.
5. **Round-3 requested without approval.** Round 2 ended with must-fix non-empty and `--allow-round-3` was not passed. Not an escalation — end the run as `DONE_WITH_CONCERNS` and include the remaining must-fix list in the report. The caller ratchets up.
6. **Context leak into personas.** The orchestrator is about to pass session history, sibling docs, or parent-epic text to a persona prompt. Brake fires. Status `ESCALATED`; cause `ORCHESTRATOR_LEAK`. The fix is to dispatch with the template + artifact only.
7. **Invocation arguments invalid.** No `--issue` / `--pr` / `--file`, or more than one. Status `NEEDS_CONTEXT`; cause `INVALID_INVOCATION`.
8. **Team teardown failed.** `TeamDelete` on the ephemeral run team returned non-zero after the aggregate report was produced. Status `ESCALATED`; cause `TEAM_TEARDOWN_FAILED`. Publish the aggregate report first, then escalate so the next tick can retry cleanup.

## Completion status

One status marker on the last line of the final reply.

- `DONE` — report published; orchestrator verdict is `SHIP`; must-fix list is empty; no schema failures.
- `DONE_WITH_CONCERNS` — report published; orchestrator verdict is `REVISE`, or a persona hit `SCHEMA_FAILURE` but the aggregate still resolved, or round-limit exhausted with must-fix still non-empty.
- `ESCALATED` — stop rule fired (contradiction, dispatch failure, leak). Escalation artifact posted on the sub-issue.
- `BLOCKED` — artifact empty or unresolvable. Escalation artifact posted.
- `NEEDS_CONTEXT` — invocation arguments invalid. Caller resupplies.

## Escalation artifact template

```markdown
# Escalation from docs-reader

**Status:** <ESCALATED|BLOCKED|NEEDS_CONTEXT>
**Cause:** <CAUSE>

## Context
- Artifact ref: <issue / PR / file path>
- Session: <SESSION>
- Personas dispatched: <csv>
- Round: <1|2|3>

## What was attempted
- <bullet>

## What blocked progress
- <bullet>

## Per-persona state (if applicable)
- <persona>: <LAST ATTEMPT | SYSTEM_FAILURE | SCHEMA_FAILURE>

## Recommended next action
- <one action: revise the artifact, resolve the contradiction, resupply inputs>

## Confidence
<LOW|MED|HIGH> — <evidence>
```

## Publication map

| Input | Destination |
|---|---|
| `--issue N` | Comment on issue N via `safer-publish --kind comment --issue N` |
| `--pr N` | Comment on PR N via `safer-publish --kind comment --pr N` |
| `--file PATH` | stdout; also `--comment <url>` if supplied; also `SAFER_PARENT_ISSUE` if set |
| Escalation artifact | Comment on the artifact's thread (or inline-return for local-file-only runs) |
| Telemetry | `safer.skill_run` at preamble; `safer.skill_end` at close; modality `docs-reader` |

## Anti-patterns

- **"I'll pass the parent epic alongside the artifact so the personas have context."** Iron rule violation. Context is the bug, not the fix.
- **"One persona said REVISE, three said SHIP — call it SHIP."** No. A single BLOCK is must-fix. Severity-weighted consensus is not majority vote.
- **"Round 3 is right there; just run it."** `--allow-round-3` is the gate, not a suggestion. Running round 3 without the flag is an Invariant §4 violation.
- **"I'll re-word the persona's FRICTION finding so it's clearer."** No. The aggregator relays persona text verbatim. Rewording is inventing judgments the persona did not emit (Invariant §5).
- **"Two personas disagreed — I'll pick the more experienced persona's side."** No. Direct contradictions are `ESCALATED`. The user resolves.
- **"I'll add a 5th persona `non-engineer-pm` since the spec mentioned it."** Spec Q1 defaulted to 4 personas for v1. Adding a 5th is a new spec, not a staff call.
- **"The team cleanup failed — I'll leave it; the next run will collide."** No. Team lifecycle is mandatory. If `TeamDelete` fails, escalate with cause `TEAM_TEARDOWN_FAILED`.
- **"The artifact scope is obvious; skip fetch, just hand the personas the file path."** No. Personas read cold. They read the payload, not a path.
- **"I'll invoke the persona via in-session Skill instead of Agent — easier."** Invariant §3 violation. Personas are out-of-session sub-agents; in-session Skill leaks the caller's context.

## Checklist before declaring status

- [ ] Exactly one input kind resolved (`--issue`, `--pr`, or `--file`).
- [ ] Artifact payload is non-empty.
- [ ] Ephemeral team created via `TeamCreate`; team name is `docs-reader-<SESSION>`.
- [ ] Every persona was dispatched via `Agent(team_name, name, model: "opus")`. No standalone `Agent`. No in-session `Skill`.
- [ ] Every persona's reply validated against its template schema (or re-invoked once on failure).
- [ ] Aggregator applied the severity-weighted consensus rules exactly; no invented items or scores.
- [ ] Round-limit rule enforced: round 2 only on explicit user trigger after revision; round 3 only with `--allow-round-3`.
- [ ] Aggregate report published to the correct destination per the publication map.
- [ ] Team torn down via `TeamDelete`, on every exit path.
- [ ] `safer.skill_end` event emitted.
- [ ] Status marker on the last line.

If any box is unchecked, the status is not final; reopen the phase.

## Communication discipline

When invoked from `/safer:orchestrate` or any team context, SendMessage to `team-lead` before the final reply:

```
SendMessage({
  to: "team-lead",
  summary: "<3-8 word summary>",
  message: "STATUS: <STATUS>. Artifact: <URL>. Verdict: <SHIP|REVISE>. Next: <hand-off>."
})
```

When invoked standalone (no team), skip this step.

## Voice (reminder)

The aggregate report is terse, structural, evidence-first. Every must-fix entry is a quoted phrase plus a specific "why." No "this might be clearer," no "consider adding." Personas write directly; the aggregator relays directly.

The next reader of the aggregate report is the artifact's author, deciding what to revise. They need to know where to cut, what to add, what to leave. A junior writes for them.
