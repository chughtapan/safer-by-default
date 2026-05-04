# Changelog

## Unreleased — Contracts: explicit autonomy grants

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

## 0.1.4 — Composition cleanup; opus everywhere

Tightens the per-skill `Composition with gstack` sections introduced in 0.1.3 and consolidates orchestrator dispatch on opus.

- Each skill's section is now `### Invokes` and `### Invoked by` (omit either if empty). One bullet per target, target name plus when/why; no per-target metadata.
- Stripped the universal "Eligible for zapbot-remote" tag (40/40 entries said yes; conveyed nothing).
- Stripped per-target interactivity labels (`Non-interactive` / `Two-gate`). The classification is target metadata, not per-skill composition metadata; centralized in `PRINCIPLES.md` → Composing with gstack as one paragraph naming the user-prompting targets that escalate via `/safer:orchestrate`.
- Architect: `/frontend-design`, `/design-consultation`, `/design-shotgun` are now live invokes, not "Tier 2 deferred".
- `PRINCIPLES.md` modality pipeline diagram: removed the `design-module* (Tier 2)` placeholder. There is no separate `design-module` modality; architect absorbs that work and composes with the gstack design skills. Knock-on cleanup in `skills/orchestrate/SKILL.md` (Phase 5c lists) and `skills/stamina/SKILL.md` (N-count table).
- Verify: closing redundant gstack-target list deleted. Phase 3.5 is the canonical contract.
- Orchestrator Model routing: opus for every dispatched modality. Removed the haiku/sonnet rows and the dogfood-on-haiku acid-test sidebar. Per-modality dispatch templates updated to say `model: opus` uniformly.
- `safer-docs-reader`: persona sub-agents now dispatch on opus.

## 0.1.3 — WS3 framing: safer ↔ gstack composition

Doctrine-level decision on how safer composes with gstack. safer is the SDS modality spine; gstack is a parallel toolbox. Composition happens at the modality dispatch seam, per-skill — no central routing table.

- `PRINCIPLES.md`: new `Composing with gstack` section names the doctrine-precedence rule (*safer wins on scope; gstack ETHOS wins on quality-within-scope*) and the `/investigate` name-collision rule (always qualify in safer docs). Pipeline diagram extends to show the post-verify ship hop (`verify SHIP → gstack /ship → done`).
- `README.md`: brief overview section pointing at per-skill composition; not an encyclopedic mirror.
- Each `skills/*/SKILL.md`: new `## Composition with gstack` section listing that skill's specific composition targets, interactivity labels (`non-interactive` / `two-gate`), and zapbot-remote eligibility. Per-skill locality means an agent invoking skill X reads only X's body.
- Runtime contract (`PRINCIPLES.md` → Composing with gstack): interactive gstack skills run hold-scope autonomous; user-facing prompts are forbidden inside their bodies and route up to `/safer:orchestrate`, which surfaces them via `AskUserQuestion`. Closes the cross-session question-relay design question without building a new primitive.

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
