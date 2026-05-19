# safer-by-default

A Claude skill plugin that recalibrates your coding agent for type-safe, scope-disciplined work. Four parts: craft, discipline, stamina, communication.

## The Problem

Your coding agent is miscalibrated. It was trained on human-written code — decades of it — written under one constraint that does not apply to it: typing was expensive for humans. That is why its training corpus is saturated with `throw new Error("bad")`, `as Record<string, unknown>`, `try { ... } catch {}`, `Promise<T>` return types, `if`-else without a `never` default, and untyped `process.env.FOO!` reads. Those were the compromises humans made when keyboard time was scarce. For an agent, keyboard time is not scarce. The agent can produce code that *eliminates classes of error by construction* — the way a compiler eliminates register-allocation bugs — if it is calibrated to do so.

It is not. This plugin recalibrates.

## Quick start

**Claude Code** (canonical):

```text
/plugin marketplace add chughtapan/safer-by-default
/plugin install safer@safer-by-default
```

Skills load as `safer:<name>` (`/safer:contract`, `/safer:architect`, …). The plugin's `bin/` is auto-prepended to `PATH`.

**Codex**:

```bash
git clone --depth 1 https://github.com/chughtapan/safer-by-default.git
cd safer-by-default && ./setup-codex
```

The script auto-detects an existing CC plugin install or clones to `~/.local/share/safer-by-default/`. Codex sees skills as `safer:<name>` wrappers. The clone is not the source of truth — delete it after.

**Per-repo setup** (one-time, requires `gh` authenticated):

```bash
safer-setup-labels
```

Creates the GitHub issue labels skills publish under. Idempotent.

**First skill**: in any repo, type `/safer:orchestrate` to start a new pipeline from intent, or pick a modality skill from the [catalog below](#skill-catalog).

For dependency requirements, source-resolution detail, working from source, and troubleshooting, see [INSTALL.md](./INSTALL.md).

## Editor diagnostics

The plugin manifest registers one LSP entry that fans out to multiple upstream servers behind a Python proxy. Claude Code's LSP dispatch can't multiplex multiple servers claiming the same file extensions, so safer presents a single server and does the multiplexing internally.

- **TypeScript code intelligence** (`typescript-language-server`) — `documentSymbol`, `goToDefinition`, `findReferences`, `hover`, and other LSP queries available via Claude Code's `LSP` tool against any `.ts`/`.tsx` file.
- **Architecture diagnostics** — a custom Effect-shaped analyzer (folder dependency graph, public surface curation, vendor type leaks, cross-domain sibling imports, cycles) runs as a diagnostic-only sidecar behind the proxy. File-header directives (`// @agent-code-guard/architecture-exception: <rule>`) provide per-file suppressions. Diagnostics fire in real time as files open and change, with `codeDescription.href` linking each finding to a `PRINCIPLES.md` heading.

**ESLint syntax floor** is delivered via CLI, not LSP. `/safer:setup` writes an `eslint.config.js` that loads `eslint-plugin-agent-code-guard`'s rules; `/safer:verify` runs `eslint` against the project as part of the pre-merge acceptance loop, and any pre-commit / CI integration the project already has continues to fire the same ruleset.

Dependencies installed by `/safer:setup`: `typescript-language-server`, `python3`, `bun`, and the upstream `lsp-proxy.py` fetched at a pinned commit into `~/.cache/safer-by-default/`.

## Four parts

The doctrine factors into four orthogonal axes. The first two govern *what code looks like*; the third governs *when it earns done*; the fourth governs *how work hands off*. Each safer skill projects from these four into one modality. The full text lives in [PRINCIPLES.md](./PRINCIPLES.md); the catalog of bullet points below is the operational summary.

**Part 1 — Craft.** Four principles for compiler-grade output:

- **Types beat tests.** Move constraints into the type system. Branded types, discriminated unions, exhaustive matches — the compiler catches every site, every reader, forever. Rules out `as Record<string, unknown>`, untagged optionals, runtime `typeof` checks for things the type already knows.
- **Validate at every boundary.** Inside a module, trust your types. At boundaries (disk, env, network, another package), decode with a schema. Rules out `process.env.FOO!` reads, untyped `JSON.parse`, blind trust in external API shapes.
- **Errors are typed, not thrown.** Tagged unions or discriminated results. No `throw new Error("bad")`, no bare `catch {}`, no `Promise<T>` that erases the error channel. Every error site has a name the caller can match on.
- **Exhaustiveness over optionality.** Every `switch` ends in `default: return absurd(x)`. Every `Option`/`Either`/`Result.match` handles both branches. Adding a new variant is a compile error at every site that didn't expect it — that's the point.

**Part 2 — Discipline.** Four principles for scope:

- **Discipline over capability.** The question is not "can I do this." The question is "is this mine to do." A skill with the *capability* to fix a sibling module's bug must still defer the work to the modality that owns it.
- **The Budget Gate.** Shape, not volume. A 500-line addition to one module is fine; one line across two modules is not. The gate measures *how many places* a change touches, not how big it is.
- **The Brake.** Stop rules are literal. When fired, stop writing code. Produce the escalation artifact and hand off. There is no "let me just finish this part first."
- **The Ratchet.** Escalate up, never sideways. A junior implementer hitting a missing module routes to senior or staff; it does not "just add the module." A reviewer finding architectural issues routes to architect; it does not rewrite the code itself.

**Part 3 — Stamina.** How leverage-class artifacts earn `done`. Higher blast radius warrants more review.

- **Blast radius × reversibility sets N.** A one-module internal change ships on N=1. Public-surface changes go to N=2. Doctrine, schema, or destructive changes go to N=3–4. The table lives in [PRINCIPLES.md](./PRINCIPLES.md) → Part 3.
- **Passes are heterogeneous.** N is not "the same reviewer N times." It's N different lenses — code review, dogfood, security audit, simplify pass, codex challenge — each looking for what the others miss. Same lens twice is one pass.
- **Capped at 4.** A 5th pass is a smell that the artifact is wrong, not under-reviewed. Park, rethink, narrow.
- **Stamina is a router, not a reviewer.** `/safer:stamina` dispatches the heterogeneous passes and aggregates verdicts; it never produces findings of its own.

**Part 4 — Communication.** How work hands off across sessions, agents, and time.

- **Contracts.** Autonomy is granted, not assumed. Every orchestration runs against a `## Contract` block (goal, acceptance, autonomy budget, always-park items) authored on the parent epic. Out-of-budget next steps park; ratchet-up always parks.
- **Durable records.** The forge (GitHub) is the record. Edit in place; never amend. Every artifact is doctrine-SHA-stamped at OK time so the reviewer knows which doctrine the work was approved against. Code references pinned by file:line, never "the function we discussed."
- **Output receipts.** Every artifact declares four numbers: status (DONE / DONE_PARKED / REVISE), confidence, effort, and process issues. Four lines, every time. The next reader knows what the producer believed without reading the body.
- **Cold-start writing.** The next agent has none of your context. Present-tense, portable references, no "earlier in this session." If a fact is load-bearing, it lives in the artifact body, not in the chat.

Read [PRINCIPLES.md](./PRINCIPLES.md) for the full doctrine. Read any skill's `SKILL.md` for one projection of the principles onto one kind of work.

## Prerequisites (v0.2.0)

v0.2.0 of `safer-by-default` is **TypeScript + vitest only**. `/safer:setup` halts with a "use safer-by-default 0.1.x" pointer on non-TS / non-vitest projects. v0.2.0 is also **dogfood-only**: the supported adopter is the maintainer's own `chughtapan/safer-by-default` clone with the `vendor/safer-spec-development/` submodule populated; external adopters wait for the publish follow-up (when the codemod publishes to npm).

`/safer:setup` pins the dogfood workspace to **pnpm** (sets `packageManager: pnpm@X.Y.Z` in `package.json`); npm and bun are not supported in v0.2.0 because their `link:`-protocol semantics differ. Yarn 1/2 could be added later but is not in scope for v0.2.0.

## Skill catalog

Eighteen skills, grouped by **modality** (the type of work: design, execution, review, or bootstrap).

Each skill is invoked as a **Claude slash-command** within a Claude Code session. Example: type `/safer:contract` in Claude Code, and the skill runs in your session. Each skill's detailed signature — required arguments, flags, input shapes, and full workflow — is documented in the skill's `SKILL.md` file in this repository.

### Design / exploration

| Skill | When to invoke | Output |
|---|---|---|
| `/safer:contract` | ambiguous intent; no acceptance criteria | contract doc → GitHub issue |
| `/safer:contract-init` | bootstrap living-spec for a new module (per-folder `MODULE.md` + sidecar) | new `MODULE.md` + `.safer-spec/<slug>.json` + property-test stub |
| `/safer:contract-migrate` | port a module to a new `SPEC_FORMAT_VERSION` | per-file dry-run diff + per-file rewrite |
| `/safer:architect` | need module/interface/data-flow structure | design doc + interface stubs + every artifact that defines the system (docs, configs, scripts, CI, deploy files) |
| `/safer:diagnose` | reproducible bug | smallest repro + codex verdict |
| `/safer:spike` | "is X feasible?" | throwaway code + go/no-go |
| `/safer:research` | open question, no known answer | hypothesis ledger + validated insights |
| `/safer:ux-audit` | UI surface needs heuristic audit (Nielsen, WCAG, etc.) | findings ledger routed to downstream modality |

### Execution

| Skill | Scope |
|---|---|
| `/safer:implement-junior` | internals of one module; no public-surface changes |
| `/safer:implement-senior` | cross-module within approved plan; no new modules |
| `/safer:implement-staff` | new modules per approved spec |

### Review / gate / handoff

| Skill | Role |
|---|---|
| `/safer:review-senior` | pre-merge diff review; native PR review |
| `/safer:verify` | tests + acceptance + ship/hold |
| `/safer:orchestrate` | decomposition + routing + tracking (scrum master) |
| `/safer:stamina` | fan-out reviewer for high-blast-radius artifacts (N heterogeneous passes) |
| `/safer:dogfood` | cold-start read of any artifact; portability check before handoff |
| `/safer:docs-reader` | multi-persona docs review (4 ephemeral opus personas) |

### Bootstrap

| Skill | Role |
|---|---|
| `/safer:setup` | one-time: install `eslint-plugin-agent-code-guard`, flip strict flags, probe; gstack hard-dep precondition check |

## How work flows

```
user intent
    │
    ▼
/safer:orchestrate       ─── creates parent epic + sub-issues on GitHub
    │
    ├── /safer:contract         → contract published to sub-issue
    ├── /safer:architect    → design doc + interfaces published
    ├── /safer:implement-*  → draft PR opened
    ├── /safer:review-senior → native PR review
    └── /safer:verify       → ship/hold verdict on PR
```

### Workspace monorepos

`/safer:setup` Step 4c installs the codemod **once** at the dogfood workspace root (`$SBD_ROOT/dogfood/`); the `link:`-protocol install populates the workspace's `node_modules/.bin`. If the dogfood layout has `vitest.workspace.ts` or per-package `vitest.config.{ts,js,mts}` files, setup repeats the **wire+seed** step (reporter patch + `safer-spec.config.json` seed) per workspace package, but the codemod install runs only at the workspace root.

**Parent epic + sub-issues:** The orchestrate skill breaks one user intent into a GitHub issue (parent epic) and creates child sub-issues for each work unit (contract, architecture, implementation, review). Each sub-issue tracks one modality of work.

**Scope discipline:** The principles enforce that each skill works in isolation — one module, one design phase, one code review — without reaching sideways into sibling work. The `/safer:implement-junior` skill, for example, fills one module's internals and does not touch a second file. If a second file is needed, the work is escalated to a senior skill that has permission to cross module boundaries.

Every skill publishes its artifact to GitHub before considering itself done. Status lives in issue labels, not local files. `safer-vp` renders the project dashboard from events + `gh` outcomes.

## Composing with gstack

safer is the SDS modality spine. [gstack](https://github.com/chughtapan/gstack) is a parallel toolbox of interactive workflow skills (`/codex`, `/qa`, `/ship`, `/plan-*`, `/health`, etc.). gstack is a hard dependency: every safer skill assumes the gstack tools it names are present. Install gstack alongside this plugin.

Individual skills name their own gstack tool usage inline in the workflow prose where the tool is called. There is no central routing table; the skill body is the dispatcher.

**Ship hop.** safer's `verify` modality emits SHIP/HOLD; the post-verify hop routes through gstack `/ship` (VERSION + CHANGELOG + PR). `/safer:orchestrate` handles that routing.

## Companion projects

This plugin does not stand alone. Two companions:

- **[`eslint-plugin-agent-code-guard`](https://github.com/chughtapan/agent-code-guard)** — the lint floor. The `setup` skill installs it. It catches the patterns an agent must not ship (bare catches, unsafe casts, raw SQL, mocked integration tests, hardcoded secrets). The plugin is the floor. This skill catalog is the ceiling.
- **[`zapbot`](https://github.com/chughtapan/zapbot)** — GitHub webhook bot + bridge. If installed, `safer-publish` composes with `/zapbot-publish` to get plannotator review links on published specs/plans. Absent it, `safer-publish` uses plain `gh`.

## Telemetry

Local only. Every skill invocation emits one `safer.skill_run` event to `~/.safer/analytics/events.jsonl`. Nothing is sent anywhere. Delete the directory to purge.

`safer-vp` and `safer-calibration` read these events + `gh` state to produce the VP-level dashboard (scope revert rate, stop-rule fires by modality, funnel, latency).

## License

MIT.
