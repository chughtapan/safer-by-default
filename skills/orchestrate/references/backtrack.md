# Phase 6 — Backtrack

When a sub-task reports `ESCALATED` / `BLOCKED` / `NEEDS_CONTEXT`, do not rescue. Read the escalation artifact, classify the cause, and route:

| Cause | Route |
|---|---|
| Contract ambiguity | New `requirements` sub-task, OR revise the existing one. Blocked sub-task waits. |
| Architecture mismatch | New `architect` sub-task. Blocked sub-task waits. |
| Scope miscalibration (modality too tight) | Relabel blocked sub-task to next-tier modality. Reopen it in `planning`. |
| Scope miscalibration (modality too loose) | Split blocked sub-task into two, each correctly scoped. |
| External dependency | Comment on the parent epic with the blocker. Post `NEEDS_CONTEXT` to the user. |
| Research gap | New `research` or `spike` sub-task. Blocked sub-task waits. |
| Duplicate sub-task discovered | Close the duplicate with a cross-link. |

Update the decomposition table on the parent epic to reflect the re-triage. Emit `safer.modality_handoff` with the cause.

## Flagged vs reproduced

**Rule.** A bug that has been *flagged* (reviewer observation, dogfood comment, teammate self-report) but not yet *reproduced* routes to `/safer:diagnose`, never directly to `implement-*`. Re-label any `safer:implement-*` sub-issue opened against an unreproduced bug to `safer:diagnose` before dispatch; wait for diagnose to publish a reproduction artifact + codex verdict before re-opening the implement-* path.

**Rationale.** A flagged symptom description is a hypothesis about the failure mode, not a fact. Dispatching `implement-*` against a hypothesis wastes a pane on the wrong cause and lands a fix that drifts from the real defect. The reproduction artifact + codex verdict is what turns the hypothesis into a fact the implementer can act on.

**Three-strikes rule.** If a single sub-task has been re-triaged **3 times without reaching `done`**, the project is mis-scoped. Stop and escalate to the user via the Confusion Protocol (below). Do not attempt a fourth triage.

## Post-refactor regressions

**Rule.** When a bug surfaced *after* a recent refactor (the user mentions the refactor PR, or the symptom started landing in a window the refactor straddles), the diagnose sub-issue body MUST cite the refactor PR URL and request a pre-vs-post behavior comparison.

**Brief addition for the diagnose sub-issue body.** Append a `## Post-refactor context` section with:

```
## Post-refactor context
Refactor PR: <full URL>
Symptom started: <approximate window or commit range>
Hypothesis: silent behavior change in the refactor.
Diagnose must:
- include "compare to last-known-good" reasoning in the REASONING section of the published artifact (what changed in the refactor window that could plausibly produce the observed symptom?),
- pass the candidate pre-vs-post delta to /codex as one of the directions to evaluate,
- if codex returns confirmed-root-cause naming the refactor as the cause, the orchestrator's default fix routing is "restore pre-refactor behavior" unless restoration is explicitly ruled out by the user.
```

**Rationale.** Post-refactor bugs that look novel are usually silent behavior deltas. Diagnose runs not primed for "compare to last-known-good" tend to publish repros that don't surface the delta, and codex then has nothing to evaluate. The brief addition primes the comparison in the REASONING section so codex sees the candidate hypothesis, and routes the default fix-shape toward restoration rather than reinvention.

**When the dispatch is for `/safer:architect` after `/safer:diagnose` on a post-refactor regression.** Include the same `## Post-refactor context` section in the architect sub-issue body, plus a pointer to the diagnose artifact. The architect must read "what was this doing before?" before designing. Restoration is a one-line plan; new pattern requires evidence.

