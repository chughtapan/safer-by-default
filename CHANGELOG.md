## 0.2.0 — 2026-05-18

v0.2.0 composes `@chughtapan/safer-spec-development` (the per-folder living-spec codemod) into `safer-by-default` as a required dependency for the maintainer's dogfood workspace. The skill formerly called `/safer:spec` is renamed `/safer:contract`; two new wrapper skills (`/safer:contract-init` and `/safer:contract-migrate`) expose the codemod's per-folder bootstrap and migration flows from inside the plugin. The codemod's typed exit codes 10/11/12/13 from `safer-spec validate` route HOLD verdicts mechanically through `/safer:verify` to the correct upstream modality, expressing Principle 8 (the ratchet) as integers a CI gate can read.

**v0.2.0 is dogfood-only.** External adopters stay on `safer-by-default` 0.1.x until the publish follow-up (when the codemod publishes to npm) lifts the maintainer-repo pre-flight halt and replaces the `link:`-protocol install with an `@chughtapan/safer-spec-development@~X.Y.Z` install.

### Breaking

- Slash `/safer:spec` removed (hard cut, no alias). The renamed skill is `/safer:contract`. Adopters must run `/plugin marketplace update safer-by-default` and `/plugin install safer@safer-by-default` to reload; until reload, the old cache continues to surface `/safer:spec`. Post-reload, invoking `/safer:spec` returns Claude Code's "skill not found".
- `bin/safer-setup-labels` creates `safer:contract` (the new modality label) and no longer creates `safer:spec`. Existing `safer:spec` GitHub labels on adopter repos are not migrated automatically; relabel manually (the script does not touch existing issues by design — Non-goal 3).
- `/safer:setup` is TypeScript + vitest only in v0.2.0. Non-TS or non-vitest adopters stay on 0.1.x.
- `/safer:setup` v0.2.0 is dogfood-only: it pre-flight halts unless the CWD is `$SBD_ROOT/dogfood/` inside a populated clone of `chughtapan/safer-by-default`. External adopters wait for the publish follow-up.

### Added

- `vendor/safer-spec-development/` git submodule pinned at sister sha `c63ad4882d` (the post-rename merge into sister main).
- Two wrapper skills `skills/contract-init/` + `skills/contract-migrate/` that surface the sister codemod's `safer-spec-init` / `safer-spec-migrate` skills inside the plugin. Bodies are inlined at `bin/safer-gen-skills` time from the submodule via the new `{{> vendor-skill:<slug>}}` template directive.
- `bin/safer-gen-skills --check --release` release-mode gate. Bare `--check` is unchanged and stays green while source carries the `__SAFER_SPEC_VERSION__` sentinel during integration-PR development. `--check --release` fails when the literal sentinel survives in any committed `SKILL.tmpl` or `SKILL.md`, catching the case where the integration PR forgot the final substitution. CI on `release/*` branches runs the release-mode form.
- `/safer:setup` Step 4c wires the codemod into the dogfood workspace: pre-flight halts (NotInSaferByDefaultClone, VendorSubmoduleAbsent, NotDogfoodCwd, PnpmAbsent, NotTypeScriptError); pins `packageManager: pnpm@X.Y.Z` to `package.json`; installs the codemod via `pnpm add -D link:../vendor/safer-spec-development`; runs `pnpm exec safer-spec doctor`; seeds `safer-spec.config.json`; wires the vitest reporter (sentinel-bounded); appends `SPEC_LAYER=required` to the managed `CLAUDE.md` section; records the doctor output in the Step 11 receipt. Workspace monorepos repeat the seed+wire per workspace package.
- `/safer:verify` Phase 2/3 ring-1 codemod gate: `pnpm exec safer-spec doctor` (Phase 2 detection probe; failure is `BLOCKED` with doctor output verbatim) and `pnpm exec safer-spec validate --implemented` (Phase 3, wrapped in a Node-based 60s timeout helper). Phase 4 adds the sidecar-thresholds checklist; Phase 5's verdict table gains routing rows for exits 10/11/12/13 and exit 124 (timeout); Phase 6 adds `### Per-folder spec gates` and `### Codemod warnings` sub-sections.
- `/safer:architect` reads adjacent `MODULE.md` files in Phase 1; Phase 3b runs `pnpm exec safer-spec generate --skeleton-only --dry-run <folder>` for each new folder under a `MODULE.md`-bearing area and embeds the output as a fenced block in the design doc's Modules section; Phase 4 requires a per-export `Property-test gates` sub-section naming each new export's `PropertyType` (Roundtrip, Idempotence, Invariant, OracleAgreement); a new stop rule fires when a new export has no nameable `PropertyType`.
- `/safer:implement-staff` traceability table gains a `Sidecar property` column; Phase 4 requires `@spec.kind`/`@spec.property`/`@spec.threshold` JSDoc on every new public export in a `MODULE.md`-bearing area; Phase 7 requires `itSpec`/`itSpec.todo` for every PropertyType row; Phase 8 runs `pnpm exec safer-spec validate --implemented` as the pre-PR scope check; Phase 9 PR body gains `## Property-test gates`; a new stop rule fires when a new public export lacks `@spec.*` JSDoc.
- `/safer:implement-junior` and `/safer:implement-senior` carry one-paragraph cross-references describing how diffs in `MODULE.md`-bearing folders update existing `@spec.*` directives, when to route to architect for NEW directives, and why hand-editing the sidecar JSON is the Principle 7 paper-over anti-pattern.
- `bin/safer-setup-labels` now creates the full modality-label set: `safer:contract`, `safer:architect`, `safer:implement-{junior,senior,staff}`, `safer:research`, `safer:spike`, `safer:deferred`.
- `setup-codex` clones with `--recurse-submodules` so vendored sister content lands in the Codex install. The skill-wrapper install loop runs after a narrow-scope retired-wrapper cleanup that removes ONLY `~/.codex/skills/safer-spec` (the known retired wrapper from the rename); other `safer-*` wrappers are left in place. `tests/test-bin/test-setup-codex.sh` asserts the retired-wrapper removal, the three new wrappers (`safer-contract`, `safer-contract-init`, `safer-contract-migrate`), and narrow-scope preservation of an unrelated mock wrapper.
- 11 scenarios under `scenarios/living-spec/` and one new scenario under `scenarios/principles/P1-types-beat-tests/property-type-as-residual.yaml`. Bodies are skeleton-shaped (id / name / axis / description); `setupPrompt` / `workspace` / `judge` blocks are filled by downstream `/safer:implement-staff` iterations against the demo project.
- `INSTALL.md` "Demo: living-spec cycle" section describes the end-to-end demo path (TS + vitest, one `auth/` module exposing `signInWithProvider`, walking `/safer:setup → /safer:contract → /safer:architect → /safer:implement-staff → /safer:verify`).

### Doctrine

- `PRINCIPLES.md` Part 2 gains a "Living-spec is the ratchet's machine-readable surface" sub-section after Principle 8's anti-patterns, naming exit codes 10/11/12/13 as Principle 8's machine-readable escalation targets.
- `PRINCIPLES.md` Principle 7's anti-patterns gain a bullet rejecting the sidecar-edit / `@spec.kind`-edit paper-over: editing the sidecar JSON or the directive to clear a `safer-spec validate` error sidesteps Invariant 2; the route is the exit-code modality, not the JSON edit.

### Deferred to publish follow-up

These items depend on the codemod publishing to npm and are explicitly out of scope for v0.2.0:

- Sister-package `@chughtapan/safer-spec-development` v0.2.0 npm publish.
- Marketplace publish itself (the `git tag` + `/plugin marketplace publish` step). v0.2.0 content updates ship (VERSION, plugin.json, marketplace.json); the publish step does not.
- Sister-minor CI contract test that installs the latest published patch within the pinned tilde range. Without an npm publish, there's no patch to install.
- External-adopter install. v0.2.0's pre-flight halts unless the CWD is the maintainer's dogfood workspace.
- Sister-package `safer-spec --version` reporting package version (not `SPEC_FORMAT_VERSION`). The integration runs version-skew detection through `safer-spec doctor` per spec Assumption 4, not `--version`; `--version` semantics belong with publish bookkeeping.
- Step 4c install line swapping from `link:../vendor/safer-spec-development` to `@chughtapan/safer-spec-development@~X.Y.Z`. The CF-3 lifecycle: this swap is a **one-off manual `SKILL.tmpl` edit** in the publish follow-up PR, not a re-substitution of the sentinel. The sentinel mechanism is the v0.2.0-integration-PR pattern; reusing it for the publish follow-up would add complexity for a one-line change.

### User-impact

To pick up v0.2.0 in Claude Code:

```
/plugin marketplace update safer-by-default
/plugin install safer@safer-by-default
```

**If you're an external adopter on 0.1.x:**

- Stay on 0.1.x. v0.2.0 is dogfood-only (it pre-flight halts unless invoked from inside a `chughtapan/safer-by-default` clone with the submodule populated). External-adopter support ships in the publish follow-up (when the codemod publishes to npm).
- 0.1.x continues to receive bug-fix releases on the `0.1.x` branch. Track that branch for updates.

**If you're the maintainer dogfooding v0.2.0:**

- After reload, `/safer:spec` returns "skill not found"; use `/safer:contract` instead.
- Existing GitHub issues carrying the `safer:spec` label remain labeled; `bin/safer-setup-labels` no longer creates that label and does not touch existing issues. Manual relabel per repo.
- `/safer:setup` halts on non-TypeScript / non-vitest projects with a "use safer-by-default 0.1.x" pointer. The dogfood workspace must carry `tsconfig.json` and a `vitest.config.{ts,js,mts}`.
- `/safer:setup` halts unless invoked from `$SBD_ROOT/dogfood/` inside a populated `chughtapan/safer-by-default` clone. Initialize the submodule first: `git submodule update --init --recursive`.
- `/safer:setup` requires pnpm. Install pnpm before running setup; the dogfood workspace's `packageManager:` field gets pinned at setup time.

## 0.1.6 — 2026-05-16

### Breaking: LSP path consolidates behind a single proxy entry

`.claude-plugin/plugin.json` `lspServers` collapses from two entries to one: `safer-merged`, pointing at `lsp/proxy/run.sh`. The wrapper templates `${CLAUDE_PLUGIN_ROOT}` into a generated config and execs the upstream [techee/lsp-proxy](https://github.com/techee/lsp-proxy) Python script. The proxy spawns two children — `typescript-language-server` (primary, for code intelligence) and the existing `bun`-hosted architecture LSP (sidecar, for architecture diagnostics) — and merges their notifications onto Claude Code's single LSP connection.

Reason: Claude Code's LSP dispatcher returns opaque "internal error" on every operation when multiple servers claim the same file extensions. The proxy presents one server to Claude Code while doing the multiplexing internally. Empirically confirmed with three different manifest shapes during the spike (3 servers → error; 1 server → works; 1 server-via-proxy with 2 children → all queries and diagnostics flow).

**User impact: re-run `/safer:setup` and `/reload-plugins` after upgrade.** Setup now installs LSP-side prerequisites (`typescript-language-server`, `python3`, `bun`) and fetches `lsp-proxy.py` at a pinned upstream commit (`9b5a2a5`) into `~/.cache/safer-by-default/lsp-proxy.py`. The fetch is idempotent and fail-closed: a network failure halts setup with a retry instruction rather than leaving the LSP path half-installed. Distribution stays MIT — the GPL v2 `lsp-proxy.py` lives in the user's local cache, never the plugin source tree.

### Removed: `lsp/syntax/` and `vscode-eslint-language-server` from the LSP path

The thin Node wrapper at `lsp/syntax/launch.js` and the `vscode-eslint-language-server` LSP integration are gone. ESLint syntax enforcement now flows through the CLI surface that `/safer:setup` already wires into each project: `eslint.config.js` loads `eslint-plugin-agent-code-guard`'s rules, and `/safer:verify`'s Phase 3 runs `eslint .` as a ring-1 gate. Pre-commit / CI integration the project already has continues to fire the same ruleset.

Trade-off: lose real-time syntax diagnostics surfaced inline as you type; keep them at well-defined checkpoints (`/safer:verify`, pre-commit, CI). The architecture LSP keeps its real-time diagnostic surface. The exchange buys TypeScript code intelligence (`documentSymbol`, `goToDefinition`, `findReferences`, `hover`) through Claude Code's `LSP` tool, which the prior two-server shape blocked.

### Added: `manifest-schema` CI guard

`.github/workflows/manifest-schema.yml` validates `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` against the canonical SchemaStore schemas (`https://json.schemastore.org/claude-code-plugin-manifest.json` and `claude-code-marketplace.json`) on every push to main and every PR touching those files. Catches schema drift when Claude Code's manifest shape changes underneath us — exactly the bug class that started this ship. Uses `check-jsonschema` against the network schema; CI failure means SchemaStore moved and our manifest needs to follow.

### Added: `lsp-proxy-smoke` CI guard

A new workflow boots `lsp/proxy/run.sh` against a minimal config in CI, sends a synthetic `initialize` request, and asserts the proxy completes the lifecycle without crashing. Runs only on PRs touching `lsp/`, `.claude-plugin/plugin.json`, or `skills/setup/SKILL.md` to keep cost down.

## 0.1.5 — 2026-05-16

### Added: two LSP servers ship with the plugin

`.claude-plugin/plugin.json` now declares two `lspServers` that auto-start when an LSP-aware editor or the Claude Code agent loop opens a TypeScript file. Both fire diagnostics with `codeDescription.href` populated so editor tooltips link directly to the relevant `PRINCIPLES.md` heading — reading the error reads the doctrine.

- **`agent-code-guard-syntax`** wraps upstream `vscode-eslint-language-server`. Surfaces every `eslint-plugin-agent-code-guard` rule (bare casts, `throw new Error`, `Promise<T>`, raw SQL, manual enums, mocks in integration tests). Runs via a thin `node lsp/syntax/launch.js` wrapper that spawns the upstream binary.
- **`agent-code-guard-architecture`** runs a custom Effect-shaped server backed by a workspace-scoped architecture analyzer: folder dependency graph, public surface curation, vendor type leaks, cross-domain sibling imports, cycle detection. File-header `// @agent-code-guard/architecture-exception: <rule>` directives provide per-file suppressions with `architecture-directive-parse-error` surfacing malformed directives so they can never silently fail. Runs via `bun lsp/architecture/server/index.ts` — TypeScript source directly, no build step at install time.

`lsp/architecture/` is a self-contained subpackage (its own `package.json`, deps, and `tsconfig.json`). The architecture analyzer was ported from `eslint-plugin-agent-code-guard@0.0.13`'s `src/rules/architecture/` (recovered from acg's pre-removal history) plus the LSP server was ported from acg's PR #66-#70 branches. `lsp/architecture/check.ts` is a thin CI shim consumers can wire as `node lsp/architecture/check.js` (post-build) or `bun lsp/architecture/check.ts` (from source) for fail-the-build behavior outside the LSP protocol. A two-LSP programmatic dogfood test ships at `lsp/architecture/dogfood.ts` and runs in CI; it spawns both LSPs via the manifest's `command + args`, sends `didOpen` on a fixture with syntax + architecture violations, and asserts both fire with `codeDescription.href` populated.

CI guard: the new `bun-runtime-smoke` job builds `lsp/architecture/server/index.ts` via `bun build --target=bun --no-output` on every push. Catches dependency drift where a future commit adds a Node-only API that bun can't run — sooner than the full dogfood would surface it.

### Added: `/safer:setup` writes structural choices to project `CLAUDE.md`

After the existing AskUserQuestion gathers stack choices (schema library, DB tool, integration-test glob), the setup skill now writes a sentinel-bounded `## Project structural choices (managed by /safer:setup — do not edit manually; rerun the skill to change)` section to the project's `CLAUDE.md`. Idempotent: rerun replaces ONLY the managed section between the sentinel heading and the next `## ` (or EOF); existing content above and below is preserved. Every Claude Code session in the project loads `CLAUDE.md` automatically, so these values become the per-session structural contract — the runtime expression of "ideal repo state" that used to live in the typescript skill body.

### Doctrine: PRINCIPLES.md absorbs `## Phrases to reject` + voice guidance

A new `## Phrases to reject` H2 lands after Part 4 (Communication), carrying the verbatim shortcut-phrase list ("this is just a prototype", "we'll add types later", "let me silence the linter for this one", etc.) plus the user-sovereignty deferral phrasing. The previous home was inside `skills/typescript/SKILL.tmpl`, which only loaded on TS triggers — now every skill that loads PRINCIPLES.md via `{{> principles}}` (every implement-*, review-senior, architect, …) gets the phrase blocklist in context. Voice guidance ("the signature speaks louder than the comment", "describe what is, not what was") folds into Part 4 → Communication's `### Voice` subsection. Existing principle headings (`## 1. Types beat tests` through `## 8. The Ratchet`) preserved verbatim so anchors in `eslint-plugin-agent-code-guard@0.0.14`'s `meta.docs.url` keep resolving.

### Doctrine: tier-stratified decision tables in implement-{junior,senior,staff}

The typescript skill's 35-row decision table (human-era shortcut vs agent-era full version, per shape-of-work) split across the three implement-* tiers by complexity:

- **junior** owns Principle 1-4 single-module forks: parsing API responses, JSON parsing, function-can-fail, error in try/catch, env var access, async return type, identifier branding, switch over union, callback signature, throw in Effect code. Both before/after example pairs (parsing HTTP response, exhaustive switch) lift into junior.
- **senior** owns Effect-runtime + testing-strategy seams: `Effect.tryPromise` catch shape, fetch inside Effect, `Layer.effect` for resources, `Config.string` env reads, happy-path vs error-path tests, test doubles for external services, positive-integer / non-empty-array brands, property-based tests via `fast-check`, parser/handler accepting untrusted input, testcontainers for code reading real DB / cache / queue.
- **staff** owns cross-service + mutation: two services crossing shape boundary (generated JSON Schema via `json-schema-diff`), cross-service boundary under SLA (Pact V4 contracts), critical UI flow vs non-critical (Playwright vs component tests), lint-only CI vs full test job, mutation testing scope on critical modules (Stryker as required gate) vs repo-wide.

Each tier's "How this modality projects from the doctrine" section references its embedded table. `bin/safer-gen-skills` regenerates all 16 SKILL.md files clean against the new content.

### Breaking: `skills/typescript/` deleted

The TypeScript craft floor skill is gone. Its load surface (3 sections beyond doctrine: ideal repo state, decision table, shortcut phrases) is now distributed:

- **Ideal repo state** → `/safer:setup` writes it to project `CLAUDE.md` (Phase 7 above).
- **Decision table** → tier-stratified across implement-* (Phase 6 above).
- **Shortcut phrases** → `PRINCIPLES.md` `## Phrases to reject` (Phase 5 above).

The LSP-on-every-write enforcement layer (Phase 4 above) catches violations reactively at the editor surface; the doctrine teaches them proactively at session start. Together they cover the same surface the typescript skill did, but with more uniform reach (PRINCIPLES.md applies to every skill; LSP fires on every write; setup-time CLAUDE.md persists per-repo).

`skills/typescript/acg-rationale.json` and `bin/safer-acg-sync` deleted alongside — the rule rationale that previously lived there now ships in `eslint-plugin-agent-code-guard@0.0.14`'s rule `meta.docs.description` + `meta.docs.url` fields. The LSP propagates them via the standard ESLint diagnostic protocol; no sfd-side bridging needed. `.claude-plugin/plugin.json`'s description string updated: 17 → 16 skills, "typescript" removed from the skill-name enumeration (it stays as a language keyword in `keywords`).

`skills/review-senior/SKILL.tmpl` and `skills/implement-{junior,senior,staff}/SKILL.tmpl` updated to drop `/safer:typescript` load references. `bin/safer-gen-skills` updated to drop the `<!-- BEGIN: acg-mapping --> ... <!-- END -->` template logic and the `acg-rationale.json` reads. A repo-wide grep for `skills/typescript`, `safer-acg-sync`, `acg-rationale`, or `/safer:typescript` returns zero hits.

### Changed: architecture LSP runs `.ts` via bun, no `dist/` shipped

Initial Phase 4 declared the architecture LSP as `node lsp/architecture/dist/server/index.js`, but `.gitignore` excluded `lsp/*/dist/` so end users running `/plugin install` from the marketplace got a manifest pointing at a file that didn't exist. Fixed by switching the manifest to `bun lsp/architecture/server/index.ts` — TypeScript source directly, no build step. `lsp/architecture/dogfood.ts` simultaneously made its plugin-root resolution source-vs-dist agnostic (walks up to find `.claude-plugin/plugin.json` instead of assuming dist depth). CI's `two-lsp-dogfood` job adds `oven-sh/setup-bun@v2` and runs `bun dogfood.ts` directly; the `pnpm build` step before dogfood is dropped. `lsp/architecture`'s `build-test` job (typecheck + vitest) is unchanged — `pnpm build` still runs `tsc` for typecheck, and vitest unit tests still consume the built output.

Tradeoff: users need `bun` on `PATH`. Since safer-by-default is gstack-based and gstack requires bun for its `browse` skill, sfd users almost certainly already have it. If absent, the LSP fails with a visible `bun: command not found` (vs the silent miss the original `node + dist/` would have caused for users without a build step).

### Docs

- README gains `## Editor diagnostics (two LSPs)` between Quick start and Four parts.
- ARCHITECTURE.md gains `## LSP integration` between CLI helpers and Install paths; `lsp/` added to repo layout.
- CLAUDE.md `## Non-skill assets` gains `lsp/` bullet.
- INSTALL.md `## Requirements` calls out `bun` as architecture-LSP runtime + `vscode-eslint-language-server` as syntax-LSP dependency. New `## LSP behavior at install time` section explains auto-start + failure modes.

### For contributors

- `lsp/architecture/` is a new code subdirectory with its own `package.json`, `tsconfig.json`, and CI job. SFD remains a Claude-plugin-first repo; the LSP is the only non-skill / non-bin code subdirectory.
- New process-issue insights collected during the orchestration that produced 0.1.5 (worktree-isolation gaps in the Agent backend, gstack composed-skill subagent loading, safer-diff-scope's LOC-only tier classifier, stacked-PR merge-order quirks, the dogfood-skill name vs integration-smoke mismatch) captured in the parent epic's wake-up digest at chughtapan/agent-code-guard#71.

## 0.1.4 — 2026-05-08

### Breaking: `safer:investigate` renamed to `safer:diagnose`

The bug-triage modality is reshaped around the smallest possible reproduction.

- **New iron rule.** The skill's job shifts from "name the root cause" to "the smallest possible reproduction is the artifact." Root-cause naming moves to `/codex --mode diagnose --hold-scope` for cross-model validation.
- **4-phase workflow** replaces the prior 8-phase one. Collect symptoms → reproduce in the smallest possible test → hand to codex → publish. Drops the standalone Isolate, Name-root-cause, and Recommend-fix-modality phases — those fold into "what codex's verdict says next."
- **Codex returns one of three verdicts:** `logical-fallacy` (the repro doesn't demonstrate the symptom; re-run), `symptom` with N directions (1 → continue with that direction; N>1 → orchestrator forks one diagnose per direction), or `confirmed-root-cause` (hand off to fix modality).
- **New orchestrate fork mechanism** in Phase 5c (Step 5c.5): when codex returns `symptom` with multiple directions, the orchestrator forks N siblings, one per direction. The parent epic's `## Diagnose splits` section tracks the count.
- **New runtime stop condition (#6):** three diagnose splits without convergence escalates to spec/architect — the bug surface is wider than diagnose can map.
- **Label rename.** `safer:investigate` becomes `safer:diagnose`. In-flight epics carrying the old label need re-labeling.
- **Name collision with gstack `/investigate` is gone.** The `/investigate` name-collision callout drops from README, AGENTS, and PRINCIPLES.

Cross-references updated in orchestrate, spec, verify, review-senior, stamina, AGENTS, README, PRINCIPLES, ARCHITECTURE, contract templates, and integration tests.

### Implementers audit and strip narrative code comments before opening the PR

Each `implement-*` skill now runs a mandatory comment audit between writing the code and moving to tests. The audit strips any inserted comment that:

- describes the present (`// this is the X`, `// we now do Y`),
- describes the future (`// the reviewer should check`, `// later we'll add`),
- restates what the code does (`// loop over users`),
- references the current task / fix / PR / plan line / caller.

Identifiers carry the explanation; PR descriptions and traceability tables carry task and plan context. Per-tier scoping calls out plan-anchor cross-refs (senior) and spec/plan citations (staff) — those live in the PR body's tables, not in code comments. A matching checklist line lands in each skill's "Checklist before declaring DONE."

### Implementer DONE checklists trimmed

Strips meta-glosses and restated rationale from the "Checklist before declaring DONE" sections in implement-junior, implement-senior, and implement-staff. Each checkbox is now a single directive imperative. Drops the duplicated "/safer:review-senior is mandatory before merge (enforced by orchestrate Phase 5c)" line from senior and staff: it duplicated the orchestrate gate and wasn't a self-checkable item.

## 0.1.3 — 2026-05-07

Combined release. Subsumes the locally-numbered-but-unpublished `0.1.3` (WS3 framing) and `0.1.4` (composition cleanup) working sections, plus the prior `Unreleased` work (ux-audit, contracts, gates) and an install-path + manifest cleanup. Only `0.1.2` actually shipped to the marketplace; the in-flight numbering has been collapsed so the published version increments cleanly from there.

### Plugin slug renamed: safer (from safer-by-default)

Breaking rename of the plugin name within the marketplace. Skills now load as `safer:NAME` (matching the docs' shorthand) instead of `safer-by-default:NAME`. The marketplace name and repo name remain `safer-by-default`. Plugin install ID is now `safer@safer-by-default`.

Anyone with the old install must migrate:

```text
/plugin uninstall safer-by-default@safer-by-default
/plugin install safer@safer-by-default
```

`.claude-plugin/marketplace.json` and `.claude-plugin/plugin.json` updated accordingly.

### New skill: /safer:docs-reader (renamed from /safer:safer-docs-reader)

Breaking rename. The skill directory `skills/safer-docs-reader/` is now `skills/docs-reader/`; YAML `name` is `docs-reader`. Other 16 skills already drop the `safer-` prefix on directory and YAML name, and the in-doc H1 was already `# /safer:docs-reader`. Anyone calling `safer-by-default:safer-docs-reader` explicitly must update to `safer:docs-reader`.

### New skill: /safer:ux-audit

Heuristic-based UX audit modality. Read-only on the live UI; emits a goal-linked findings ledger plus recommendations routed to the right downstream modality.

- `skills/ux-audit/SKILL.md`: new skill at v0.1.0. Seven inspection protocols (H1 Nielsen, H2 cognitive walkthrough, H3 WCAG 2.1 AA, H4 responsive, H5 form/microinteraction, H6 stakeholder/artifact read, H7 information architecture). Iron rule: every recommendation has finding + evidence + goal-link.
- Composition: per-protocol gstack pairings — `/browse` + `/design-review` for visual heuristics, `/qa-only` for cognitive-walkthrough reporting, `/setup-browser-cookies` for auth-blocked surfaces, optional `/plan-ceo-review` via `--challenge-goal` to stress-test the named goal.
- Workflow: URL/path inference from trigger, complaint-keyword H6 front-run, `SAFER_PARENT_ISSUE` as single orchestrate-context signal (used by Phase 6 publication and SendMessage gating), Phase 1.5 time-budget checkpoint (30-min progress comment, 60-min hard stop), `--prior <issue#>` for re-audit deltas, `DONE_PARKED` status when an orchestrate contract is missing inputs.
- Out of scope by design: applying fixes (recommendations route to `/safer:implement-*`, `/safer:architect`, or `/safer:contract`), analytics ingestion, plan-mode review of redesign-specs, auto-dispatch of recommendations.

### Contracts: explicit autonomy grants

Default state for the orchestrator and dispatching skills is no longer "all-stages-authorized." Every orchestration is now governed by a contract recorded on the parent epic body.

- `PRINCIPLES.md`: new `## Contracts` section. Four-section format (Goal, Acceptance, Autonomy budget, Always-park), worked examples, lifecycle (dispatch → execution → amendment → stop → done), recommended `Always-park` defaults, ratchet-up always parks, doctrine SHA stamping.
- `skills/orchestrate/SKILL.md`:
  - New Phase 1a (Draft the contract). Parses user instruction into the four sections, names back, waits for `OK` before any decomposition.
  - Phase 3 epic body template now requires `## Contract` and `## Contract history` sections.
  - New Step 5c.-1 contract-budget check before any auto-transition. Out-of-budget next dispatch parks; ratchet-up always parks regardless of budget. Posts `## Awaiting amendment` block on the parked sub-issue.
  - Phase 5d cron loop adds Step 1b (contract-comment scan): processes `OK`, `AMEND CONTRACT:`, `STOP CONTRACT:`, `REVISE:`, and 🛠️ reactions on the parent epic. Authorization gated on repo-collaborator status.
  - New Step 5b (Live `## Status` rewrite). After every state change, rewrites the parent epic's `## Status` section so a cold-start reader sees current state at a glance.
  - New Step 5c (wake-up digest). Posts a single consolidated digest comment when an autopilot run completes — "I went to bed; here's the night."
- `docs/contracts/`: four worked-example contract templates (invitation, bug-fix-end-to-end, scrum-master-backlog, architect-and-stop) plus a README pointing at when to use each.
- Per-skill changes: none. Skills publish artifacts cleanly; the contract check fires orchestrator-side. `safer-escalate --to <higher>` already declares ratchet-up; orchestrator's contract-budget check now reads it as park-mandatory.

### plan-eng-review + plan-devex-review gates

Architect and spec gain mandatory plan-quality gates before transitioning to review.

- `skills/architect/SKILL.md` Phase 7: `/plan-eng-review` runs first (hold-scope autonomous), then `/codex`. Threshold: optional for implement-junior tier, mandatory for senior/staff. Findings within the parent epic's `## Contract` autonomy budget auto-revise; findings cross-budget ratchet up to spec via `safer-escalate`. Unavailable → Claude sub-agent fallback with a structured architecture-audit prompt.
- `skills/spec/SKILL.md` Phase 5: same shape. Threshold: optional for junior-tier specs, mandatory for non-trivial features and any spec touching setup / deployment / infra. Same Claude sub-agent fallback.
- `skills/orchestrate/SKILL.md` Step 5c: setup/deploy path detection on PRs (railway.toml, vercel.json, Dockerfile, .github/workflows, fly.toml, netlify.toml, package.json scripts, .env*, setup/) additively dispatches `/plan-devex-review`. Spec/architect plans that describe infra work run the gate at the spec/architect stage; orchestrate verifies via audit-trail check.
- Order is plan-eng-review → codex (structured audit first; cross-model challenge on the audited plan).

### Composition cleanup; opus everywhere

Tightens the per-skill `Composition with gstack` sections and consolidates orchestrator dispatch on opus.

- Each skill's section is now `### Invokes` and `### Invoked by` (omit either if empty). One bullet per target, target name plus when/why; no per-target metadata.
- Stripped the universal "Eligible for zapbot-remote" tag (40/40 entries said yes; conveyed nothing).
- Stripped per-target interactivity labels (`Non-interactive` / `Two-gate`). The classification is target metadata, not per-skill composition metadata; centralized in `PRINCIPLES.md` → Composing with gstack as one paragraph naming the user-prompting targets that escalate via `/safer:orchestrate`.
- Architect: `/frontend-design`, `/design-consultation`, `/design-shotgun` are now live invokes, not "Tier 2 deferred".
- `PRINCIPLES.md` modality pipeline diagram: removed the `design-module* (Tier 2)` placeholder. There is no separate `design-module` modality; architect absorbs that work and composes with the gstack design skills. Knock-on cleanup in `skills/orchestrate/SKILL.md` (Phase 5c lists) and `skills/stamina/SKILL.md` (N-count table).
- Verify: closing redundant gstack-target list deleted. Phase 3.5 is the canonical contract.
- Orchestrator Model routing: opus for every dispatched modality. Removed the haiku/sonnet rows and the dogfood-on-haiku acid-test sidebar. Per-modality dispatch templates updated to say `model: opus` uniformly.
- `docs-reader`: persona sub-agents now dispatch on opus.

### WS3 framing: safer ↔ gstack composition

Doctrine-level decision on how safer composes with gstack. safer is the SDS modality spine; gstack is a parallel toolbox. Composition happens at the modality dispatch seam, per-skill — no central routing table.

- `PRINCIPLES.md`: new `Composing with gstack` section names the doctrine-precedence rule (*safer wins on scope; gstack ETHOS wins on quality-within-scope*) and the `/investigate` name-collision rule (always qualify in safer docs). Pipeline diagram extends to show the post-verify ship hop (`verify SHIP → gstack /ship → done`).
- `README.md`: brief overview section pointing at per-skill composition; not an encyclopedic mirror.
- Each `skills/*/SKILL.md`: new `## Composition with gstack` section listing that skill's specific composition targets, interactivity labels (`non-interactive` / `two-gate`), and zapbot-remote eligibility. Per-skill locality means an agent invoking skill X reads only X's body.
- Runtime contract (`PRINCIPLES.md` → Composing with gstack): interactive gstack skills run hold-scope autonomous; user-facing prompts are forbidden inside their bodies and route up to `/safer:orchestrate`, which surfaces them via `AskUserQuestion`. Closes the cross-session question-relay design question without building a new primitive.

### Install paths reworked

The plugin marketplace is now the canonical Claude Code install path; the manual-clone-into-`~/.claude/skills/` flow is deprecated.

- README install section rewritten. Sections for Claude Code (marketplace), Codex (`./setup-codex`), per-repo setup (`safer-setup-labels`), and working-from-source.
- `setup` repurposed as a sanity check + legacy-symlink cleanup. No longer creates standalone `~/.claude/skills/safer-*` symlinks (those duplicated every skill description and silently dropped 100+ from the registry on hosts with both install paths active). Detects + cleans them.
- `setup` zapbot probe extended to detect the marketplace-cache path (`~/.claude/plugins/cache/*/zapbot/`) in addition to the legacy standalone path.
- `setup-codex` resolves the safer-by-default source via `$SAFER_SOURCE_DIR` → CC plugin cache → `~/.local/share/safer-by-default/` (clones fresh if absent). Decoupled from any specific working-tree path.
- `tests/test-bin/test-setup-codex.sh` updated for the new resolution contract.

### Removed

- `safer-linear` feature: `lib/safer-linear/` (5 shell scripts), `bin/safer-linear-setup`, `tests/test-bin/test-linear-setup.sh`, `tests/test-linear-v2/` (~15 tests). Linear-project sync line removed from `skills/orchestrate/SKILL.md`. Replacement: none planned.
- `plugins/safer-channel/` working-tree scratch (only untracked `node_modules/`; never committed). Anyone with `safer-channel@safer-by-default` enabled in their personal `~/.claude/settings.json` should disable it: `/plugin disable safer-channel@safer-by-default`.
- `docs/arch/bot-token-routing.md` orphan planning doc.

### Changed (manifests)

- `VERSION`, `.claude-plugin/marketplace.json`, and `.claude-plugin/plugin.json` synced to `0.1.3`. Previously the manifests were stuck at `0.1.2` while `VERSION` had drifted to `0.1.4`. The marketplace description listed `13 skills (... ) plus 10 bin/ utilities`; actual counts are 17 skills and 13 bin utilities and the description now reflects that.

### Docs

- `CLAUDE.md` rewritten (~30 lines): plugin overview, namespacing (`safer:NAME` everywhere), runtime paths, source-resolution order, where contracts/scenarios live.

## 0.1.2 — safer-docs-reader skill

New `safer-docs-reader` skill (opus orchestrator + 4 haiku persona sub-agents: install-operator, cold-start-junior, security-skeptic, cli-ergonomics-auditor). Audits a docs artifact and publishes persona-aggregated feedback. Plus doctrine-triangle updates to orchestrate/review-senior/verify (read-reviewer-body, pane-monitor, HOLD-vs-APPROVE), CC-time-estimates PRINCIPLES subsection, `safer:deferred` label, investigate-first triage rule.

## 0.1.1 — bin/ packaging fix

Package `bin/` directory in plugin distribution to fix telemetry propagation (sbd#101).

## 0.1.0 — Initial

First cut of the safer-by-default Claude Code plugin.

### Doctrine

- `PRINCIPLES.md` — the compiler-frame thesis. Two axes: craft (principles 1-4, aim at compiler-grade output), scope (principles 5-8, stay in your lane). Artifact discipline (GitHub, confidence, cold-start) binds handoff.

### Skills (13)

- `orchestrate` — VP/scrum master: decompose intent, create GitHub epic + sub-issues, dispatch modalities, gate handoffs, close out with VP dashboard.
- `spec` — ambiguous intent → spec doc (goals, non-goals, invariants, acceptance criteria).
- `architect` — spec → module boundaries, interfaces, data flow, dependency choices.
- `implement-junior` — internals of one module; no exported-signature changes; no cross-module reach.
- `implement-senior` — cross-module within an approved plan; no new modules.
- `implement-staff` — new modules per approved spec; must trace to plan.
- `investigate` — bug report → repro + isolation + root cause + fix recommendation.
- `spike` — feasibility question → throwaway code + go/no-go verdict.
- `research` — open question → hypothesis ledger + validated insights (OpenGlia researcher + supervisor loop).
- `review-senior` — pre-merge diff review; native PR review as the artifact.
- `verify` — test run + acceptance check + ship/hold verdict.
- `typescript` — TypeScript craft floor; invoked by `implement-*` when target is TS.
- `setup` — one-time bootstrap: install `eslint-plugin-agent-code-guard`, flip tsconfig strict flags, probe that lint fires.

### Binaries (10)

Under `bin/`, all standalone (no gstack dependency):

- `safer-update-check`, `safer-telemetry-log`, `safer-slug`, `safer-publish`, `safer-load-context`, `safer-transition-label`, `safer-escalate`, `safer-diff-scope`, `safer-vp`, `safer-calibration`.

### Integration

- Lint floor: the `setup` skill installs [`eslint-plugin-agent-code-guard`](https://github.com/chughtapan/agent-code-guard).
- Publish path: `safer-publish` prefers `/zapbot-publish` (if [zapbot](https://github.com/chughtapan/zapbot) is installed), falls back to `gh issue/pr` commands.

### State

Local state lives under `~/.safer/`:
- `~/.safer/analytics/events.jsonl` — modality events (always local, never sent).
- `~/.safer/last-update-check` — 1h cache for version poll.
