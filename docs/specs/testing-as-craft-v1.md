# testing-as-craft — v1 spec

Source: sbd#68. Modality: `/safer:spec`. Downstream routing: `/safer:implement-senior` (PRINCIPLES + typescript-skill edits) + `/safer:orchestrate` (per-repo follow-up queue).

Confidence (overall): **MED-HIGH**. Audit evidence is HIGH. Doctrinal choice (a vs b vs c) is MED-HIGH. Exact wording of the expanded corollary is MED (iteration expected in implement-senior).

---

## 1. Intent

> "Spec should handle this. It should go through the whole code base and figure out how testing is being wired through. It's an important part of our craft things."
> — user, 2026-04-18

Testing doctrine is implicit today. Principle 1 carries a one-line corollary — *"Tests exist for constraints the type system could not encode"* (sbd PR #47) — and `skills/typescript/SKILL.md` carries 14 testing rows (sbd PR #45). Research at sbd#32 produced the evidence. None of it is first-class in PRINCIPLES.md. The four repos downstream (sbd, acg, ccj, zap) each wire testing differently, with gaps that are traceable to the absence of a principle-level anchor.

## 2. Goals

1. Produce an auditable snapshot of testing wiring across sbd, acg, ccj, zap as of 2026-04-18.
2. Decide whether testing craft warrants principle-level codification in PRINCIPLES.md, and if so, at what shape: expand the existing corollary, add a 9th principle, or leave PRINCIPLES alone and strengthen decision tables.
3. Produce the full markdown text of the proposed PRINCIPLES.md change (if any) and of the affected `skills/typescript/SKILL.md` rows, ready for `/safer:implement-senior` to apply.
4. Name, per-repo, the concrete testing wiring that is missing and size each item as junior or senior.

## 3. Non-goals

1. Writing any code. Spec only.
2. Running `pnpm test`, `pnpm mutation`, Stryker, fast-check, or Playwright as part of the audit. Read PR history + config files + source.
3. Choosing between specific mutation-testing libraries. Stryker is already adopted repo-wide.
4. Re-opening the research question closed at sbd#32. That research is ground truth.
5. Changing `/safer:setup`'s opt-in posture. The user clarification on 2026-04-18 (closing sbd PR #60) is explicit: setup stays opt-in; aggressive installs are per-repo judgement, not a universal setup-skill flip.
6. Expanding scope to consumers outside the four in-house repos (acg, sbd, zapbot, cc-judge). The aggressive-install direction applies to our repos only.
7. Editing PRINCIPLES.md or `skills/typescript/SKILL.md` in this PR. This spec designs the edit; `/safer:implement-senior` writes it.

## 4. Invariants

- I1. **Tests are residual, not primary.** Every constraint that can live in the type system lives there first; testing is what types cannot encode. Derived from Principle 1.
- I2. **Mocks at the integration boundary are a lie.** Integration tests hit the real dependency (testcontainers, real HTTP, real file system). Derived from Principle 2.
- I3. **Coverage % is not a CI gate.** Coverage is diagnostic; gating it is Goodhart-broken (Inozemtseva & Holmes ICSE 2014). Mutation score is the test-your-tests check for critical modules.
- I4. **Tools are installed by per-repo judgement, not by universal default.** A linter does not need Playwright; a Docker-less repo does not need testcontainers; every repo needs fast-check for pure-with-algebraic-property code paths; every repo with a critical module needs Stryker gating CI.
- I5. **If tests exist, CI runs them.** A repo with `test/**/*.test.ts` and no `test` job in CI is shipping decoration, not tests.

## 5. Acceptance criteria

- [ ] `/safer:implement-senior` can apply the proposed PRINCIPLES.md edit and the proposed typescript-SKILL.md row updates from this doc alone, with no additional clarification round.
- [ ] `/safer:orchestrate` can decompose the per-repo follow-up backlog into sub-issues with the modality + confidence stated here.
- [ ] The audit tables (§6) are concrete: file path, line range or PR number, and explicit "present / absent / in-flight" status per dimension.
- [ ] The doctrinal choice is argued on both sides (a/b/c) before one is picked.
- [ ] Every open question lists a recommended default.

---

## 6. Part 1 — Audit of current state

### 6.1 Dimensions

Seven audit dimensions, from sbd#68:

1. Test runners in use.
2. Property-based coverage (fast-check, what properties, what gaps).
3. Mutation testing (Stryker config, CI gating status).
4. Integration / real-dep testing (testcontainers, real HTTP, Docker).
5. Contract / schema testing (boundary decode).
6. Coverage reporting (diagnostic-only; never a gate).
7. Fuzzing (Jazzer.js or equivalent).

### 6.2 Per-repo tables

#### sbd (safer-by-default) — bash plugin, no TypeScript

| Dim | State | Evidence |
|---|---|---|
| Runner | Custom `tests/run-tests.sh` (bash) | `tests/run-tests.sh`; 14 test files under `tests/test-bin/` + `tests/test-integration/` |
| Property | N/A (no TS; no fast-check analog chosen for bash) | — |
| Mutation | N/A | — |
| Integration | `tests/test-integration/test-orchestrate-pipeline.sh` (end-to-end orchestrate-step simulation) | PR #30 |
| Contract | N/A (no cross-service boundary inside sbd) | — |
| Coverage | None | — |
| Fuzzing | None | — |
| CI | None (no `.github/workflows/`) | `ls .github/workflows` → not present |

**Notable gap.** Even though sbd is a bash/docs repo, it ships the doctrine that governs the other three. Its own test-suite runs on a developer's laptop, not in CI. A breakage in `bin/safer-publish` or `bin/safer-transition-label` would not be caught by any CI job today.

#### acg (agent-code-guard) — eslint plugin, TypeScript

| Dim | State | Evidence |
|---|---|---|
| Runner | `vitest` (`"test": "vitest run"`) | `package.json` |
| Property | fast-check wired; **1 file, 3 properties** | `tests/property/rule-correctness.test.ts` — P1 "no recommended rule fires on safe TS"; P2 "every rule fires on its anti-pattern across mutations"; P3 "fixer idempotence". PR #8. |
| Mutation | Stryker wired **and required CI gate**. Incremental cache + concurrency tuning in flight (PR #19). Local cold run 159s, warm 39s, score 72.57. | `stryker.config.js`; `.github/workflows/ci.yml` `mutation` job. PR #16 (merged), PR #19 (open). |
| Integration | None (plugin has no external deps to integrate against) | `find -name '*.integration.test.ts'` → 0 |
| Contract | None (plugin's consumers are tsx/mjs eslint configs; no schema) | — |
| Coverage | None wired | `grep -E '(coverage\|c8)' package.json` → 0 |
| Fuzzing | None | — |
| CI | `test` job + `mutation` job (both required on PR) | `.github/workflows/ci.yml` |
| Test count | 13 `.test.ts` files (12 rule tests + 1 property file) | 12 rules in `src/rules/`; 13 tests in `tests/` |

**Notable gap.** Properties cover rule-correctness shape (3 properties over 12 rules). The three principles-gap rules added in PR #5 (`no-raw-throw-new-error`, `no-test-skip-only`, `no-coverage-threshold-gate`) get example-based tests but are folded into P2's "fires on anti-pattern" sweep. No per-rule property was authored; the cross-rule property covers them. That is a legitimate compression choice, not a gap.

#### ccj (cc-judge) — eval harness, TypeScript

| Dim | State | Evidence |
|---|---|---|
| Runner | `vitest` (`"test": "vitest run"`) | `package.json` |
| Property | fast-check wired; **1 file, 4 properties** on `scenario-loader` | `tests/scenario-loader.property.test.ts` — P1 roundtrip, P2 `WORKSPACE_PATH_PATTERN` invariant, P3 duplicate-id tagged error, P4 malformed-input tagged error. PR #10. |
| Mutation | Stryker **wired but not gating**. Pilot score 6.53% on `src/core/scenario.ts` + `src/runner/index.ts` with `--ignoreStatic`. Below break threshold (50); posture is non-gating until test-import-direct-module is fixed. | PR #19 (open). Full-src instrument: 2219 mutants across 17 files. |
| Integration | testcontainers wired for `DockerRunner`. **1 integration test**, `tests/integration/docker-runner.integration.test.ts` — "start() yields a running container; stop() tears it down" | PR #18. |
| Contract | None (ccj emits `summary.md` + `results.jsonl` + `details/*.yaml`; no consumer under SLA) | — |
| Coverage | None wired | — |
| Fuzzing | None | — |
| CI | `check` job runs `lint`, `typecheck`, `test`, `build`. No mutation job. | `.github/workflows/ci.yml` |
| Test count | 7 `.test.ts` files (1 per module: cli, pipeline, scenario-loader, scenario-loader.property, report-emitter, trace-adapter, docker-runner.integration) | |

**Notable gaps.**
- Four `src/` module trees (`app/`, `core/`, `judge/`, `emit/`) have example-based tests but no property tests beyond `scenario-loader`. `judge/` in particular, which parses LLM output, is an obvious fast-check candidate (oracle-agreement property against a stubbed judge).
- Stryker pilot score 6.53% is a symptom, not a disease: pipeline/CLI tests import the composition root, not the per-module exports, so `vitest --related` under `@stryker-mutator/vitest-runner` does not find tests for leaf modules. Fix: write leaf-module-level tests or disable `vitest.related`. PR #19 calls this out as out-of-scope for the wiring PR.
- `DockerRunner` is the only code path with an integration test. `trace-adapter` writes to real files — arguably an integration boundary — and has an example-based test only.

#### zap (zapbot) — webhook bridge + gateway, TypeScript

| Dim | State | Evidence |
|---|---|---|
| Runner | `vitest` (`"test": "vitest run"`) | `package.json` |
| Property | fast-check wired; **1 file, 4 properties** on `verifySignature` (HMAC) | `test/verify-signature.property.test.ts` — P1 "accepts any correctly-signed payload"; P2 "rejects a mutated signature"; P3 "rejects a mutated body"; P4 "rejects a mutated secret". PR #118. |
| Mutation | Not wired. zap#115 queued (`safer:implement-senior`) blocked on v2 churn subsiding. User direction flipped to default-install. | zap#115 (open). |
| Integration | None (v2 has no DB; testcontainers intended-but-skipped). HTTP integration via real fastify in `v2-bridge.http.test.ts` (same-process server). | PR #117 queued agent-code-guard lint install. |
| Contract | None (zap consumes GitHub webhooks; no internal cross-service boundary) | — |
| Coverage | None wired | — |
| Fuzzing | None | — |
| CI | **`lint` only**. No `test` job. 16 test files exist but CI runs none of them. | `.github/workflows/lint.yml` |
| Test count | 16 `.test.ts` files across `test/`, `gateway/test/`. 1 is property-based; 1 is in-process HTTP. | |

**Notable gaps.**
- **I5 violation:** CI does not run the 16 test files. Every merge ships untested. This is the highest-severity gap found by the audit; it trumps Stryker or property-coverage gaps because it renders the rest of the test layer decorative.
- `mention-parser`, `github-state`, `bridge` are all pure transforms with nameable algebraic properties (idempotence, roundtrip against canonicalized input). None has a property test yet.
- Stryker is queued but blocked on v2 rewrite landing.

### 6.3 Rollup

| Dim | sbd | acg | ccj | zap |
|---|---|---|---|---|
| Test runner | bash | vitest | vitest | vitest |
| fast-check | N/A | ✅ 3 props / 12 rules | ✅ 4 props / 1 module | ✅ 4 props / 1 module |
| Stryker wired | N/A | ✅ | 🟡 PR #19 open (pilot) | ❌ zap#115 queued |
| Stryker CI gate | N/A | ✅ required | ❌ non-gating pilot | ❌ not wired |
| testcontainers | N/A | N/A (no external dep) | ✅ DockerRunner only | ❌ (intentional — no DB) |
| Contract / Pact | N/A | N/A | N/A | N/A |
| Coverage report | ❌ | ❌ | ❌ | ❌ |
| Fuzzing | ❌ | ❌ | ❌ | ❌ |
| CI runs tests | ❌ (no CI) | ✅ | ✅ | ❌ lint only |

**The repo-wide reading.** fast-check is adopted (four repos × one property file each on the first critical module). Stryker is adopted in one repo, in-flight in another, queued in the third. testcontainers is used where a real dep exists. Coverage % is uniformly not gated, which matches doctrine. Two I5 violations exist: sbd runs tests only locally; zap runs lint-only in CI and skips its test suite entirely. These are not subtle gaps — they are the difference between "we have tests" and "our tests run."

### 6.4 What the audit is *not*

- Not a statement about test quality. Mutation score is the signal for that, and Stryker is mature in one repo only (acg, 72.57).
- Not a statement about coverage percentage in any repo. Coverage is diagnostic; no repo reports it, which matches doctrine.
- Not a statement about what properties *should* cover. That's a per-module judgement call for the implementer.

---

## 7. Part 2 — Doctrinal codification

### 7.1 The choice

Three options (from sbd#68):

- **(a)** Expand the Principle 1 corollary to cover: residual-as-property, mutation-as-tests-about-tests, coverage-as-Goodhart, CI-runs-tests.
- **(b)** Promote testing to a 9th principle — *"Prove the invariant."*
- **(c)** Leave PRINCIPLES.md alone; strengthen `skills/typescript/SKILL.md` decision tables.

### 7.2 The argument

**For (a) — expand the corollary.**
- Preserves the 4+4 architecture of PRINCIPLES.md ("Use your powers" + "Stay in your lane"). The 8-principle structure is load-bearing culturally — the document's own meta-shape tells the agent what kind of thinking each principle is.
- Matches the actual agent decision moment. The agent is writing a `.ts` file; it consults `skills/typescript` for "what to write" and is anchored by Principle 1 for "why types first." Testing shows up when types are exhausted. A corollary under Principle 1 is where testing naturally lives in that mental flow.
- Research sbd#32 already chose this direction (row 13 of its deliverables: a one-line corollary). PR #47 landed it. The audit shows the one-liner is correct but not sufficient — agents still shipped a lint-only CI in zap and a 6.53% Stryker pilot in ccj.
- Expanding (not rewriting) is reversible. If 2026-Q3 brings a new testing dimension that doesn't fit, the corollary can either extend further or lift into its own section without invalidating its anchor.

**Against (a).**
- Corollaries are small real-estate. Four claims (residual/mutation/coverage/CI-gate) strain the format. May feel like a checklist hiding under a heading.
- Testing is cross-cutting; pinning it under "types" may understate that it interacts with Principle 2 (validation), Principle 3 (typed errors → tested error paths), Principle 4 (exhaustiveness → property-based sweeps). The corollary form can feel subordinate rather than interacting.

**For (b) — 9th principle "Prove the invariant."**
- Testing becomes first-class. One principle can carry all four claims (residual/mutation/coverage/CI-gate) without crowding.
- First-class naming lets skills reference the principle directly ("per Principle 9"), which is a stronger anchor than "per Principle 1 corollary."
- Captures the interaction with principles 1-4 explicitly: testing is the meta-check that the types/schemas/errors/exhaustiveness machinery actually holds.

**Against (b).**
- Breaks the 4+4 symmetry. Principles 1-4 are "use your powers" (craft at the type level); 5-8 are "stay in your lane" (scope). A 9th principle does not fit either half. The Part 1 / Part 2 framing would need to break or absorb it, and both options visibly distort PRINCIPLES.md's current pedagogy.
- Testing as "a 9th peer" overstates it. Every claim in the proposed 9th principle is *downstream of* Principle 1's residual framing. Making it a peer would invert the priority the rest of the doctrine establishes ("types first, tests for the residue").
- The SDS / compiler-is-a-new-era analogy underpinning Part 1 does not cleanly extend to testing. Compilers don't test their output; they produce it. Testing is a different mental model.

**For (c) — leave PRINCIPLES alone; strengthen decision tables.**
- Decision tables are what agents actually read when writing code. `skills/typescript/SKILL.md` lines 106-119 already carry 14 testing rows (PR #45). A 15th, 16th, 17th row is cheap.
- PRINCIPLES.md has stayed stable through the last three doctrine rounds. Changing it is high-blast-radius; changing a skill is not.

**Against (c).**
- Skills drift. The audit has two pieces of evidence: zap shipped a lint-only CI, and ccj shipped a non-gating Stryker pilot. Both are skill-level drift that a principle-level anchor would have caught at review time. *"Per Principle 1 corollary"* is a reviewer's reach-point; *"per decision-table row 17"* is not.
- Decision tables are operational. Principles are doctrinal. The gap the audit reveals is doctrinal (what tests exist *at all*, whether CI runs them) — not operational (which library).

### 7.3 The pick

**Pick (a): expand the Principle 1 corollary.**

Confidence: **MED-HIGH**. The argument for (a) is load-bearing: the 4+4 architecture is the document's pedagogy, and testing-as-residual is the natural shape under Principle 1. The research at sbd#32 pre-chose this path; the audit shows the one-liner is correct but too thin. The fix is to expand, not to restructure.

Why not (b): too big a structural change for a refinement that remains "residual after types." Testing is not peer with the four craft principles; it's the verification layer for them.

Why not (c): the audit produces positive evidence of skill-level drift that principle-level anchoring would have caught. `skills/typescript/SKILL.md` row 17 did not prevent zap shipping lint-only CI; a principle would surface in every review-senior pass.

### 7.4 Proposed PRINCIPLES.md edit

**Location.** Replace the current one-line corollary at the bottom of Principle 1 with an expanded corollary block, in the shape of the existing "Corollary: back-compat is not a default" under the debt-multiplier table (see PRINCIPLES.md lines 45-51).

**Current text (to be replaced):**

```markdown
**Corollary.** *Tests exist for constraints the type system could not encode.* Move the encodable ones into types first; the residue is what testing is for.
```

**Proposed text (full markdown, as-it-would-appear):**

```markdown
### Corollary: tests are the residual, and the residual has a shape

*Tests exist for constraints the type system could not encode.* Move the encodable constraints into types first; the residue is what testing is for. That is the easy part. The shape of the residue is what doctrine has to name.

**1. If the function has a nameable algebraic property, the residual is a property, not an example.** Roundtrip, idempotence, invariant, oracle agreement — these are the four shapes to look for. A `fast-check` property is cheap to write in the agent era; an example test that asserts one hand-picked input is a compression of the same information, with lower coverage. Default to the property when a property exists.

**2. Coverage percentage is a diagnostic, never a CI gate.** Inozemtseva & Holmes (ICSE 2014) showed that coverage % correlates poorly with mutation-detection ability once you control for test count. Gating CI on 80% coverage is Goodhart-broken — it optimizes for line execution, not for the tests being tests. Report coverage as a comment or artifact; act on the *cause* of a gap (dead code, missing path, unreachable branch), not on the number.

**3. Mutation testing is the meta-check on the residual.** Coverage answers "did any test touch this line." Mutation answers "does any test fail when this line's behavior changes." For a critical module (auth, billing, parsing, crypto, webhook signing), Stryker + `@stryker-mutator/typescript-checker` is the only check that distinguishes a test from a decoration. Gate CI on it for the critical glob. Scope outside that glob is a Principle 6 (compute budget) call per repo.

**4. If tests exist, CI runs them.** A test file that CI never executes is decoration. A repo that runs `lint` in CI but not `test` is shipping a test suite that has not been verified to pass since the last developer ran it locally. The minimum floor for any repo with a test suite is a CI job that executes it.

**5. Mocks at the integration boundary are a lie.** This is Principle 2 applied to the test layer. An integration test that mocks the database is asserting that your code works against your mock, not against the real thing. Use `testcontainers` or the real dependency; reserve mocks for unit tests where the dependency is outside the boundary under test.

**Per-repo judgement, not universal default.** Installing every tool everywhere is the mirror-image error of installing nothing. A linter does not need `testcontainers`. A Docker-less CI does not need Playwright. Every repo with pure functions needs `fast-check`; every repo with a critical module needs Stryker gating CI; every repo with a DB/cache/queue needs `testcontainers` against the real client. The default is "ask what this repo actually has," not "install all five."
```

**Why five numbered items, not four or six.** Four captures the claims the audit surfaced (property-as-residual, coverage-as-diagnostic, mutation-as-meta-check, CI-runs-tests). Item 5 (integration mocks) is already embedded in `no-vitest-mocks` (lint rule) and Principle 2, but the audit did not surface any repo that violates it today, so a compressed reminder is sufficient. The trailing "per-repo judgement" paragraph codifies the 2026-04-18 user clarification that caused sbd PR #60 to be closed.

**Why under Principle 1, not at the top of PRINCIPLES.md.** Principle 1 is where "tests as residual" is framed. The corollary is the natural expansion point. Promoting it to its own section at the top would be equivalent to option (b), rejected above.

### 7.5 Proposed `skills/typescript/SKILL.md` row updates

The existing 14 testing rows (lines 106-119) were written before the 2026-04-18 user direction. Three rows need updating to reflect the aggressive-install posture on our four repos. All other rows remain as-is.

**Row 18 — mutation testing on a critical module.**

Current:
```
| Mutation testing on a critical module (auth, billing, parsing) | Skip, or run it everywhere | `@stryker-mutator/core` + `@stryker-mutator/typescript-checker`, opt-in per glob of named critical modules |
```

Proposed:
```
| Mutation testing on a critical module (auth, billing, parsing, crypto, webhook signing) | Skip, or run it everywhere | `@stryker-mutator/core` + `@stryker-mutator/typescript-checker`, **required CI gate**; scope the mutate glob to the critical module(s). Thresholds: `{ high: 80, low: 60, break: 50 }` as a starting point. |
```

**Row 19 — mutation testing repo-wide.**

Current:
```
| Mutation testing repo-wide | Run Stryker over every file | Scope Stryker to the critical-module glob only; compute budget is a Principle 6 constraint |
```

Proposed:
```
| Mutation testing repo-wide | Run Stryker over every file | Scope the mutate glob to named critical modules. When no critical module is named, the fallback is `src/**` with `ignoreStatic: true` and incremental mode on; compute budget (Principle 6) still caps full-sweep to nightly. PR runs use incremental. |
```

**Row 16 — coverage threshold as a CI gate.**

Current:
```
| Coverage threshold as a CI gate | `jest --coverage --coverageThreshold` set to 80% | Report coverage as a diagnostic artifact; never gate CI on a percentage (Goodhart; Inozemtseva & Holmes ICSE 2014) |
```

Proposed (strengthening — add the "what to do with the report" cross-reference):
```
| Coverage threshold as a CI gate | `jest --coverage --coverageThreshold` set to 80% | Report coverage as a diagnostic artifact only; **never** gate CI on a percentage (Goodhart; Inozemtseva & Holmes ICSE 2014). Gate CI on mutation score for critical modules instead (see row 18). Coverage gaps are investigated for cause (dead code? missing path?), not chased with filler tests. |
```

**New row — CI runs tests.**

Insert after row 17 ("Coverage report flags a gap in a module"):
```
| Repo has a `test/**/*.test.ts` suite | `"lint"` job in CI, run tests locally | CI runs a `test` job that executes the full suite on every PR. A lint-only CI with tests on disk is Principle 1 corollary item 4 violation: tests that do not run are decoration. |
```

### 7.6 What does NOT change

- The 11 other testing rows (rows 14-15, 17, 20-21, plus the earlier Pact/Playwright/testcontainers rows at 11-13) remain as authored in PR #45. They are consistent with the expanded corollary.
- `skills/setup/SKILL.md` keeps its opt-in posture with per-step `AskUserQuestion` prompts. Rationale: user clarification on 2026-04-18 (sbd PR #60 closing comment) — setup serves future consumers with different judgement; aggressive installs are per-repo, done by the repo's orchestrator, not by the universal setup skill.
- No new skill (`/safer:test` or equivalent) is proposed. Research sbd#32 closed that question; the audit does not re-open it.

---

## 8. Per-repo follow-up backlog

Each item lists the gap, the fix shape, and a modality sizing. Confidence per item.

### 8.1 sbd (safer-by-default)

| # | Gap | Fix | Modality | Confidence |
|---|---|---|---|---|
| sbd-T1 | No CI at all; `tests/run-tests.sh` runs only on a developer laptop. | Add `.github/workflows/ci.yml` with a single `bash tests/run-tests.sh` step. | `/safer:implement-junior` | HIGH |
| sbd-T2 | No property-analog for bash `bin/safer-*` (each script has an example test only). | Out of scope until a bash property-testing tool is adopted. Flag as open question, not a backlog item. | — | LOW |

### 8.2 acg (agent-code-guard)

| # | Gap | Fix | Modality | Confidence |
|---|---|---|---|---|
| acg-T1 | PR #19 (Stryker incremental + concurrency) open; ready to merge per its own test plan. | Land PR #19. | `/safer:review-senior` + merge | HIGH |
| acg-T2 | Coverage report not wired. Doctrine: diagnostic artifact only. | Add `vitest --coverage` producing `coverage/` as a CI artifact; no threshold. | `/safer:implement-junior` | HIGH |
| acg-T3 | 12 rules × 1 cross-rule property. No per-rule fast-check for `no-raw-sql` / `no-manual-enum-cast` where the input space has structure worth generating. | Spike: is a per-rule property useful, or is P2 sufficient? | `/safer:spike` (not `/safer:implement-*`) | MED |

### 8.3 ccj (cc-judge)

| # | Gap | Fix | Modality | Confidence |
|---|---|---|---|---|
| ccj-T1 | Stryker PR #19 pilot at 6.53%: vitest `--related` does not find tests for leaf modules. | Either (a) add leaf-module-direct-import tests for `runner/index.ts` et al, or (b) disable `vitest.related`. Pick (a) for signal. | `/safer:implement-senior` | HIGH |
| ccj-T2 | `judge/` parses LLM output; zero property coverage. Oracle-agreement property (pass a stubbed judge through and assert invariant). | Property test in `tests/judge/*.property.test.ts`. | `/safer:implement-junior` | MED-HIGH |
| ccj-T3 | `trace-adapter` writes real files; has example test only. | Promote to integration test or add property for path-handling invariants. | `/safer:implement-junior` | MED |
| ccj-T4 | No `mutation` job in CI. | Add `mutation` job **non-gating** until ccj-T1 closes; flip to gating after score crosses break threshold. | `/safer:implement-junior` | HIGH |

### 8.4 zap (zapbot)

| # | Gap | Fix | Modality | Confidence |
|---|---|---|---|---|
| zap-T1 | **CI does not run tests.** 16 test files; `lint` job only. | Add `test` job to `.github/workflows/` running `vitest run` on PR + push. | `/safer:implement-junior` | HIGH |
| zap-T2 | zap#115 (Stryker wiring, aggressive scope) blocked on v2 churn. | Unblock once PR #104 is stable; aggressive scope means `mutate: ["src/**", "v2/**", "gateway/src/**", "bin/**", "!**/*.test.ts"]` with `ignoreStatic` + incremental. | `/safer:implement-senior` (remains zap#115) | MED |
| zap-T3 | `mention-parser`, `github-state`, `bridge` are pure transforms with algebraic properties. No property tests. | One property file per module. Focus on `bridge` first (highest blast radius). | `/safer:implement-junior` (one per module, parallel-safe) | MED-HIGH |
| zap-T4 | Coverage report not wired. | Same as acg-T2: diagnostic artifact only, no gate. | `/safer:implement-junior` | HIGH |

### 8.5 Dispatch order

Highest-signal first: `zap-T1` (CI not running tests is the most expensive bug per the debt multiplier — Row 1 is 1×, Row 5 is 30-100×, and "no CI" is Row 5-equivalent). Then `acg-T1` (merge-ready). Then parallel: `ccj-T1`, `ccj-T4`, `zap-T2`.

---

## 9. Assumptions

1. `/safer:implement-senior` will apply PRINCIPLES.md + `skills/typescript/SKILL.md` edits in a single PR. The typescript-skill edits are sized-junior but couple doctrinally to the corollary, so the senior modality is correct.
2. The per-repo backlog items in §8 will be dispatched by `/safer:orchestrate` as separate sub-issues per repo, not batched into one cross-repo PR. Cross-repo PRs are not a shape this doctrine supports.
3. The 2026-04-18 user clarification ("super aggressive applies to our 4 repos, not universally; setup stays opt-in") is durable through at least the next two quarters. If it reverses, the per-repo-judgement paragraph in the corollary needs re-pitching.
4. No testing-adjacent tool is adopted in the next 30 days that would invalidate the doctrine (e.g., a new mutation-testing engine that replaces Stryker). If one is, the corollary is tool-agnostic; only the decision-table row names change.
5. Inozemtseva & Holmes (ICSE 2014) remains the correct citation for "coverage is not mutation score." If a 2025-2026 paper supersedes it, swap the citation; the claim stands.

## 10. Open questions

1. **Q: Does sbd itself need a CI job, given that it ships bash + docs only?**
   - Options: A) Yes — `bash tests/run-tests.sh` on PR; no matrix needed. B) No — tests are developer-local; CI would cost minutes for low signal. C) Yes, but behind a `changed-files` filter so CI skips doc-only PRs.
   - Recommended default: **A.** The floor (§invariant I5) is "if tests exist, CI runs them." `tests/run-tests.sh` is 60+ tests across bin + integration; not running them in CI leaves the 4-repo doctrine shipping on a vibes-check.

2. **Q: Does the corollary's item 3 ("mutation testing gates CI for critical modules") mandate mutation testing *for every repo*, or only for repos that name a critical module?**
   - Options: A) Mandatory for every repo; absent a critical module, the default scope is `src/**` with `ignoreStatic`. B) Mandatory only for repos that name a critical module; silent where none is named. C) Mandatory framework-level for the four in-house repos; open for external consumers of the doctrine.
   - Recommended default: **C.** The 2026-04-18 clarification is explicit that aggressive installs are per-repo judgement. For our four repos, the critical modules are identified (acg: each lint rule; ccj: `core/scenario`, `runner`, `judge`; zap: `verify-signature`, broker auth). For external consumers reading PRINCIPLES.md, option B's "only when named" is the right default.

3. **Q: Should the corollary name specific libraries (`fast-check`, Stryker, testcontainers, Playwright) or stay tool-agnostic?**
   - Options: A) Name them — matches current `skills/typescript/SKILL.md` body. B) Stay tool-agnostic — PRINCIPLES.md is durable, skills churn. C) Name one per claim (e.g., "mutation testing, such as Stryker") for readability without locking.
   - Recommended default: **B.** PRINCIPLES.md has been tool-agnostic through the rest of its body (Effect, Zod, Kysely appear only in skills). Testing deserves the same durability. The draft in §7.4 follows this: "fast-check" and "Stryker" appear once in item 1 and item 3 respectively; could be rewritten to "a property-based tester" and "a mutation testing tool" if the user prefers full neutrality. Recommend keeping the names for concreteness, matching the existing `Inozemtseva & Holmes` citation precedent.

4. **Q: Is a 5th item in the corollary (item 5 on integration mocks) worth including, given that no repo currently violates it?**
   - Options: A) Include — it's cheap and it matches the corollary's charter. B) Drop — `no-vitest-mocks` (lint rule) + Principle 2 already cover it; adding it to the corollary is redundant. C) Move it to a Principle 2 corollary instead.
   - Recommended default: **A.** The corollary is about what tests *are*; item 5 is the "don't write lies" floor. Redundancy with the lint rule is fine — PRINCIPLES.md frames, lints enforce. If the user prefers, drop and rely on Principle 2 + lint.

---

## Handoff

- `/safer:implement-senior` — apply §7.4 (PRINCIPLES.md corollary expansion) + §7.5 (three typescript-SKILL row updates + one new row). One PR; ≤100 lines of markdown.
- `/safer:orchestrate` — decompose §8 (per-repo backlog) into 9 sub-issues across 4 repos. Dispatch order per §8.5.
- Open questions in §10 route to user (for Q1 & Q4) or to `/safer:implement-senior` judgement at apply time (Q2 & Q3).

STATUS: `DONE_WITH_CONCERNS` — spec published; 4 open questions with recommended defaults; confidence MED-HIGH overall.
