# Per-modality dispatch prompt templates

Step 6d dispatches by filling the template that matches the sub-issue's `safer:<modality>` label. Every template is a copy-pasteable block. Every template carries the `source: orchestrate-auto-dispatch` header so a post-hoc audit can separate auto-dispatched work from human-driven dispatches. Every template ends with the mandatory status-marker instruction.

**Placeholder schema.** Every template draws from this fixed set — no template may introduce a placeholder outside it, and every placeholder below has one definition used consistently across all seven templates:

| Placeholder | Source | Notes |
|---|---|---|
| `{TEAM}` | `~/.claude/teams/<team-name>/config.json` → `name` | the team the dispatching orchestrator runs under; the dispatched teammate joins this team |
| `{ISSUE_URL}` | sub-issue `url` from `gh issue list --json url` | full URL including host |
| `{PARENT_URL}` | parent epic URL resolved from `Parent: #N` or `## Parent` in the sub-issue body | full URL; empty only if the epic is missing (which is itself a Step 6 skip case) |
| `{ACCEPTANCE}` | the `Acceptance:` line verbatim from the sub-issue body | if the sub-issue has no such line, skip the candidate — Step 6 never synthesizes acceptance |
| `{BRANCH_HINT}` | derived; see format below | empty string for modalities that produce no branch (`verify`, `research`, `contract`) |

`{BRANCH_HINT}` format: `<modality-short>/<issue-number>-<slug>` where

- `<modality-short>` is one of `junior`, `senior`, `staff`, `verify`, `spike`, `research`, `requirements` — the final token of the `safer:<modality>` label (drop the `implement-` prefix).
- `<issue-number>` is the sub-issue number with no `#` prefix.
- `<slug>` is the sub-issue title lowercased, non-alphanumerics collapsed to `-`, trimmed of leading/trailing `-`, and truncated to 40 characters. Example: sub-issue `#66` titled `[impl-senior] orchestrate: Step 6 work-queue scan` becomes `senior/66-impl-senior-orchestrate-step-6-work`.

For `verify`, `research`, and `requirements`, `{BRANCH_HINT}` is the empty string; their templates omit the `Branch: ...` line entirely.

## implement-junior

```
source: orchestrate-auto-dispatch
Dispatch with: `model: opus` per orchestrate Model routing table.
You are a teammate on team `{TEAM}` invoking `/safer:implement-junior`.

Sub-issue: {ISSUE_URL}
Parent epic: {PARENT_URL}
Branch: {BRANCH_HINT}

Read PRINCIPLES.md and skills/implement-junior/SKILL.md at the plugin root.
Read the sub-issue and parent epic before touching code.

Acceptance: {ACCEPTANCE}

Scope is ONE module. If you need to touch a second module, stop and escalate.
Before opening the PR, run /simplify and /review on the diff (mandatory; apply
findings; neither counts toward stamina N — they are pre-PR hygiene gates).
Open a draft PR titled `[impl-junior] ...`. Move the sub-issue to `review`.
Emit a status marker (DONE / DONE_WITH_CONCERNS / ESCALATED / BLOCKED /
NEEDS_CONTEXT) on your final output and SendMessage the team lead with the PR URL.
```

## implement-senior

```
source: orchestrate-auto-dispatch
Dispatch with: `model: opus` per orchestrate Model routing table.
You are a teammate on team `{TEAM}` invoking `/safer:implement-senior`.

Sub-issue: {ISSUE_URL}
Parent epic: {PARENT_URL}
Branch: {BRANCH_HINT}

Read PRINCIPLES.md and skills/implement-senior/SKILL.md at the plugin root.
Load the architect plan the parent epic references. No plan, escalate.

Acceptance: {ACCEPTANCE}

Scope is cross-module WITHIN the plan. Do not introduce new modules, new public
surface outside the plan, or new deps. `safer-diff-scope --head HEAD` must report
`senior`. Before opening the PR, run /simplify and /review on the diff (both
mandatory; apply findings unless a finding conflicts with a plan-approved
decision — cite the plan line in the PR body for any skipped finding). Neither
counts toward stamina N — pre-PR hygiene gates, not independent reviewers.
Open a draft PR titled `[impl-senior] ...` with a plan-anchor table.
/safer:review-senior is mandatory before merge.
Status marker + SendMessage the team lead with the PR URL.
```

## implement-staff

```
source: orchestrate-auto-dispatch
Dispatch with: `model: opus` per orchestrate Model routing table.
You are a teammate on team `{TEAM}` invoking `/safer:implement-staff`.

Sub-issue: {ISSUE_URL}
Parent epic: {PARENT_URL}
Branch: {BRANCH_HINT}

PRECONDITION: the parent epic carries label `plan-approved`. If not, STOP and
escalate — staff-tier work without architect sign-off is a Ratchet violation.

Read PRINCIPLES.md and skills/implement-staff/SKILL.md at the plugin root.
Read the approved spec + architect plan the parent epic references.

Acceptance: {ACCEPTANCE}

You may introduce new modules, new public interfaces, and new deps — all of
which must trace to the approved plan. Before opening the PR:
1. Run /simplify on the diff (mandatory, stricter than senior — apply every
   finding unless it conflicts with a plan-approved architect decision; cite the
   plan line in the PR body for any skipped finding). Does NOT count toward stamina N.
2. Run /codex on the PR diff (mandatory): post the codex verdict as a PR comment
   before /safer:review-senior fires. This counts as one independent pass toward
   the stamina N budget.
3. Run /review on the diff (mandatory): apply findings; cite plan-conflicting
   skips in the PR body under "Review skips". Does NOT count toward stamina N.
Open a draft PR titled `[impl-staff] ...`. /safer:review-senior is mandatory
before merge. Status marker + SendMessage the team lead with the PR URL.
```

## verify

```
source: orchestrate-auto-dispatch
Dispatch with: `model: opus` per orchestrate Model routing table.
You are a teammate on team `{TEAM}` invoking `/safer:verify`.

Sub-issue: {ISSUE_URL}
Parent epic: {PARENT_URL}

PRECONDITION: the PR under test is `MERGEABLE state=CLEAN`. If not, STOP;
this tick's auto-dispatch should not have picked you up.

Read PRINCIPLES.md and skills/verify/SKILL.md at the plugin root.

Acceptance: {ACCEPTANCE}

Run the repo test suite and lint. Post a ship/hold verdict as a PR comment
naming each acceptance criterion. Do NOT apply fixes — hand back if anything
fails. Status marker + SendMessage the team lead with the verdict URL.
```

## spike

```
source: orchestrate-auto-dispatch
Dispatch with: `model: opus` per orchestrate Model routing table.
You are a teammate on team `{TEAM}` invoking `/safer:spike`.

Sub-issue: {ISSUE_URL}
Parent epic: {PARENT_URL}
Branch: {BRANCH_HINT}  (throwaway — do NOT merge)

Read PRINCIPLES.md and skills/spike/SKILL.md at the plugin root.

Acceptance: {ACCEPTANCE}

Answer one feasibility question with throwaway code. Publish a go/no-go
writeup as a sub-issue comment. The branch stays unmerged. Status marker
+ SendMessage the team lead with the writeup URL.
```

## research

```
source: orchestrate-auto-dispatch
Dispatch with: `model: opus` (Researcher); Supervisor role uses codex.
You are a teammate on team `{TEAM}` invoking `/safer:research`.

Sub-issue: {ISSUE_URL}
Parent epic: {PARENT_URL}

Read PRINCIPLES.md and skills/research/SKILL.md at the plugin root.

Acceptance: {ACCEPTANCE}

Run an iterative hypothesis loop; post one comment per iteration on the
sub-issue as your research ledger. Produce no code. The Supervisor role
for each round is codex (run /codex --mode supervisor on the Researcher
output before advancing to the next round). Status marker + SendMessage
the team lead with the ledger URL when the loop converges or the budget
runs out.
```

## requirements

```
source: orchestrate-auto-dispatch
Dispatch with: `model: opus` per orchestrate Model routing table.
You are a teammate on team `{TEAM}` invoking `/safer:requirements`.

Sub-issue: {ISSUE_URL}
Parent epic: {PARENT_URL}

Read PRINCIPLES.md and skills/requirements/SKILL.md at the plugin root.

Acceptance: {ACCEPTANCE}

Produce a requirements document with goals, non-goals, invariants, and
explicit acceptance criteria. No architecture, no libraries, no code. Publish as a
comment on the parent epic (or sub-issue body per the skill's publication
rule). After publishing, run /codex --mode review on the published
artifact. The codex verdict must be `approve` before transitioning to
`review`. If `changes-requested`, revise and re-run (one revision round). If `reject`,
escalate to the user with codex's reasoning.
Transition the sub-issue to `review`. Status marker + SendMessage the
team lead with the artifact URL.
```

Templates are intentionally terse. They do not replicate the full modality charter; they point the teammate at `SKILL.md` and carry the scope contract that differs per modality. If a template grows beyond ~25 lines, the modality has shifted; revisit the template rather than expanding it in-place.

