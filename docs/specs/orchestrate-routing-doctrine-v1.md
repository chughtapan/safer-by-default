# Orchestrate routing doctrine v1

**Status:** spec (pre-implement)
**Branch:** `spec/routing-doctrine`
**Tracks issue:** https://github.com/chughtapan/safer-by-default/issues/87
**Route after approval:** `/safer:implement-senior` — one PR applies all three sub-systems to `skills/orchestrate/SKILL.md`.

---

## 1. SDS grounding

The doctrine operationalizes three claims in Anderson, Mahajan, Peter, Zettlemoyer, *Self-Defining Systems* (Dec 2025). The paper was pulled via `curl https://foci.uw.edu/papers/whitepaper2025-sds.pdf` and converted with `pdftotext`. Quotes are from that text; line numbers refer to `/tmp/sds.txt`.

### Claim A — Scope-limitation reduces junior-agent error rate (p.1, lines 50–53)

> "LLMs offer cheap (relative to a human) but buggy and approximate hypothesis and code generation, equivalent to having an army of inexpensive, tireless, and somewhat clueless junior developers. Industry already knows how to reduce the error rate of junior developers by limiting the scope and complexity of any assigned task."

Operationalization: **model routing.** Model capability is the clean proxy for "how much scope this modality owns." Junior scope (one module's internals) gets haiku; staff scope (new modules, new public surface) gets opus. Giving opus to a junior modality inflates scope by making more plausible the risky moves scope discipline exists to forbid.

### Claim B — Upstream-stage evaluation is coarse; backtracking is cheaper than late discovery (p.3, lines 144–150)

> "Evaluating the artifacts at upstream stages is more resource efficient but coarser … evaluation at a refinement stage informs future hypotheses at that stage as well as upstream stages (backtracking). … Architectures that are deemed poor are not fleshed out; and if an architecture that appeared promising earlier in the process later turns out to be too complex to implement, it is modified or discarded."

Operationalization: **codex routing.** Spec and architect are the upstream-stage refinements the SDS paper names. Their error propagates at the highest multiplier in the debt-multiplier table (row 4–5: 30–100x). A second independent model at the upstream stages is the cheap coarse filter the paper argues for — it catches the design errors before they cascade. Same argument for research-supervisor: each round's researcher output is an upstream artifact, evaluated by an independent model before influencing the next round.

### Claim C — Human code review is error-prone; complementary gates catch what review misses (p.6, lines 311–316)

> "Human code review and edge case analysis can be error prone. This has driven an increasing interest in the use of formal methods as a complement to more manual methods, to catch more of these types of errors before deployment. … lighter weight formal methods such as model checking have proven effective at reducing bugs and vulnerabilities in complex systems code."

Operationalization: **pre-PR gates.** `/simplify` is the lightweight-formal-methods analog for over-engineering: a mechanical scan across the diff for DRY violations, premature abstractions, and dead code. It is strictly cheaper than review-senior and catches a disjoint error class (structural smell, not correctness smell). Review-senior stays the human-style review pass; simplify stays the mechanical pass. Both fire; neither substitutes for the other.

### Claim D — Time-to-integration has collapsed; back-compat is no longer free (p.1, line 23; PRINCIPLES.md corollary)

> "Time to Integrate (TTI) for new use cases and technology integration efforts take days or weeks, instead of [faster timelines SDS targets]."

Operationalization: skill-doc updates are carrier artifacts, not public API. The doctrine revises freely in one PR rather than carrying piecemeal sub-issue state. The three closed sub-issues (sbd#77 merged, sbd#81 and sbd#85 closed unshipped) consolidate into a single design round rather than three serial junior edits.

### What the SDS paper does NOT say (honesty note)

The paper names backtracking, scope limiting, independent hypothesis evaluation, and reviewable-by-humans artifacts. It does **not** name:
- Cross-model review specifically (codex vs claude). The "independent-hypothesis" claim generalizes to cross-model, but that generalization is ours.
- `/simplify` as a gate. The "formal methods as complement" claim generalizes; the generalization is ours.
- A specific model-to-modality mapping. The capability-to-scope claim motivates the mapping; the specific rows (haiku/sonnet/opus) are our calibration.

Each of the three sub-systems in §3 marks which parts are direct-from-SDS vs our generalization.

---

## 2. Unified routing table

Eleven routes. Columns: **default model** (primary executor), **outside voice** (independent second-opinion channel), **pre-PR gates** (what runs before the PR opens or artifact publishes), **post-merge / post-publish gates** (what runs before a downstream modality trusts the artifact).

| # | Modality | Default model | Outside voice | Pre-PR gates | Post-publish gates |
|---|---|---|---|---|---|
| 1 | `safer:implement-junior` | haiku | — (scope too narrow) | — (optional `/simplify` if diff >50 LOC) | `/safer:review-senior` |
| 2 | `safer:implement-senior` | sonnet | — | **`/simplify` mandatory** | `/safer:review-senior` (or `/safer:stamina` if tier ≥ senior per existing Phase 5c) |
| 3 | `safer:implement-staff` | opus | **`/codex review`** on diff | **`/simplify` mandatory** (stricter framing) | `/safer:stamina` (N≥3 per existing Durability clause) |
| 4 | `safer:spec` | opus | **`/codex consult` review-after** | — | `/safer:stamina --plan` (existing Phase 5c) |
| 5 | `safer:architect` | opus | **`/codex consult` review-after** | interface-stub compile-check | `/safer:stamina --plan` (existing Phase 5c) |
| 6 | `safer:research` — Researcher | opus | — | — | Supervisor round-gate (see #7) |
| 7 | `safer:research` — Supervisor | **codex** | — | — | Researcher can't advance rounds without Supervisor sign-off |
| 8 | `safer:spike` | opus | — | branch stays unmerged | writeup reviewed against spike's yes/no question |
| 9 | `safer:review-senior` | opus | — | — | (is itself a gate) |
| 10 | `safer:verify` | opus | — | — | (is itself a gate) |
| 11 | `safer:investigate` | opus | — | — | root-cause writeup reviewed by orchestrator before routing to fix |

`safer:dogfood` is **not a routed modality** — it is an orthogonal acid test the orchestrator can invoke on any artifact. It pins to **haiku** for the reason sbd#77 gave: cold-read comprehension by a small model is the test for artifact portability, and upgrading the model masks the failure. It has no outside-voice or pre-PR column; it IS the test.

### Column-level argument

- **Default model.** Capability-to-scope. Claim A.
- **Outside voice.** Independent-hypothesis channel for upstream-stage error. Claim B. Only stamps on spec / architect / staff — the three rows whose errors are both highest-multiplier AND most design-shaped (where a second model disagrees most).
- **Pre-PR gates.** Mechanical simplify pass catches a disjoint error class from human review. Claim C. Senior + staff only; junior scope is narrow enough that the ratio is not worth the overhead.
- **Post-publish gates.** The existing orchestrate Phase 5c wiring. Listed here for completeness, not revised.

---

## 3. Per-sub-system design

Each sub-system states: the rule, the exact skill-level text to land, the exceptions.

### 3a. Model routing by modality

**Rule.** Every dispatch carries a `model:` parameter from the table in §2, column 3. Override only if the user explicitly names a different model. Dogfood stays on haiku permanently; upgrading dogfood to opus masks portability debt.

**Skill-level text.** sbd#77 merged text stands. No revision. The merged table at `skills/orchestrate/SKILL.md:607` is canonical.

**Exceptions.**
- User explicitly names a different model for a specific task → follow user.
- A scenario is large-context (>150K tokens) and sonnet fails → escalate one tier (sonnet → opus for senior; opus already has headroom for staff). Do not silently upgrade; log the override on the sub-issue.
- Test fixtures / CI runs that dispatch via fixtures — use the fixture's declared model.

**Direct-SDS share.** Claim A motivates capability-to-scope. The specific haiku/sonnet/opus mapping is our calibration, not the paper's.

### 3b. Codex routing — independent second-opinion channel

**Rule.** Two firm modes, one optional:

1. **Upstream-stage review-after** (spec, architect): primary model produces the artifact; `/codex consult --mode review` reads the published artifact and returns a verdict before the orchestrator transitions `review → plan-approved`. Two-pass: claude-draft → codex-review.
2. **Research supervisor** (research only): each round's researcher output is read by `/codex consult --mode supervisor` before the researcher dispatches the next round. Supervisor fails → researcher revises same round.
3. **Staff-diff review** (implement-staff): `/codex review` runs on the PR diff before the human review-senior pass. Optional for senior. Off for junior.

**Revision from sbd#81.** sbd#81 proposed **codex-first-draft** for spec/architect (codex writes, opus reviews). That is more aggressive than Claim B supports: the SDS paper argues for independent hypothesis evaluation, not independent hypothesis *generation*. Flipping the primary author switches the "buggy but cheap junior developer" frame onto the wrong axis — codex is an independent model, not a junior one. **Recommend review-after, not draft-first.** This is the single biggest deviation from sbd#81's closed draft and the central argument of §7 and §8.

**Skill-level text (new section in orchestrate SKILL.md, immediately after Model routing table).**

> **Codex dispatch pattern.** Three modes mirror gstack `/codex`:
> 1. **Review mode (spec, architect upstream stages):** claude drafts; codex reviews the published artifact before `review → plan-approved`. Verdict: `approve` / `changes-requested` / `reject`. `changes-requested` routes back to the drafting modality as one revision round; `reject` escalates to the user with codex's reasoning. Opus stays the primary author — the SDS paper's independent-hypothesis claim motivates independent *evaluation*, not independent *generation*.
> 2. **Supervisor mode (research):** per-round. Researcher output lands as a comment; codex reads and stamps `continue` / `hold` / `escalate` before the next round's dispatch. Breaks single-model groupthink on multi-round reasoning.
> 3. **Diff review mode (implement-staff mandatory; implement-senior optional):** codex reads the PR diff, independent of `/safer:review-senior`. Verdict posted as a PR comment before the human review fires. Counts as one independent pass toward the stamina N budget (PRINCIPLES.md → Durability).
>
> **Invocation:** use gstack `/codex` skill (wraps `codex` CLI). Do NOT import `@openai/sdk` or `codex` binary raw; the harness CLI is the routing boundary.
>
> **Budget.** Codex runs cost real time and real tokens. Review-after on spec/architect: one pass per artifact. Supervisor: one pass per research round. Diff review on staff: one pass per staff PR. No more; over-calling codex defeats the cost model.

**Direct-SDS share.** Claim B direct. The review-after vs draft-first choice (and the research supervisor framing) is our calibration.

### 3c. Pre-PR gates — `/simplify` mandatory for senior + staff

**Rule.** Before opening a draft PR, senior and staff implementers run `/simplify` on the diff. Apply all findings unless a specific finding would expand scope beyond the original spec. Skipped findings are annotated in the PR body with the reason. Junior is optional.

**Skill-level text (per-modality dispatch template additions).** sbd#85 closed text is correct. Land as-drafted, three template deltas:

- **senior template:** add "Pre-PR simplify pass" step between tests-green and PR-open.
- **staff template:** same, with stricter framing (every finding applied unless it conflicts with plan-approved decision).
- **junior template:** add optional note (if diff >50 LOC or introduces helpers, consider running).

**Exceptions.**
- `/simplify` finding conflicts with plan-approved architect decision → skip; cite plan line in PR body.
- `/simplify` finding would change public API → skip (out of senior/junior scope); file as follow-up.
- `/simplify` itself errors → fall through; note in PR body; reviewer decides whether to block.

**Direct-SDS share.** Claim C direct motivation. The specific tool choice (gstack `/simplify`) and the senior+staff-mandatory/junior-optional split are our calibration.

---

## 4. Conflict resolution

Rules interact. The resolution order below is strict; earlier rules dominate later ones.

1. **User override wins.** User explicitly names a model, skips a gate, or routes differently → follow. Log override on sub-issue.
2. **Scope discipline wins over capability upgrades.** If a scenario needs opus reasoning but the modality is junior, the modality is wrong — re-triage to senior per Principle 6 (Budget Gate). Never silently upgrade the junior's model; that hides the scope drift.
3. **Dogfood-on-haiku overrides artifact's model hint.** Dogfood IS the small-model test. If haiku cannot cold-read the artifact, the artifact has a portability bug; the answer is to fix the artifact, not upgrade dogfood.
4. **Codex unavailable falls through to claude-only.** If `/codex` is not installed or fails, the orchestrator proceeds without the codex pass and logs the skip on the sub-issue. This is a calibrated degradation, not a silent one. Cross-model coverage is a "durability-additive" gate, not a hard blocker — blocking all spec work on a third-party CLI failure is worse than missing one cross-model pass.
5. **Simplify finding conflicts with plan-approved architect decision.** Plan wins; skip finding; cite plan line in PR body. Principle 8 (Ratchet) — senior doesn't revise plan; file follow-up.
6. **Stamina N budget overlaps with codex + review-senior.** A codex diff-review pass and a `/safer:review-senior` pass on the same PR count as N=2 toward the stamina budget (independent roles: mechanical/cross-model vs human-style). They do not double-count as N=1.
7. **Gate failures are never silent.** Simplify errored, codex unreachable, review-senior did not fire: the orchestrator posts a gate-skip comment on the sub-issue with the reason. A reader opening the sub-issue sees the missing gate; a silent skip would lose that signal.

---

## 5. Cross-modality dispatch template updates

Seven templates in `skills/orchestrate/SKILL.md` (implement-junior, implement-senior, implement-staff, verify, spike, research, spec). Five of them change.

| Template | Model line | Codex line | Simplify line | Other changes |
|---|---|---|---|---|
| implement-junior | haiku (no change) | — | optional note added | none |
| implement-senior | sonnet (no change) | — | **mandatory step added** | none |
| implement-staff | opus (no change) | **mandatory codex-review step added** | **mandatory step added (stricter)** | precondition clause unchanged |
| verify | opus (no change) | — | — | none |
| spike | opus (no change) | — | — | none |
| research | opus for researcher; **new supervisor block** for codex | **supervisor role added** | — | per-round gate added |
| spec | opus (no change) | **codex review-after step added** | — | publish step gates on codex verdict |

No template is rewritten wholesale. Each change is additive text matching the existing placeholder schema (`{TEAM}` / `{ISSUE_URL}` / `{PARENT_URL}` / `{ACCEPTANCE}` / `{BRANCH_HINT}`). No new placeholders.

Architect does not have a dispatch template today (architect runs via `/safer:architect` directly, not via auto-dispatch). The codex review-after rule for architect lives in the architect SKILL.md, not in an orchestrate template. Flagged as open question §8.4 — if architect grows an auto-dispatch template later, the codex line copies from the spec template.

---

## 6. Rollout plan

One `/safer:implement-senior` PR. Scope is cross-module within this approved spec: edits to `skills/orchestrate/SKILL.md` and `skills/spec/SKILL.md` and `skills/architect/SKILL.md` and `skills/research/SKILL.md` and `skills/implement-senior/SKILL.md` and `skills/implement-staff/SKILL.md` (six skill files). No new modules; no new public interfaces; no new dependencies.

### What gets rewritten

- **`skills/orchestrate/SKILL.md`** — Model routing table kept as-is (already merged per sbd#77). New **Codex dispatch pattern** section added immediately after. Per-modality dispatch templates (5 of 7) get model/codex/simplify lines per §5. Conflict-resolution table from §4 added as a short section before the Anti-patterns.
- **`skills/spec/SKILL.md`** — Phase 5 (Publish) updates to gate on codex verdict before `planning → review`.
- **`skills/architect/SKILL.md`** — Publish phase updates to gate on codex verdict before `planning → review`.
- **`skills/research/SKILL.md`** — Per-round structure documents the Supervisor role and its gate.
- **`skills/implement-senior/SKILL.md`** — Pre-PR workflow adds simplify step.
- **`skills/implement-staff/SKILL.md`** — Pre-PR workflow adds simplify step + codex diff-review step.

### What stays

- `skills/implement-junior/SKILL.md` — no doctrine change. Optional simplify note lives in the orchestrate junior template, not in the junior skill.
- `skills/verify/SKILL.md` — no change.
- `skills/review-senior/SKILL.md` — no change. Review-senior is a gate, not a gated modality.
- `skills/dogfood/SKILL.md` — no change. Already haiku per sbd#77 merged.
- `PRINCIPLES.md` — no change. This doctrine operates within Principle 5/6/8; does not amend them.
- Test fixtures — no change. Existing `tests/run-tests.sh` is markdown-content-only; doctrine edits pass.

### Commit shape

One PR titled `[impl-senior] orchestrate routing doctrine v1: model + codex + simplify gates`. Six-file diff. Plan-anchor table in the PR body cites the spec's §5 table. `safer-diff-scope --head HEAD` should report `senior` (cross-module within approved spec; no new public surface).

### Verification after merge

- `bash tests/run-tests.sh` green.
- One dogfood run on the updated orchestrate skill: haiku reads the skill cold and correctly identifies the model / codex / simplify routing for a sample sub-issue. Dogfood failure = artifact unclear = senior revises.
- One self-test dispatch: orchestrate picks up a real sub-issue from the queue and emits the correct model + codex + simplify lines per the table.

---

## 7. Rejected alternatives

Each section names the alternative, the reason it was considered, and the reason it was rejected.

### 7a. Codex first-draft for spec/architect (sbd#81 original proposal)

**Considered:** codex writes the first draft of spec and architect artifacts; opus reviews and signs off. Puts the cross-model tension at generation time, not review time.

**Rejected because:** SDS Claim B is about independent *evaluation*, not independent *generation*. Flipping the drafter to codex switches the primary author from claude to OpenAI's model — which means the PRINCIPLES.md framing ("you are the new compiler … calibrated correctly …") stops applying to the drafter. The doctrine lives in claude; the review channel is codex. Draft-first breaks that invariant.

Also: codex draft quality on spec/architect tasks is untested in this repo. Review-after lets us benefit from cross-model coverage without staking the primary artifact on it.

### 7b. Per-repo model overrides

**Considered:** let each repo's `.safer/config.json` override the model column per modality. "acg senior uses opus; ccj senior uses sonnet."

**Rejected because:** the table is the doctrine. Per-repo overrides are how the doctrine turns into 15 variants nobody remembers. If a repo actually needs a different default, the honest move is to revise the table (for everyone) or to override inline per sub-issue (logged). Config-file sprawl is the failure mode.

### 7c. Skip codex on staff diffs

**Considered:** staff-tier work already gates on `/safer:stamina` with N≥3. Codex diff review is redundant.

**Rejected because:** stamina's N=3 counts three passes but does not enforce cross-model independence unless one of the passes IS cross-model. Codex review is the *designated* cross-model pass — without it, stamina can be three runs of claude-based reviewers, which PRINCIPLES.md → Durability → Independence explicitly warns against ("Two passes with the same role on the same model count as one pass"). Codex on staff is how stamina hits true N=3 instead of effective N=1.

### 7d. Gate on mutation score instead of review

**Considered:** Stryker mutation testing catches real bugs; expand its role as the post-merge gate.

**Rejected because:** mutation testing runs against a test suite that exists. The artifacts this doctrine gates (spec, architect, orchestrate SKILL.md) are skill-doc markdown — no mutation surface. Mutation testing is orthogonal to the doctrine; it lives on impl repos (acg / ccj / zapbot) and does not generalize to skill-doc gates. It is not a substitute for human + cross-model review.

### 7e. Dogfood on opus

**Considered:** upgrade dogfood to opus so the test is stronger.

**Rejected because:** dogfood is the *weaker* model test on purpose. A skill-doc that only opus can cold-read has a portability bug — the next agent picking it up may be haiku. Upgrading dogfood hides the bug. sbd#77 merged this argument; repeating the rejection here for completeness.

### 7f. Simplify mandatory for junior

**Considered:** run simplify on every PR regardless of tier.

**Rejected because:** junior PRs are scope-bounded by definition (one module's internals, small diffs). Simplify findings on those PRs are usually noise-level (the module is small enough that DRY violations haven't formed). Cost of running simplify on every junior PR exceeds benefit. Optional-at-author-discretion is the right ratio; senior+staff is where the value actually lives.

### 7g. Stamina as an explicit column in the routing table

**Considered:** add a fifth column showing stamina N per modality.

**Rejected because:** stamina N is not a routing decision — it is set by blast radius × reversibility per the existing PRINCIPLES.md → Durability table, which is modality-agnostic. Encoding it per-modality would duplicate and eventually drift. The Durability table stays the source of truth; this doctrine references it where relevant (§2 Post-publish column, §4 rule 6).

---

## 8. Open questions

Each question has `Q:`, `Options:`, `Recommended default:`.

### 8.1 Codex review-after vs consult-on-draft vs both

**Q:** For spec and architect, should codex see the full published artifact (review-after), or see a structured summary the drafter prepares (consult-on-draft), or both?

**Options:**
- A) Review-after on full artifact. One pass. Codex reads the same doc a human reviewer would read.
- B) Consult-on-draft. Drafter sends codex a summary + key decisions; codex challenges before finalization.
- C) Both. Consult-on-draft for early feedback, review-after for final sign-off.

**Recommended default:** **A**. One pass is the cheapest viable implementation and matches the SDS claim (coarse independent evaluation). C doubles the cost for marginal additional signal. B is a useful research direction but too much process for v1.

### 8.2 `/simplify` optional vs mandatory for senior when diff is <50 LOC

**Q:** Some senior PRs are tiny (one cross-module rename). Is the mandatory simplify pass worth it?

**Options:**
- A) Mandatory regardless of size.
- B) Mandatory only above a size threshold (e.g., >100 LOC or >3 files).
- C) Mandatory, with a "no findings, skipped" one-line acknowledgment when the pass returns empty.

**Recommended default:** **C**. The mandatory framing is the value — senior is always on the "yes, simplify ran" path. An empty result is a 10-second acknowledgment. Option B is how the rule erodes ("this one's under the threshold" becomes "this one's close enough").

### 8.3 Architect skill — does it auto-dispatch?

**Q:** Architect currently runs directly, not via an orchestrate template. If architect grows an auto-dispatch path, the codex review-after column applies — but does it today?

**Options:**
- A) No architect template in v1. Codex rule lives in `skills/architect/SKILL.md` only.
- B) Add architect template in v1 so the doctrine is uniform across all upstream modalities.

**Recommended default:** **A**. Architect auto-dispatch is out of scope for this doctrine. Adding it in v1 expands the implement-senior PR's surface. File as sbd follow-up.

### 8.4 Research supervisor model — codex or claude-opus with different prompt?

**Q:** Supervisor role could be a codex instance OR an opus instance with a different system prompt. Which is the actual independent-hypothesis channel?

**Options:**
- A) Codex. True cross-model.
- B) Opus with supervisor prompt. Same model, different role.
- C) Either (orchestrator picks based on availability).

**Recommended default:** **A**. PRINCIPLES.md → Durability → Independence is explicit: "Two passes with the same role on the same model count as one pass." Opus-with-different-prompt fails the cross-model test. If codex is unavailable, fall through (conflict rule §4.4) rather than substitute.

### 8.5 Dogfood cadence

**Q:** Does dogfood run on every skill-doc change, or only on doctrine-level changes?

**Options:**
- A) Every skill-doc PR.
- B) Only on PRs that touch dispatch templates, routing tables, or the orchestrate skill.
- C) At the author's discretion.

**Recommended default:** **B**. Dogfood on typo fixes wastes haiku-time and erodes signal. Dogfood on routing-doctrine PRs is exactly where it catches portability bugs. B is the cost-proportionate rule. Out of scope for v1 to codify; flag as sbd follow-up after v1 lands.

### 8.6 "Gate-skip" comment — who writes it?

**Q:** When a gate is skipped (codex unreachable, simplify errors, etc.), who posts the gate-skip comment on the sub-issue?

**Options:**
- A) The orchestrator auto-monitor loop.
- B) The implementing teammate at PR-open time.
- C) Whichever one notices first; dedupe via idempotency marker.

**Recommended default:** **B**. The implementer knows the gate failed at the moment it failed; the auto-monitor loop is a lagging detector. Write at the source. Idempotency marker prevents double-posting if the loop sweeps before the comment lands.

---

## Confidence

**HIGH** on the three sub-system designs (model, codex, simplify). Each is grounded in a direct SDS quote + a well-understood operationalization.

**MED-HIGH** on the unified routing table. 11 modalities listed; the three additive columns (outside voice, pre-PR gates, post-publish gates) are design calls, not paper-derived. Table is complete as-drafted; calibration of individual cells may shift during implementation.

**MED** on the open questions. Each has a recommended default; none is load-bearing for v1 ship.

## Summary

Three sub-systems, grounded in SDS Claims A/B/C. Unified table covers 11 modalities. Doctrine lives in the orchestrate skill + five other skill files. One implement-senior PR. Seven open questions with recommended defaults; flag 8.1 and 8.4 for user sign-off before implement-senior dispatches.

Route after plan-approved: `/safer:implement-senior`. Scope: six skill files. Estimated size: ~200 LOC of markdown additions across `skills/orchestrate/SKILL.md` + five sub-skills. No code changes. No new dependencies.
