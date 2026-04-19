# cc-time estimates doctrine — v1 spec

**Modality:** `/safer:spec`
**Source issue:** chughtapan/safer-by-default#104
**Research input:** chughtapan/safer-by-default#91 (HIGH @ 0.90, EXCELLENT)
**Status:** v1 draft.

---

## 1. Intent

Agents on this stack still produce single-scale, human-team effort estimates ("2 weeks", "4 hours") for tasks they will execute in CC + plugin time. The two scales differ by ~3×–100× across task types. Without a shared doctrine, every spec, plan, and review compounds the mismatch — `/safer:orchestrate` decomposes against the wrong unit; `/safer:architect` budgets against the wrong unit; user reads "2 weeks" and waits, when the work will land in 30 minutes. Add a fourth subsection to `PRINCIPLES.md → Artifact discipline` titled *"Estimates are in CC-time, not human-time"* that states the format rule, ships the 6-row compression table from gstack's `ETHOS.md:20-27`, names the per-modality row mapping, and resolves the open injection-vs-principle-only question for runtime enforcement. Output is a paste-ready subsection plus a routing recommendation for downstream skill edits.

---

## 2. Goals

1. Add one new subsection to `PRINCIPLES.md → Artifact discipline` titled *"Estimates are in CC-time, not human-time"*, sibling to *"GitHub is the record"*, *"Confidence is a first-class output"*, *"Write for the cold-start reader"*, and *"Durability — the stamina rule"*.
2. The subsection ships gstack's full **6-row** compression table verbatim (Boilerplate ~100×, Tests ~50×, Feature ~30×, Bug fix ~20×, Architecture ~5×, Research ~3×) with attribution to `gstack/ETHOS.md:20-27` and a "heuristic, not measured" disclaimer that mirrors `PRINCIPLES.md:39`.
3. The subsection mandates the format `(human: ~X / CC: ~Y)` for every effort estimate any modality emits — in spec docs, architect plans, orchestrator decompositions, review verdicts, status replies, PR bodies, escalation artifacts.
4. The subsection states one decomposition rule: pattern-match the task to its nearest row; for composite tasks (architect-plus-feature), sum the rows of the components and report each sub-estimate in `(human / CC)` form; do not collapse to a single row.
5. The subsection names the per-modality row mapping so any agent can infer its row without re-deriving it: spec ~2×, architect ~5×, research ~3×, investigate ~3×, spike ~5×, implement-junior ~30×, implement-senior ~30×, implement-staff ~20× (cross-module amortizes), review-senior ~50× (mechanical reading), verify ~50×, orchestrate (sum of children, with overhead row), stamina (N × the row of the artifact under pass).
6. The subsection ships an explicit anti-pattern list that names single-scale estimates ("2 weeks") with no CC equivalent as a Principle violation, and pattern-matching-thinking-time-tasks-to-Feature as the specific failure mode the gstack 4-row preamble subset created.
7. Resolve the injection-vs-principle-only question (Spec deliverable point 3) with a recommendation that names which downstream skills, if any, get a per-skill preamble inject and which rely on Principle 0's once-per-session PRINCIPLES read.
8. The subsection is paste-ready: an `/safer:implement-senior` agent picks up this spec, opens `PRINCIPLES.md`, locates the artifact-discipline section, and inserts the subsection without further authoring decisions.

---

## 3. Non-goals

1. **No measurement of safer-by-default's own compression factors.** The numbers are heuristic; calibration is a future Principle 6 (compute budget) call, not 2026-Q2 work.
2. **No new principle.** This is an artifact-discipline subsection, not a 9th principle. The 8-principle taxonomy stays. (Research Round 4 ruled out Option A for this exact reason.)
3. **No standalone `safer-estimate` binary.** Estimation is a formatting convention, not a computation. Research Round 4 rejected Option D as fiction-or-ceremony.
4. **No copying of gstack's full ETHOS.md.** Borrow the table only. The surrounding rationale (Golden Age, Boil the Lake) is gstack's voice, not ours.
5. **No retroactive editing of existing artifacts.** Past specs, plans, and PR bodies stay as written. The doctrine binds outputs from merge-forward.
6. **No CI lint on estimate format in this spec.** Lint-level enforcement (gstack's `review/checklist.md:91` equivalent) is a follow-up `/safer:architect` decision, not v1 scope.
7. **No revision of the existing debt-multiplier table.** It is the structural precedent (`PRINCIPLES.md:31-37`) but it stays as-is — different axis (cost-over-time, not human-vs-CC).
8. **No row-by-row argument with gstack's numbers.** Adopt as-is per Research Round 5; revisit only if measured data later contradicts.

---

## 4. Invariants

1. **The 6-row table is canonical; no truncated subset ships anywhere.** Gstack's 4-row preamble subset is the failure mode this spec corrects. Any future inject must carry all 6 rows or none.
2. **Format `(human: ~X / CC: ~Y)` is symmetric.** Both scales appear, in that order, with `~` retained. `(human / CC)` without `~` is wrong; `(CC / human)` is wrong; either side alone is wrong.
3. **Attribution is one line.** The subsection cites `gstack/ETHOS.md:20-27` in one footnote-style sentence, not a paragraph. Mirror the `PRINCIPLES.md:39` disclaimer voice.
4. **Per-modality mapping lives in the subsection itself.** It does not get pushed to per-skill SKILL.md files. One read of PRINCIPLES suffices.
5. **The decomposition rule names composite tasks explicitly.** Otherwise an agent given an architect-plus-feature task pattern-matches to one row and underestimates the thinking-time component (the gstack Architecture-row drop in flagrante).
6. **The subsection is shorter than the existing siblings on average.** Artifact discipline is a tight section; the new subsection is at most ~25 lines of running text plus the 6-row table. Length budget: comparable to *"Confidence is a first-class output"* (`PRINCIPLES.md:280-289`).
7. **The doctrine binds every modality, not just the effort-producing ones.** Even `verify` reporting "took 5 minutes" emits `(human: ~30 min / CC: ~5 min)`. Symmetry has no exceptions.
8. **The doctrine cannot be inferred from existing PRINCIPLES.md.** This is what makes it doctrinal-not-mechanical — without the new subsection, the next agent will continue to emit single-scale estimates because the corpus default is single-scale.

---

## 5. Acceptance criteria

### 5.1 — Subsection text exists and is paste-ready

- [ ] `PRINCIPLES.md` contains a new subsection under `# Artifact discipline` titled `## Estimates are in CC-time, not human-time`.
- [ ] The subsection appears between `## Write for the cold-start reader` and `## Durability — the stamina rule`, preserving the existing within-section order (least-to-most procedural).
- [ ] The first line of the subsection is a one-sentence rationale stating *why* both scales appear (decomposition + user expectation, not status posturing).
- [ ] The 6-row table appears with exactly these rows, in this order: Boilerplate / scaffolding, Test writing, Feature implementation, Bug fix + regression test, Architecture / design, Research / exploration.
- [ ] The table columns are: `Task type`, `Human team`, `CC + plugin`, `Compression`. Values match `gstack/ETHOS.md:20-27` exactly.
- [ ] A one-line attribution follows the table: `Source: gstack/ETHOS.md (in-tree mirror at ~/.claude/skills/gstack/ETHOS.md:20-27); heuristic, not measured.`
- [ ] The format rule appears as a single inline sentence: `Every effort estimate is written as (human: ~X / CC: ~Y).`
- [ ] The decomposition rule appears as one paragraph: pattern-match to nearest row; composite tasks sum component rows and report each sub-estimate.
- [ ] The per-modality mapping appears as a small table or bulleted list keyed by modality name.
- [ ] An anti-patterns block ends the subsection, mirroring the voice of the existing artifact-discipline anti-patterns (`PRINCIPLES.md:278, 289, 297`).

### 5.2 — Per-modality mapping is exhaustive

- [ ] The mapping covers all 11 rows of the modality shape table (`PRINCIPLES.md:196-208`): spec, architect, implement-junior, implement-senior, implement-staff, investigate, spike, research, review-senior, verify, orchestrate.
- [ ] `stamina` (the dispatcher) is named separately as `N × the row of the artifact under pass`.
- [ ] Thinking-time-heavy modalities (spec, architect, research, investigate, spike) are mapped to rows 5-6 (~5×, ~3×) with one-line reasoning.
- [ ] Mechanical modalities (implement-junior, implement-senior, review-senior, verify) are mapped to rows 1-4 (~20× to ~50×) with one-line reasoning.
- [ ] `orchestrate` is mapped to "sum of children plus a small overhead row," not a single compression number.

### 5.3 — Anti-pattern coverage

- [ ] The anti-pattern list names *single-scale estimates* ("2 weeks" with no CC equivalent) as a Principle violation.
- [ ] The anti-pattern list names *pattern-matching a thinking-time task to the Feature row* as the specific failure mode that gstack's 4-row preamble subset produced. Cite the failure mode by name.
- [ ] The anti-pattern list names *collapsing a composite task to one row* (architect-plus-feature reported as one Feature estimate) as the third failure mode.
- [ ] Each anti-pattern mirrors the *italicized one-line* style of the existing artifact-discipline anti-patterns.

### 5.4 — Injection question is resolved

- [ ] The spec body contains an explicit recommendation on the injection-vs-principle-only question (Open Question 1 below).
- [ ] The recommendation cites Research Round 4's argument that no resolver exists in safer-by-default and building one is spike-plus-build work.
- [ ] If the recommendation is "principle-only," the spec states the assumption that Principle 0 ("Read this once per session," `PRINCIPLES.md:23`) is sufficient and names the failure mode that would invalidate the assumption (agents skipping the read).
- [ ] If the recommendation is "principle-plus-targeted-inject," the spec names the exact list of skills that get the inject and why each one needs it beyond the once-per-session PRINCIPLES read.

### 5.5 — Routing handoff

- [ ] The spec ends with a "next modality" line stating `/safer:implement-senior` (cross-module: PRINCIPLES.md edit + 0-to-N skill SKILL.md edits depending on §5.4 resolution).
- [ ] Confidence on the where-it-goes (HIGH) and on the injection call (MED, with the open question called out) are stated explicitly.

---

## 6. Assumptions

1. **Gstack's compression table is doctrinal, not provisional.** The numbers will not be revised in the next quarter; downstream skills can cite them without staleness risk. (Confirm with user; if revision is imminent, the cite-and-mirror strategy needs an adjustment.)
2. **The artifact-discipline section is the right home, not Voice or a new top-level section.** Research Round 4 selected this; the spec inherits the choice without re-litigating. (Confirm structurally; one alternative — extending the Voice section — was not in research scope.)
3. **Principle 0 ("Read this once per session," `PRINCIPLES.md:23`) is operationally enforced.** Agents do read PRINCIPLES at session start with high reliability, such that a doctrine-only-in-PRINCIPLES intervention reaches them. (Confirm via skill audit; if observed compliance is low, recommendation in §5.4 changes.)
4. **The 11-row modality shape table is the authoritative list of modalities.** Any mapping covering all 11 plus stamina is exhaustive. (Confirm; if `design-module` Tier 2 is imminent, mapping needs a 12th row.)
5. **The user prefers terse paste-ready output over an extended argument.** Subsection length matches sibling subsections; rationale lives in the spec doc, not in the subsection itself. (Confirm preference; if expansive prose is wanted, length budget in Invariant 6 changes.)
6. **No CI lint on estimate format ships in v1.** Per Non-goal 6. (Confirm; if user wants the lint in scope, a separate `/safer:architect` round opens.)
7. **The 6-row table needs no row insertions for safer-by-default-specific modalities.** Research Round 5 mapped all 15 of our skills to existing rows; the spec inherits that conclusion. (Confirm; if `/safer:stamina` deserves its own row scaling with N, see Open Question 2.)

---

## 7. Open questions

### Q1 — Injection vs. principle-only

**Q:** Does this doctrine ship as a PRINCIPLES.md subsection only, or also as a per-skill preamble injection (gstack's `generateCompletenessSection()` model) for some subset of effort-producing skills?

**Options:**
- **A — Principle-only.** Add the subsection to PRINCIPLES.md; rely on Principle 0's once-per-session PRINCIPLES read; ship no inject. Zero infra to build, lowest drift risk, mirrors how *Confidence is a first-class output* operates today (no preamble inject; per-skill convention).
- **B — Principle-plus-targeted-inject.** Add the subsection to PRINCIPLES.md *and* build a small inject helper that prepends the format rule + 6-row table + per-modality row to the SKILL.md preamble of effort-producing skills (spec, architect, orchestrate, stamina, plus the four implement-* skills). Higher infra cost (build a resolver-like helper or hand-edit ~8 SKILL.md files); recreates gstack's drift exposure if the subsection in PRINCIPLES and the inject diverge.
- **C — Principle-plus-hand-mirror.** Add the subsection to PRINCIPLES.md *and* hand-copy the format rule (just one sentence) into the SKILL.md "Read first" section of the same ~8 effort-producing skills. No resolver to build; one-line drift surface per skill is small enough to audit by hand.

**Recommended default: A (Principle-only).** Rationale:
1. **Precedent.** *Confidence is a first-class output* and *Write for the cold-start reader* both operate principle-only today and have not produced widespread compliance failures. CC-time estimates is structurally identical (formatting convention, not workflow).
2. **Infra cost.** No resolver exists; Research Round 4 explicitly priced building one as spike-plus-build (the exact ground for rejecting Option C in research). Option B inherits that cost.
3. **Drift risk.** Option B recreates the gstack 4-row preamble drift in our codebase. Once two copies of the table exist, one will lag. Principle-only keeps a single canonical source.
4. **Reversibility.** A is the smallest possible step. If observed compliance is poor in 4-8 weeks of merged PRs, escalate to C (one-sentence mirror per skill — additive, low-friction). Skipping straight to B is premature optimization.

**The case against A** is real and worth naming: agents under tight context budgets sometimes skip the PRINCIPLES read, especially in re-entry from `/compact`. If the format rule is invisible in the SKILL.md preamble, those agents emit single-scale estimates and the doctrine fails silently. Option C costs ~8 single-line SKILL.md edits and closes that gap without building infrastructure.

The reason to choose A over C anyway: *if compliance is the failure mode we are protecting against, then `Confidence is a first-class output` and `Write for the cold-start reader` should also be inject-mirrored, and they are not.* Either we add C-style mirrors for all three sibling subsections in one round, or we trust Principle 0 for all three. Asymmetric mirroring is the worst outcome — it implies CC-time is more important than the other two, which is not the user's stated priority.

**Resolution path.** Spec ships with **A as the recommended default**, MED confidence. User confirms or overrides at the spec-review gate. If user picks C, follow-up `/safer:implement-senior` round handles the 8 SKILL.md mirror lines under one PR.

### Q2 — Stamina row

**Q:** Does `/safer:stamina` (the fan-out dispatcher) get its own row in the per-modality mapping, or is it expressed as `N × the row of the artifact under pass`?

**Options:**
- **A — Computed (`N × artifact-row`).** Inherit the row from whatever the artifact is; multiply by N. Matches the existing `stamina is N heterogeneous passes` framing (`PRINCIPLES.md:305-306`).
- **B — Standalone row at `~10×`.** Treat stamina as a meta-modality with its own compression. Adds a 12th row to the mapping; loses the dependence on what is being staminated.

**Recommended default: A.** Stamina's compression literally is N times the artifact's compression. Inventing a fixed number obscures that. Adopt `N × artifact-row` and call it out in the mapping with one example (`stamina on an architect doc with N=3 → ~5× × 3 = 15× compression of the equivalent N=3 human-team review pass`).

### Q3 — Composite-task example

**Q:** Does the decomposition rule paragraph need a worked example, or is the rule self-evident?

**Options:**
- **A — Rule only.** One-paragraph rule, no example. Matches the terseness of the sibling subsections (none of them ships an example).
- **B — Rule plus one example.** Add one inline example (`/safer:implement-staff` task spanning architect-plus-feature → report `(human: ~2 days / CC: ~4 hours)` for the architecture component plus `(human: ~1 week / CC: ~30 min)` for the feature component, not a single combined estimate). Costs 2-3 lines.

**Recommended default: B.** The existing artifact-discipline siblings are all about *what to write*; CC-time estimates is about *how to compute*, which is the only place where one example is genuinely load-bearing. Sibling-subsection terseness is a stylistic floor, not a ceiling.

---

## 8. Confidence

- **HIGH** on subsection placement, table content, format rule, anti-pattern shape. Research Round 4-5 settled these with reproducible evidence; spec inherits.
- **MED** on injection-vs-principle-only (Q1). Recommendation defended above; user override expected at spec-review.
- **HIGH** on routing: `/safer:implement-senior` is the right downstream modality (cross-module PRINCIPLES + ≤8 SKILL.md edits depending on Q1 resolution; not implement-junior because the change is doctrinal-not-mechanical).

## 9. Next modality

`/safer:implement-senior` — apply the PRINCIPLES.md edit; if Q1 resolves to C, also apply the per-skill one-line mirror to the 8 effort-producing skills in the same PR.
