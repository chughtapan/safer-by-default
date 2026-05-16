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
├── skills/                    ← 16 modality skills, one folder each
│   ├── orchestrate/
│   ├── spec/
│   ├── architect/
│   ├── implement-{junior,senior,staff}/
│   ├── diagnose/
│   ├── spike/
│   ├── research/
│   ├── review-senior/
│   ├── verify/
│   ├── stamina/
│   ├── dogfood/
│   ├── docs-reader/
│   ├── ux-audit/
│   └── setup/
├── bin/                       ← 14 CLI helpers; auto-PATH at session start (see "CLI helpers" below)
├── lib/                       ← shell modules sourced by bin/ scripts
├── lsp/                       ← single LSP entry declared in plugin.json (see "LSP integration" below)
│   ├── proxy/                 ← run.sh wrapper; execs upstream lsp-proxy.py with a templated config
│   └── architecture/          ← custom architecture analyzer + LSP server, runs via bun behind the proxy
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

## CLI helpers (`bin/safer-*`)

Each helper is a standalone bash script. The plugin marketplace install auto-prepends `bin/` to `PATH`, so skills invoke them by bare name. Skills should reference this table when calling a helper for the first time.

| Helper | Purpose | Signature |
|---|---|---|
| `safer-publish` | Publish artifact to GitHub (issue / comment / PR review); routes via zapbot when present | `--kind issue\|comment\|review [--title --body-file --labels --parent --issue --pr --repo]` |
| `safer-escalate` | Emit standard escalation markdown to stdout | `--from <modality> --to <target> --cause <cause> [--status --issue --parent --context --attempted]` |
| `safer-transition-label` | Atomic state-label transition on a GitHub issue | `--issue --from --to [--repo]` → `TRANSITIONED #<n>: <from> → <to>` |
| `safer-defer` | Atomically write deferral marker + add `safer:deferred` label | `--issue --reason --until` / `--issue --clear` / `--issue --check` |
| `safer-load-context` | Load issue (and optionally parent epic) as JSON | `--issue [--parent --repo]` → JSON |
| `safer-diff-scope` | Classify the current diff into junior / senior / staff tier | (no args; reads `git diff`) → JSON `{tier, files, modules, exports, new_deps, rationale}` |
| `safer-peer-message` | Peer-channel transport for cross-modality coordination | `--to-role --kind [--to-session --artifact-url --correlation-id] (--body-file \| --body-stdin)`; exit codes 0/10/20/21/22/30/64 |
| `safer-update-check` | Poll remote VERSION with 1h cache | (no args) → empty if current; `UPGRADE_AVAILABLE <local> <remote>` on mismatch |
| `safer-slug` | Emit `SLUG=<owner>-<repo>` from git origin (sh-evalable) | (no args) |
| `safer-telemetry-log` | Append JSONL event to `~/.safer/analytics/events.jsonl` | `--event-type [--modality --session --outcome --duration-s --issue]` |
| `safer-setup-labels` | Create the `safer:*` issue labels on a repo (idempotent) | `[--quiet]` |
| `safer-vp` | VP-level dashboard (funnel + throughput + calibration + in-flight) | `[7d\|30d\|all] [--repo]` |
| `safer-calibration` | Per-modality health dashboard from events.jsonl | `[7d\|30d\|all]` |
| `safer-gen-skills` | Render `skills/<name>/SKILL.md` from `SKILL.tmpl + PRINCIPLES.md` | `[--check]` |

Conventions: helpers exit non-zero on missing required args; skills wrap calls with `2>/dev/null || true` only when the helper is optional plumbing (telemetry, update-check), never when it's load-bearing. `safer-publish` routes through zapbot's bot-token broker when zapbot is detected on the host; absent zapbot, falls back to the user's `gh auth`.

## LSP integration

The plugin manifest (`.claude-plugin/plugin.json`) declares one `lspServers` entry: `lsp/proxy/run.sh`. The wrapper templates `${CLAUDE_PLUGIN_ROOT}` into a generated config and execs `python3 ~/.cache/safer-by-default/lsp-proxy.py` (the upstream [techee/lsp-proxy](https://github.com/techee/lsp-proxy) fetched at a pinned commit by `/safer:setup`). The proxy spawns two children and multiplexes them onto Claude Code's single LSP connection:

| Child | Role | Runtime |
|---|---|---|
| `typescript-language-server` | Primary. Handles `documentSymbol`, `goToDefinition`, `findReferences`, `hover`, and the other code-intelligence operations Claude Code's `LSP` tool exposes. Also emits TS semantic diagnostics. | `typescript-language-server --stdio` (installed globally by `/safer:setup`) |
| Architecture LSP | Diagnostic-only sidecar. Custom Effect-shaped server backed by the architecture analyzer (folder graph, public surface, vendor type leaks, cycle detection). Reads file-header `// @agent-code-guard/architecture-exception: <rule>` directives for per-file suppressions. Diagnostics populate `codeDescription.href` linking to a `PRINCIPLES.md` heading. | `bun lsp/architecture/server/index.ts` (runs TypeScript source directly) |

Why a proxy: Claude Code's LSP dispatcher errors out (`"internal error"` on every operation) when multiple servers claim the same file extensions. The proxy presents one server to Claude Code while internally fanning notifications to all children and merging their `publishDiagnostics` output upward.

The ESLint syntax floor — `eslint-plugin-agent-code-guard` rules — is delivered via the CLI surface that `/safer:setup` wires into each project (`eslint.config.js` with the plugin loaded). `/safer:verify`'s Phase 3 picks up the project's eslint config and runs `eslint .` as a ring-1 gate; any pre-commit / CI integration the project already has continues to fire the same ruleset. ESLint is not part of the LSP path.

The architecture analyzer also exports a thin shim at `lsp/architecture/check.ts` that CI can invoke (`node lsp/architecture/check.js` post-build, or `bun lsp/architecture/check.ts` from source) to exit non-zero on error-severity findings without needing the LSP protocol.

Dependencies installed by `/safer:setup` (global, not project-local): `typescript-language-server`, `python3`, `bun`, plus the pinned `lsp-proxy.py` in `~/.cache/safer-by-default/`.

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

**Update gate**: user-facing entry skills (spec, architect, diagnose, spike, research, setup, ux-audit) halt at the preamble if `_UPD` is non-empty AND `SAFER_PARENT_ISSUE` / `SAFER_SUBISSUE` are unset. Output: `PRECONDITION_FAIL` block telling the user to run the marketplace install commands. The model relays the message and waits for confirmation before doing any work.

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
- `bug-fix-end-to-end.md` — diagnose → fix → verify pipeline.
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
