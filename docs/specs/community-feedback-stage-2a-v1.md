# community-feedback Stage 2a — v1 spec

**Modality:** `/safer:spec`
**Source issue:** chughtapan/safer-by-default#90
**Research input:** chughtapan/safer-by-default#84 (HIGH, 8 rounds, EXCELLENT at 0.9)
**Status:** v1 draft.

---

## 1. Intent

Land Stage 2a of the multi-persona dogfood pipeline that sbd#84 prescribed: three new persona skills (`install-friction`, `cli-ergonomics`, `extension-attempt`) plus two new cc-judge axes (`install-friction`, `cli-ergonomics`). No orchestrator coordination, no aggregator, no release-gate — those are 2b and 3. Personas exist as standalone skills invokable by a human or by a future orchestrator. The cc-judge axes exist as schema-level enum extensions; scenario authoring against the new axes is downstream work, not 2a. Stage 2a together with 2b satisfies the Stage 2 advance gate (sbd#84 ship ladder).

---

## 2. Goals

1. Ship one runnable `/safer:install-friction` skill that probes a repo as a fresh-install operator and reports every failure point during install + first-command flow.
2. Ship one runnable `/safer:cli-ergonomics` skill that exercises every documented CLI command in a repo and scores help text, error messages, and exit codes.
3. Ship one runnable `/safer:extension-attempt` skill that attempts a non-trivial extension against a repo's public surface and reports over-coupling. This skill routes its core work to `/safer:spike`; the persona is the framing prompt + scoreboard row.
4. Extend cc-judge's `AxisSchema` enum with two new literals so scenarios authored later can target install + CLI ergonomics dimensions.
5. Each persona produces one report artifact in a single, schema-stable shape (one verdict, scored sub-axes, friction list, recommended revisions, confidence) so a future Stage 2b aggregator can consume all three without per-persona special-casing.
6. Each persona is invokable two ways: directly by a human (`/safer:install-friction --repo owner/name`) and dispatchable by a future orchestrator that passes the same arguments. No auto-dispatch in 2a.
7. Each persona declares its model in its frontmatter, picked per the routing rule in §6 below.
8. Cite sbd#84 in every persona skill's "Read first" section so a cold-start reader can trace the rationale.

---

## 3. Non-goals

1. **No orchestrator** — `/safer:dogfood-all` is Stage 2b, not 2a. The three personas do not call each other; no coordination skill is shipped.
2. **No aggregator** — dedupe-by-`(location, category)`, worst-of-N verdict, and short-circuit-on-REJECT are 2b. 2a personas each emit standalone reports.
3. **No release-gate plumbing** — `.safer.yml`, the CI check that reads scoreboard comments, and `/safer:signal-scan` are Stage 3. 2a does not block any merge.
4. **No new cc-judge scenarios** authored against the new axes. The schema slot exists; populating it is downstream work and a separate sub-issue.
5. **No new sub-rubric structure inside cc-judge axes.** Whether `install-friction` and `cli-ergonomics` need nested sub-rubrics is an open question deferred (sbd#84 open question #3); 2a treats them as flat axes for now.
6. **No real beta-user feedback ingest.** `/safer:dogfood-feedback` is Stage 4. 2a personas simulate consumers; they do not collect from any.
7. **No revision of the existing `/safer:dogfood` skill.** Cold-start reader stays as-is; Stage 2b orchestration may wrap it later.
8. **No promotion of `extension-attempt` into a cc-judge scenario.** sbd#84 Round 6 + Round 8 conclusion: extension is the definition of a spike, routes through `/safer:spike`, never becomes a cc-judge axis. 2a respects that ratchet.
9. **No skill that operates outside the published-artifact + repo-root surfaces.** Personas read the repo + its docs + its CLI; they do not query GitHub Issues, Discussions, or external signal sources.

---

## 4. Invariants

1. **Persona output schema is stable across all three skills.** A 2b aggregator, written without modifying the persona skills, can parse any of the three reports with the same parser. (The schema's exact field names are an architect-stage decision; the *invariant* is that 2b can aggregate without touching 2a.)
2. **No persona auto-dispatches another persona.** A skill terminates with one report; coordination is the orchestrator's job, not the persona's. Violating this is a Principle 6 (Budget Gate) violation.
3. **Every persona runs cold against its target.** Like `/safer:dogfood`, the consumer-side analysis must dispatch a subagent (or equivalent) with no project session context. Any context borrowed from the dispatching session is the bug the persona exists to surface.
4. **`extension-attempt` never produces a cc-judge scenario row.** Its output is a spike writeup, not an axis-scored result. Routing through `/safer:spike` is mandatory; calling `cc-judge` directly is forbidden.
5. **`AxisSchema` extension is additive, not mutating.** The 11 existing literals (principles 1-8, modality-routing, artifact-discipline, debt-multiplier) keep their exact string values. Two new literals are appended. No renames, no removals.
6. **Each persona's report is publishable as a single comment on the target artifact** (issue, PR, or local-file equivalent), matching the dogfood pattern. No multi-comment fan-out.
7. **Each persona is reproducible by hand.** A human running the same persona against the same repo twice in the same week gets verdicts within one tier of each other (SHIP/REVISE/REJECT). Determinism is not required; tier-stability is.
8. **No persona can mutate the target repo.** Read-only against the target; writes only to the publishing destination (comment on the artifact, or stdout for local).

---

## 5. Acceptance criteria

### 5.1 — Persona skill files exist and load

- [ ] `skills/install-friction/SKILL.md` exists, loads via the safer plugin loader, and declares model `haiku` in frontmatter.
- [ ] `skills/cli-ergonomics/SKILL.md` exists, loads, and declares model `haiku`.
- [ ] `skills/extension-attempt/SKILL.md` exists, loads, and declares model `opus`.
- [ ] Each skill's frontmatter includes `triggers`, `description`, `allowed-tools`, and a model declaration. (Format follows `skills/dogfood/SKILL.md` convention.)
- [ ] Each skill's "Read first" section cites sbd#84 by URL.

### 5.2 — Persona skill behavior

- [ ] `/safer:install-friction --repo owner/name` produces a report containing: install-step timeline (each step + status), TTHW (time-to-hello-world) in minutes, first-command success boolean, error-recovery friction list, verdict ∈ {SHIP, REVISE, REJECT}, confidence ∈ {LOW, MED, HIGH}.
- [ ] `/safer:cli-ergonomics --repo owner/name` produces a report containing: a per-command table (one row per documented CLI command) scoring help-text / error-message / exit-code per command, an overall ergonomics verdict, friction list, confidence.
- [ ] `/safer:extension-attempt --repo owner/name --feature "<one-line feature prompt>"` produces a report containing: the spike writeup (verbatim from `/safer:spike`), the over-coupled-API list (which public-surface files were touched outside the declared extension scope), verdict, confidence.
- [ ] All three skills, when given a repo where their target surface is missing (no install steps documented; no CLI; no public surface), emit a structured `BLOCKED` status per safer convention rather than crashing or producing a synthetic report.
- [ ] All three skills emit `safer.skill_run` and `safer.skill_end` telemetry events with their modality name.

### 5.3 — cc-judge axis schema extension

- [ ] cc-judge `src/core/schema.ts` `AxisSchema` includes `Type.Literal("install-friction")` and `Type.Literal("cli-ergonomics")` in addition to the 11 existing literals.
- [ ] cc-judge `Axis` type alias compiles; `Static<typeof AxisSchema>` includes the two new values.
- [ ] cc-judge tests verify a YAML scenario with `axis: install-friction` decodes successfully and `axis: not-a-real-axis` is rejected at the boundary with a typed error (Principle 2).
- [ ] cc-judge `README.md` (or whatever surface enumerates valid axis values) lists the two new literals.

### 5.4 — Per-persona rubric template (acid-test framing)

Each persona ships a rubric in its `SKILL.md` matching this template, with persona-specific axis names and scoring criteria:

```
# Rubric

Score each axis 0 to 10, integer. Cite evidence (a quoted phrase, a command output, a file path + line).

- <axis 1> — <one-sentence definition>. 10 = <best>; 0 = <worst>.
- <axis 2> — ...

# Verdict

- SHIP — every axis ≥ 8 AND no friction entry blocks action.
- REVISE — any axis ≤ 6 OR a friction entry blocks action.
- REJECT — <persona-specific blocker, e.g., install fails entirely; CLI command not runnable; public surface forces edits to private internals>.

# Output schema

[verbatim markdown skeleton — same shape across personas, with axis names swapped]
```

- [ ] `install-friction` axes: install-steps-clarity, TTHW, first-command-success, error-recovery.
- [ ] `cli-ergonomics` axes: help-text-quality, error-message-routability, exit-code-consistency, discoverability.
- [ ] `extension-attempt` axes: public-surface-stability, extension-scope-containment, doc-support-for-extenders, spike-go-no-go (the spike's own verdict).

### 5.5 — Invocation surface

- [ ] Each skill's `triggers` list contains at least three natural-language phrases a human would type.
- [ ] Each skill accepts `--repo owner/name` (and `--feature` for extension-attempt) as documented arguments.
- [ ] Each skill's preamble verifies `gh auth status` and emits the standard safer telemetry-log start event before running.
- [ ] When invoked under `/safer:orchestrate` with `SAFER_PARENT_ISSUE` set, each skill publishes its report as a comment on the parent issue. When invoked standalone, each skill prints to stdout and (if a repo is named) optionally publishes to a designated artifact via `--publish-to <issue-or-pr-N>`.

### 5.6 — Sbd#84 traceability

- [ ] This spec doc is committed under `docs/specs/community-feedback-stage-2a-v1.md` on branch `spec/community-feedback-2a`.
- [ ] sbd#90 receives a comment linking to the spec doc with a one-paragraph summary and a confidence marker.

---

## 6. Assumptions

The user must confirm or correct each:

1. **Skill names are `install-friction`, `cli-ergonomics`, `extension-attempt`** — using the brief's names, not the research's `/safer:dogfood-{install,cli,extend}` names. Reason: the team-lead brief uses the axis-style names; sbd#84's draft names were tentative.
2. **Models per the brief** — `install-friction` and `cli-ergonomics` route to haiku (the dogfood acid-test result generalizes to other "consumer-cold-read" personas); `extension-attempt` routes to opus because the underlying `/safer:spike` is opus-class work.
3. **`extension-attempt` is implemented as a wrapper that dispatches `/safer:spike`** with a fixed-template prompt ("can you extend this repo's public surface to add <feature> without touching any file outside <public-surface-dir>?") and reformats the spike writeup into the persona report shape. The persona does not re-implement spike semantics.
4. **The cc-judge axis values are bare strings `install-friction` and `cli-ergonomics`** (not e.g. `cross-cutting-install-friction`). The 11 existing literals mix `principle-N-...`, `modality-...`, `artifact-...`, `debt-...` namespaces; the two new ones do not need a namespace prefix.
5. **No new cc-judge scenarios are written in 2a.** The schema slot is opened; scenarios that exercise it are 2b acid-test work, owned by the implementer of the dogfood-all orchestrator.
6. **Stage 2a's "ship" definition is: 3 SKILL.md files, 1 cc-judge schema PR, this spec.** Not "3 personas + the orchestrator." 2b is a separate spec with its own advance gate.
7. **The spec doc lives in the safer-by-default repo even though one persona's implementation work lands in cc-judge.** The spec is single-source; routing is "1 implement-staff PR per repo" downstream.
8. **`extension-attempt`'s "fixed feature prompt" is supplied by the human at invocation time** (`--feature` flag). Default seed prompts may live in the SKILL.md as examples, but no canonical "test extension" is mandated by 2a.

---

## 7. Open questions

1. **Q:** Should the cc-judge `AxisSchema` extension keep the flat 11→13 literal-list shape, or restructure to a tagged union (`{ kind: "principle", n: 1 }` etc.)?
   **Options:** (a) Flat extension — append two `Type.Literal` entries. (b) Tagged restructure — group existing 11 by category, slot `install-friction` and `cli-ergonomics` under a new `cross-cutting` group.
   **Recommended default:** (a). Restructuring breaks existing scenario YAML files; sbd#84 explicitly recommended "no cc-judge schema change beyond adding the two new axis names." Defer (b) to a separate architect cycle if/when sub-rubric nesting becomes load-bearing.

2. **Q:** Does `/safer:install-friction` execute the install commands in a real fresh container/VM, or does it read install docs and report on what a fresh-install reader would experience without actually running anything?
   **Options:** (a) Read-only doc audit — no execution; persona reads `README.md`, `setup/`, `docs/install.md` and reports on clarity + apparent friction. (b) Real-execution probe — persona spawns a clean container, runs the documented install steps, reports actual TTHW and first-command results.
   **Recommended default:** (b) for true acid-test value, but (a) is acceptable as a 2a fallback if container infrastructure is not in place. sbd#84 implies (b) ("fresh-machine TTHW > 10 min"); architect stage decides which is feasible by ship-by date. Flagging because the difference is large.

3. **Q:** Should `/safer:cli-ergonomics` discover commands automatically (parse `--help`, walk subcommands) or require the repo to enumerate them in a manifest?
   **Options:** (a) Auto-discovery via `--help` walking. (b) Manifest required (`.safer.yml` `cli_commands:` list).
   **Recommended default:** (a). Manifest requirement defeats the cold-start premise — if the repo doesn't ship one, the persona can't run, which is the inverse of the persona's purpose. Auto-discovery degrades gracefully; if it can't find a CLI, it BLOCKED-exits per §5.2.

4. **Q:** Does each persona spawn an internal subagent (the dogfood pattern) or run inline within the dispatching session?
   **Options:** (a) Internal subagent dispatch (matches `/safer:dogfood`). (b) Inline execution.
   **Recommended default:** (a) for `install-friction` and `cli-ergonomics` (cold-start invariant requires no session leak). `extension-attempt` does not need its own subagent because `/safer:spike` already runs cold.

5. **Q:** Where do the persona reports live when the persona runs standalone (no parent issue, no PR)?
   **Options:** (a) stdout only. (b) stdout + optional `--publish-to <issue-or-pr-N>`. (c) Auto-create a `safer:dogfood-report` issue.
   **Recommended default:** (b). Matches dogfood; (c) creates issue noise; (a) loses the report on session end.

6. **Q:** Does `extension-attempt`'s spike writeup get published verbatim, or does the persona reformat it into the standard report shape?
   **Options:** (a) Verbatim spike writeup as the report body. (b) Reformat into the per-persona rubric shape, attach the spike writeup as an appendix.
   **Recommended default:** (b). Invariant 1 (stable output schema) requires a parseable shape across all three personas. The spike writeup is evidence, not the report.

7. **Q:** Does the per-persona report explicitly state which Stage 2b aggregator field each section maps to, or does 2b solve mapping at consumption time?
   **Options:** (a) Each persona report includes a structured-data block (e.g., a YAML/JSON appendix) the aggregator reads. (b) 2b parses the markdown.
   **Recommended default:** (a). Invariant 1 + Principle 2 (validate at boundaries): a structured block is the natural decode boundary. The architect stage decides the exact shape.

---

## Rejected alternatives

These were considered and dropped during sbd#84 (rounds 5-8). Listed here so a future reader does not re-litigate:

1. **Six-persona pipeline** (cold-start + install + CLI + docs + community-signal + grumpy-staff). Rejected: redundancy. Docs subsumed by cold-start + install; community-signal is Stage 3; grumpy-staff was voice, not function (folded into extension-attempt).
2. **Persona-as-cc-judge-scenario for extension-attempt.** Rejected: spike is the natural shape; forcing it through cc-judge violates the Ratchet.
3. **GitHub-issue-per-finding output.** Rejected: fragments signal away from the upstream author.
4. **Release-gate as Stage 2 default.** Rejected: too tight; high-blast-radius gating belongs in opt-in `.safer.yml` (Stage 3).
5. **Persona SDK / framework.** Rejected: gstack, MCP, fast-check all shipped concrete reference implementations before any abstraction. Skill-files-on-disk is the persona unit.
6. **Fully-sequential persona coordination (all 4 in series).** Rejected: ~4× latency vs the 3-way-parallel-after-cold-start-gate pattern. Note: this concerns 2b coordination, not 2a; included for traceability.
7. **`/safer:dogfood-all` as part of 2a.** Rejected by the team-lead brief: 2a ships persona surface area only; coordination is 2b.

---

## Source citations

- sbd#84 final report — https://github.com/chughtapan/safer-by-default/issues/84#issuecomment-4274924946
- sbd#90 plan input — https://github.com/chughtapan/safer-by-default/issues/90
- `/safer:dogfood` precedent — `skills/dogfood/SKILL.md` in this repo
- cc-judge `AxisSchema` (in-progress PR) — chughtapan/cc-judge#23 (`staff/axis-field-ccj`)
