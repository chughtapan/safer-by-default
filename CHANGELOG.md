# Changelog

## 0.1.3 — 2026-05-07

Combined release. Subsumes the locally-numbered-but-unpublished `0.1.3` (WS3 framing) and `0.1.4` (composition cleanup) working sections, plus the prior `Unreleased` work (ux-audit, contracts, gates) and an install-path + manifest cleanup. Only `0.1.2` actually shipped to the marketplace; the in-flight numbering has been collapsed so the published version increments cleanly from there.

### New skill: /safer:docs-reader (renamed from /safer:safer-docs-reader)

Breaking rename. The skill directory `skills/safer-docs-reader/` is now `skills/docs-reader/`; YAML `name` is `docs-reader`. Other 16 skills already drop the `safer-` prefix on directory and YAML name, and the in-doc H1 was already `# /safer:docs-reader`. Anyone calling `safer-by-default:safer-docs-reader` explicitly must update to `safer-by-default:docs-reader` (or the documented `/safer:docs-reader` shorthand).

### New skill: /safer:ux-audit

Heuristic-based UX audit modality. Read-only on the live UI; emits a goal-linked findings ledger plus recommendations routed to the right downstream modality.

- `skills/ux-audit/SKILL.md`: new skill at v0.1.0. Seven inspection protocols (H1 Nielsen, H2 cognitive walkthrough, H3 WCAG 2.1 AA, H4 responsive, H5 form/microinteraction, H6 stakeholder/artifact read, H7 information architecture). Iron rule: every recommendation has finding + evidence + goal-link.
- Composition: per-protocol gstack pairings — `/browse` + `/design-review` for visual heuristics, `/qa-only` for cognitive-walkthrough reporting, `/setup-browser-cookies` for auth-blocked surfaces, optional `/plan-ceo-review` via `--challenge-goal` to stress-test the named goal.
- Workflow: URL/path inference from trigger, complaint-keyword H6 front-run, `SAFER_PARENT_ISSUE` as single orchestrate-context signal (used by Phase 6 publication and SendMessage gating), Phase 1.5 time-budget checkpoint (30-min progress comment, 60-min hard stop), `--prior <issue#>` for re-audit deltas, `DONE_PARKED` status when an orchestrate contract is missing inputs.
- Out of scope by design: applying fixes (recommendations route to `/safer:implement-*`, `/safer:architect`, or `/safer:spec`), analytics ingestion, plan-mode review of redesign-specs, auto-dispatch of recommendations.

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

- `CLAUDE.md` rewritten (~30 lines): plugin overview, namespacing (CC marketplace `safer-by-default:NAME` vs Codex `safer:NAME`), runtime paths, source-resolution order, where contracts/scenarios live.

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
