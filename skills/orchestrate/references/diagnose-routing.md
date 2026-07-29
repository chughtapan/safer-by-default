# Step 5c.5 — Diagnose verdict routing

Applies only when the sub-issue being closed carries the `safer:diagnose` modality. Most epics decompose to zero diagnose sub-issues; skip this file entirely when none is closing.

The diagnose artifact carries a `## CODEX VERDICT` section. Read it; do not summarize from the teammate `SendMessage`. The verdict drives one of four routes:

1. **`logical-fallacy`.** Codex says the repro doesn't demonstrate the claimed symptom. The diagnose teammate's reasoning was broken; the next round corrects it.
   - Transition the sub-issue label `review` → `planning` (the modality revises).
   - Append a comment on the sub-issue: `Round N+1: codex returned logical-fallacy. Gap: <quoted from artifact>. Re-running diagnose with the correction.`
   - Re-dispatch the same diagnose teammate (Step 5c.4) with the same sub-issue. The teammate reads the new comment as the round seed.
   - Do not advance to the next decomposition row.
2. **`symptom` with N=1 direction.** Codex confirms the bug is real and names a single hypothesis to investigate next.
   - Transition the sub-issue label `review` → `planning`.
   - Re-dispatch the same diagnose teammate with `SAFER_DIAGNOSE_DIRECTION=<the one direction, verbatim from codex>` set in the dispatch environment.
   - Do not advance to the next decomposition row.
3. **`symptom` with N>1 directions.** Codex names multiple hypotheses; one diagnose cannot pursue them concurrently. Fork.
   - Transition the closing sub-issue's label `review` → `planning`. Set its `SAFER_DIAGNOSE_DIRECTION` to direction[0] (the first hypothesis from codex's list).
   - For each direction[1..N-1], create a NEW `safer:diagnose` sub-issue on the parent epic, body cites the parent diagnose's repro URL and names `SAFER_DIAGNOSE_DIRECTION=<that direction>`. Append the new sub-issue rows to the parent epic's decomposition table.
   - Append (or create) a `## Diagnose splits` section on the parent epic with one row per fork: `| <round> | <parent sub-issue> | <fork sub-issues> | <directions> |`. Increment the split counter in the section heading: `## Diagnose splits (count: <N>)`.
   - Dispatch the original diagnose teammate against direction[0] AND a teammate per fork sub-issue against its assigned direction. Each fork is a sibling, not nested; each pursues exactly one direction.
   - Do not advance to the next decomposition row until at least one fork (or the parent diagnose's round on direction[0]) returns `confirmed-root-cause`.
4. **`confirmed-root-cause`.** Codex named the cause from the repro alone. The orchestrator hands off.
   - Proceed with Steps 5c.1–5c.4 as normal: gating comment, transition `review` → `done`, advance the decomposition table to the next sub-issue (typically `implement-junior` for restoration / fix work, or `architect` if the cause is structural).
   - The next sub-issue body cites the diagnose artifact URL and quotes the codex `confirmed-root-cause` mechanism + file:line evidence verbatim. The implementer reads this; no re-investigation.

If the artifact is missing the `## CODEX VERDICT` section, treat as a stop-rule violation: post a comment on the sub-issue requesting the diagnose teammate to run `/codex --mode diagnose --hold-scope` and re-publish. Do not invent a verdict; codex's stamp is mandatory.

**Three-splits stop rule.** If the parent epic's `## Diagnose splits (count: N)` reaches 3 and no fork has returned `confirmed-root-cause`, fire runtime stop condition #6 (Three diagnose splits without convergence — see Stop rules below). Park the active sub-issues; escalate to spec/architect.
