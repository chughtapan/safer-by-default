# INSTALL.md

Install paths, dependency requirements, and troubleshooting for safer-by-default. For the 30-second version, see the README's Quick start.

## Claude Code (canonical)

Inside a Claude Code session:

```text
/plugin marketplace add chughtapan/safer-by-default
/plugin install safer@safer-by-default
```

Skills register under the `safer:<name>` namespace (`/safer:spec`, `/safer:architect`, …). The plugin's `bin/` directory is auto-prepended to `PATH`, so `safer-publish`, `safer-vp`, `safer-update-check`, etc. are available immediately. No `./setup` step required.

**Verify**:

```text
/plugin
```

Should list `safer@safer-by-default: enabled` with the cache path under `~/.claude/plugins/cache/safer-by-default/safer/<version>/`.

**Upgrade**:

```text
/plugin marketplace update safer-by-default
/plugin install safer@safer-by-default
```

User-facing entry skills auto-detect available upgrades via `safer-update-check` and halt at the preamble until you run the two commands above.

## Codex

Codex has no plugin marketplace, so we install via a script:

```bash
git clone --depth 1 https://github.com/chughtapan/safer-by-default.git
cd safer-by-default
./setup-codex
```

`./setup-codex` resolves the safer-by-default source in this order:

1. `$SAFER_SOURCE_DIR` if set (developer escape hatch — points at any working tree).
2. The Claude Code plugin cache at `~/.claude/plugins/cache/safer-by-default/safer/<latest>` if you've already installed via the CC marketplace. Reuses that cache instead of duplicating files.
3. `~/.local/share/safer-by-default/` — cloned fresh from GitHub if absent, refreshed otherwise.

It then symlinks `bin/safer-*` into `~/.local/bin/` and writes Codex skill wrappers at `~/.codex/skills/safer-<name>/`. Restart Codex to pick them up. The clone you used to invoke the script is **not** the source of truth — it can be deleted; subsequent runs resolve from the CC cache or the XDG location.

**Env-var overrides**:

| Var | Purpose | Default |
|---|---|---|
| `SAFER_SOURCE_DIR` | Skip resolution; use this tree directly | unset |
| `SAFER_XDG_SOURCE_DIR` | Override the XDG fallback location | `~/.local/share/safer-by-default` |
| `SAFER_CODEX_BIN_DIR` | Where to symlink `safer-*` binaries | `~/.local/bin` |
| `SAFER_REPO_URL` | Git remote for the XDG fallback clone | `https://github.com/chughtapan/safer-by-default.git` |
| `CODEX_HOME` | Codex config root | `~/.codex` |

**Verify**: Codex should now respond to `safer:spec`, `safer:architect`, etc. The wrapper SKILL.md files at `~/.codex/skills/safer-<name>/` carry a marker comment (`<!-- safer-by-default codex wrapper -->`) so re-runs replace generated wrappers but leave hand-written ones at the same path untouched.

**Upgrade**: re-run `./setup-codex`. The XDG clone refreshes; the wrappers regenerate. If you're using the CC plugin cache as the source, run `/plugin marketplace update safer-by-default` first to refresh that cache, then `./setup-codex`.

## Per-repo setup (one-time)

After the plugin is installed:

```bash
safer-setup-labels
```

Creates the GitHub issue labels (`safer:parent`, `safer:spec`, `safer:planning`, `safer:implementing`, `safer:reviewing`, `safer:verifying`, `safer:done`, `safer:deferred`, …) the skills publish under. Requires `gh` authenticated with `repo` scope and write access. Idempotent — running it twice on the same repo is safe.

## Working from source (developers)

```bash
git clone https://github.com/chughtapan/safer-by-default.git
cd safer-by-default
./setup       # sanity check; not an installer
```

`./setup` verifies dependencies (`gh`, `git`, `bash`, `gh auth status`), prepares `~/.safer/analytics/`, makes binaries executable, and removes any legacy `~/.claude/skills/safer-*` symlinks left by previous versions of this script. The canonical install path is the marketplace command above.

**Run tests**:

```bash
tests/run-tests.sh
```

Covers `bin/` helpers and the Codex compatibility layer. Each test runs in an isolated temp dir with mocked external tools.

## Requirements

- `gh` (authenticated with `repo` scope), `git`, `bash`, `bun` (template generator + the architecture LSP runtime).
- [gstack](https://github.com/garrytan/gstack) installed at `~/.claude/skills/gstack/`. safer-by-default treats gstack as a hard dependency — every safer skill calls gstack tools (`/simplify`, `/review`, `/codex`, `/plan-eng-review`, `/security-review`, `/ship`, etc.) inline. `/safer:setup` fails fast if gstack is absent.
- `vscode-eslint-language-server` (from `vscode-langservers-extracted`) on `PATH` for the syntax LSP. `/safer:setup` installs it in the target repo as part of the standard ESLint setup.
- **Optional:** [`zapbot`](https://github.com/chughtapan/zapbot) for richer publish paths (falls back to `gh` cleanly if absent).

## LSP behavior at install time

The plugin manifest declares two `lspServers` (see `ARCHITECTURE.md` → LSP integration). When Claude Code (or an LSP-aware editor wired to this plugin) opens a TypeScript file, both servers auto-start:

- `agent-code-guard-syntax` → `node lsp/syntax/launch.js` (spawns upstream `vscode-eslint-language-server`).
- `agent-code-guard-architecture` → `bun lsp/architecture/server/index.ts` (runs TypeScript source directly; no build step).

If `bun` isn't on `PATH`, the architecture LSP fails to start with a visible `bun: command not found`. If `vscode-eslint-language-server` isn't on `PATH`, the syntax LSP prints a friendly pointer at `/safer:setup`. Either way, the rest of the plugin (skills, bins) keeps working.

## Troubleshooting

**`gh: command not found` or `gh auth status` fails.**
Install GitHub CLI (`gh`) and run `gh auth login`. Choose `repo` scope. Skills that publish to GitHub will not start until this passes.

**Skill descriptions dropped from the listing (`/doctor` warning).**
The skill registry exceeded the budget for description text. Either bump `skillListingBudgetFraction` in `~/.claude/settings.json` (e.g. `0.02` for ~20k tokens), or move user-skills you don't auto-route on to a `~/.claude/skills.disabled/` directory. Dispatched skills (called by other skills, not by the user) work fine with truncated descriptions — they're invoked by name, not discovered.

**Plugin install ID changed (was `safer-by-default@safer-by-default`, now `safer@safer-by-default`).**
The plugin slug in the marketplace was renamed. Run:
```text
/plugin uninstall safer-by-default@safer-by-default
/plugin install safer@safer-by-default
```
Then reload plugins. Stale entries in `~/.claude/plugins/installed_plugins.json` can be removed by editing the file.

**`./setup-codex` falls through to a network clone.**
Set `$SAFER_SOURCE_DIR` to your working tree path, or install via the CC marketplace first so the script can reuse that cache. The XDG fallback only activates when neither override nor cache is available.

**`safer-update-check` halts skills with `PRECONDITION_FAIL`.**
This is the upgrade gate working as intended. Run `/plugin marketplace update safer-by-default` and `/plugin install safer@safer-by-default`, then re-invoke the skill. To skip the gate inside an autonomous orchestration, ensure `SAFER_PARENT_ISSUE` is set — the gate suppresses itself for dispatched runs.

**State directory.**
Local state lives at `~/.safer/`:
- `analytics/events.jsonl` — modality run events. Always local; never sent.
- `last-update-check` — 1h cache for the version poll.

To purge: `rm -rf ~/.safer`. The next skill invocation recreates what it needs.

**Stale plugin cache after force-pushed history.**
If you upgrade and the new commit SHA has been force-pushed (history rewrite), the marketplace cache may still reference the old SHA. Run `/plugin marketplace update safer-by-default` and reinstall. If that fails, manually remove `~/.claude/plugins/marketplaces/safer-by-default/` and `~/.claude/plugins/cache/safer-by-default/`, then `/plugin marketplace add chughtapan/safer-by-default` again.
