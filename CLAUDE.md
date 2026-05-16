# safer-by-default — project notes for agents

## What this is

A Claude Code skill plugin (also Codex-compatible) that recalibrates a coding agent for compiler-grade craft and scope discipline. Doctrine lives in `PRINCIPLES.md`. Every skill in `skills/` is one projection of those principles onto one kind of work (spec, architect, implement-{junior,senior,staff}, diagnose, spike, research, review-senior, verify, orchestrate, setup, dogfood, docs-reader, stamina, ux-audit).

## Skill namespacing

Skills load as `safer:NAME` in both Claude Code and Codex (e.g. `/safer:spec`, `/safer:architect`). The plugin slug inside the marketplace is `safer`; the marketplace itself is named `safer-by-default` (matching the repo). All in-repo docs use the `/safer:NAME` form literally.

## Where things live at runtime

- **Claude Code**: install via `/plugin marketplace add chughtapan/safer-by-default` then `/plugin install safer@safer-by-default`. The plugin's `bin/` is auto-prepended to `PATH`, so `safer-publish`, `safer-vp`, etc. are available without extra setup. Skills load from the cache at `~/.claude/plugins/cache/safer-by-default/safer/<version>/`.
- **Codex**: run `./setup-codex` from a clone of this repo. It resolves source via (1) `$SAFER_SOURCE_DIR`, (2) the CC plugin cache, (3) `~/.local/share/safer-by-default/` (clones fresh if absent). Symlinks `bin/safer-*` into `~/.local/bin/` and writes Codex wrappers to `~/.codex/skills/safer-NAME/`.
- **Working from source**: `./setup` is a sanity check (deps, state dir, legacy-symlink cleanup). It is not an installer; the marketplace is.

## Non-skill assets worth knowing about

- `PRINCIPLES.md` — the 4-part doctrine (craft, discipline, stamina, communication). Every skill projects from these principles.
- `docs/contracts/` — four worked-example contract templates (invitation, bug-fix-end-to-end, scrum-master-backlog, architect-and-stop) plus a README explaining when to reach for each.
- `scenarios/` — cc-judge calibration suite for evaluating doctrine adherence; see `scenarios/README.md`.
- `bin/` — 14 standalone helpers (publish, telemetry, escalate, etc.). All are on `PATH` in any session that has the plugin enabled. See `ARCHITECTURE.md` → CLI helpers for the full list.
- `lib/` — helper shell modules sourced by `bin/` scripts.
- `lsp/` — two LSP servers declared in `.claude-plugin/plugin.json`'s `lspServers`. `lsp/syntax/launch.js` wraps upstream `vscode-eslint-language-server` for the ACG syntax rules; `lsp/architecture/` is the custom Effect-shaped architecture analyzer + server (runs via `bun` directly on TypeScript source). Both fire diagnostics with `codeDescription.href` links to `PRINCIPLES.md` anchors. See `ARCHITECTURE.md` → LSP integration.

## Skill routing

- Stamina review on high-blast-radius artifact (public-surface PR, spec, architect plan) → invoke `/safer:stamina`.
