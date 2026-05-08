# ARCHITECTURE.md

How safer-by-default is organized. For doctrine, read [`PRINCIPLES.md`](./PRINCIPLES.md). For rules of engagement, read [`AGENTS.md`](./AGENTS.md).

## The core idea

A coding agent miscalibrated for human-era shortcuts (`throw new Error("bad")`, `Promise<T>` that erases errors, sideways fixes that touch sibling modules) ships less safe code than the compiler can prove. safer-by-default is a set of *modalities* — kinds of work — each projected onto the same four-part doctrine. Every skill reads the same `PRINCIPLES.md`; only its scope, inputs, and outputs differ.

The agent doesn't learn doctrine by accumulation. It loads it per skill invocation. Each `SKILL.md` re-reads the principles and projects them onto its modality. This makes skills independently swappable and the doctrine changeable in one place.

## Repo layout

```
safer-by-default/
├── PRINCIPLES.md              ← four-part doctrine; canonical
├── AGENTS.md                  ← rules of engagement
├── ARCHITECTURE.md            ← this file
├── README.md                  ← install + overview
├── CHANGELOG.md               ← release notes
├── CLAUDE.md                  ← cold-start agent context
├── VERSION                    ← single source of truth for version
├── SKILL.md.tmpl              ← scaffolding for new skills
├── .claude-plugin/
│   ├── marketplace.json       ← Claude Code marketplace registration
│   └── plugin.json            ← plugin metadata
├── skills/                    ← 17 modality skills, one folder each
│   ├── orchestrate/
│   ├── spec/
│   ├── architect/
│   ├── implement-{junior,senior,staff}/
│   ├── investigate/
│   ├── spike/
│   ├── research/
│   ├── review-senior/
│   ├── verify/
│   ├── stamina/
│   ├── dogfood/
│   ├── docs-reader/
│   ├── ux-audit/
│   ├── typescript/
│   └── setup/
├── bin/                       ← 13 CLI helpers; auto-PATH at session start
├── lib/                       ← shell modules sourced by bin/ scripts
├── docs/contracts/            ← worked-example contract templates
├── scenarios/                 ← cc-judge calibration suite
├── tests/                     ← test-bin/, test-integration/
├── setup                      ← dev-mode sanity check + legacy cleanup
└── setup-codex                ← Codex compatibility installer
```

## Skill anatomy

Each `skills/<name>/SKILL.md` follows a fixed structure (codified in [`SKILL.md.tmpl`](./SKILL.md.tmpl)):

1. **YAML frontmatter** — `name`, `version`, `description`, optional `triggers`, `allowed-tools`.
2. **`# /safer:NAME`** — H1 heading, matches the YAML name.
3. **`## Read first`** — what to read before any work.
4. **`## Iron rule`** — the single non-negotiable invariant for this modality.
5. **`## Role`** — what the skill is and what it isn't.
6. **`## Inputs required`** — what must be present before invocation; preamble bash; update gate.
7. **`## Scope`** — in-scope and out-of-scope work.
8. **`## Workflow`** — phased steps.
9. **`## Stop rules`** — when to halt and escalate.
10. **`## Publication map`** — what artifact gets published where.
11. **`## Anti-patterns`** — common drift to avoid.
12. **`## Checklist before declaring DONE`** — verifiable preconditions.

Skills read `PRINCIPLES.md` in their preamble and project the relevant principles onto their modality. They publish artifacts via `safer-publish` to GitHub.

## Install paths

**Claude Code (canonical)**: marketplace install.

```text
/plugin marketplace add chughtapan/safer-by-default
/plugin install safer@safer-by-default
```

The plugin loads from `~/.claude/plugins/cache/safer-by-default/safer/<version>/`. `bin/` is auto-prepended to `PATH`. Skills register under the `safer:NAME` namespace.

**Codex**: `./setup-codex` resolves source via:
1. `$SAFER_SOURCE_DIR` env var (developer escape hatch).
2. The Claude Code plugin cache (if installed).
3. `~/.local/share/safer-by-default/` — clones fresh from GitHub if absent.

It then symlinks `bin/safer-*` into `~/.local/bin/` and writes Codex skill wrappers at `~/.codex/skills/safer-NAME/`. Decoupled from any specific working tree.

**From source (developers)**: clone the repo and run `./setup`. The script verifies dependencies (`gh`, `git`, `bash`), prepares `~/.safer/analytics/`, removes any legacy `~/.claude/skills/safer-*` symlinks from prior install schemes. It is **not** an installer — the marketplace is.

## Update mechanism

`bin/safer-update-check` polls `https://raw.githubusercontent.com/chughtapan/safer-by-default/main/VERSION` once per hour, cache at `~/.safer/last-update-check`. On mismatch, prints `UPGRADE_AVAILABLE <local> <remote>` to stdout. Silent on network failure or when up to date.

**Update gate**: user-facing entry skills (spec, architect, investigate, spike, research, setup, ux-audit) halt at the preamble if `_UPD` is non-empty AND `SAFER_PARENT_ISSUE` / `SAFER_SUBISSUE` are unset. Output: `PRECONDITION_FAIL` block telling the user to run the marketplace install commands. The model relays the message and waits for confirmation before doing any work.

`/safer:orchestrate` uses a refined gate: halts only on fresh-pipeline starts (no open `safer:parent` epic exists). Autonomous re-entry — cron ticks, parent-epic polling — skips the gate so in-flight pipelines drain to completion.

Dispatched skills (with `SAFER_PARENT_ISSUE` set) skip the gate. The user upgrades after the orchestration finishes.

## State

**Local** (`~/.safer/`):
- `analytics/events.jsonl` — modality run events. Always local; never sent.
- `last-update-check` — 1h cache for the version poll.

**Pipeline** (GitHub):
- Parent epic — labeled `safer:parent`. Body carries `## Contract`, `## Status`, `## Contract history`.
- Sub-issues — one per modality. Labeled with the modality state (`safer:spec`, `safer:planning`, `safer:implementing`, `safer:reviewing`, `safer:verifying`, `safer:done`, `safer:deferred`).
- Comments — every published artifact (spec doc, design doc, persona feedback, audit findings, escalation notices, wake-up digests).

The orchestrator reads pipeline state from GitHub on every tick; nothing pipeline-relevant lives in local files.

## Composition with gstack

safer-by-default treats [`gstack`](https://github.com/garrytan/gstack) as a hard dependency. Skills call gstack tools inline at modality dispatch boundaries — `/simplify`, `/review`, `/codex`, `/plan-eng-review`, `/plan-devex-review`, `/security-review`, `/ship`. `/safer:setup` fails fast if gstack is absent at `~/.claude/skills/gstack/`.

Doctrine precedence: **safer wins on scope; gstack ETHOS wins on quality-within-scope.**

Each skill's `## Composition with gstack` section names that skill's specific gstack invocations under `### Invokes` (what this skill calls) and `### Invoked by` (which gstack skills delegate into this one). Per-skill locality means an agent invoking skill X reads only X's body.

User-prompting gstack skills (e.g. `/plan-eng-review`, `/qa`) run hold-scope autonomous when invoked from inside a safer skill body. User-facing prompts route up to `/safer:orchestrate`, which surfaces them via `AskUserQuestion`.

## Stamina

Some artifacts have a high blast-radius — public-surface PRs, doctrine changes, deployment pipelines. They earn `done` only after N heterogeneous review passes (capped at 4) drawn from `/simplify`, `/review`, `/safer:review-senior`, `/safer:dogfood`, `/codex`, `/security-review`. N is set by the blast-radius × reversibility table in `PRINCIPLES.md` → Part 3.

`/safer:stamina` is the dispatcher. It does not review; it orchestrates the heterogeneous passes and aggregates verdicts. Invoked by `/safer:orchestrate` Phase 5c when the routing logic determines an artifact warrants stamina.

## Contracts

Every orchestration runs against a `## Contract` block on the parent epic body — goal, acceptance, autonomy budget, always-park items. The orchestrator drafts the contract in Phase 1a, names it back to the user, and waits for `OK` before any decomposition. Out-of-budget next dispatches park the sub-issue with `## Awaiting amendment`. Ratchet-up to a higher modality always parks regardless of budget.

Worked examples in `docs/contracts/`:
- `invitation.md` — initial intent → orchestrator contract.
- `architect-and-stop.md` — architect plan with explicit stop conditions.
- `bug-fix-end-to-end.md` — investigate → fix → verify pipeline.
- `scrum-master-backlog.md` — multi-issue orchestration backlog.

## Codex compatibility layer

Codex has no plugin marketplace. The `setup-codex` script:
1. Resolves a stable source root (CC plugin cache or XDG clone).
2. Symlinks `bin/safer-*` into `~/.local/bin/` so helpers are on `PATH`.
3. Writes per-skill Codex wrappers at `~/.codex/skills/safer-NAME/SKILL.md` that forward to the corresponding `skills/NAME/SKILL.md`.

The wrappers carry a marker comment (`<!-- safer-by-default codex wrapper -->`) so re-runs replace generated wrappers but never overwrite hand-written ones at the same path.

## Test infrastructure

- `tests/test-bin/` — unit tests for `bin/` helpers. Each `test-<helper>.sh` runs the helper in an isolated temp dir with mocked dependencies (`gh`, `bun`).
- `tests/test-integration/` — multi-step flows.
- `tests/test-helpers.sh` — shared assertion library.
- `tests/run-tests.sh` — driver.

`tests/test-bin/test-setup-codex.sh` exercises the source-resolution contract by setting `$SAFER_SOURCE_DIR` to the local checkout, isolating the test from host state.

## What's intentionally not here

- **Plugin marketplace for Codex.** Codex has no equivalent yet; the `setup-codex` shim is the bridge.
- **Per-skill `package.json` or build step.** Skills are markdown + bash. No transpile, no bundle.
- **Cross-skill state in local files.** Pipeline state lives on GitHub. Local files are session-scoped.
- **`--force` overrides on the update gate.** A stale skill body and a fresh remote can disagree on doctrine. Upgrade is the only path forward.
- **Doctrine inheritance from gstack.** safer's doctrine and gstack's ETHOS are independent. Composition happens at the dispatch seam, not at the doctrine level.
- **A `/safer:simplify` or `/safer:review` skill.** Those are gstack's domain; safer dispatches into them rather than mirroring them.
