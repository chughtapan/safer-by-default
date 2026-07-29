# safer-by-default — project notes for agents

A Claude Code skill plugin (also Codex-compatible) that recalibrates a coding agent for compiler-grade craft and scope discipline. Every skill in `skills/` is one projection of the doctrine onto one kind of work. `AGENTS.md` is the fuller map; `ARCHITECTURE.md` covers internals.

## Gotchas

- **`skills/*/SKILL.md` is generated.** Edit `SKILL.tmpl` in the same directory and run `bin/safer-gen-skills`. Direct edits to `SKILL.md` are overwritten on the next render. Both files are committed.
- **Doctrine is two layers.** `PRINCIPLES.core.md` is the compressed craft floor, inlined into every skill body by the generator via `{{> principles-core}}`. `PRINCIPLES.md` is the full doctrine, read by path at the plugin root when a call is close or the artifact is high-blast-radius. Changing a rule means updating both, then regenerating.
- **`PRINCIPLES.md` headings are load-bearing.** `eslint-plugin-agent-code-guard` points its rule docs at `PRINCIPLES.md#<anchor>`. Renaming a heading breaks those links.
- **Rare-branch material lives in reference files**, not in the skill body: `skills/<name>/references/*.md`, `skills/_shared/*.md`, `skills/docs-reader/prompts/*.md`. A skill reads them on demand. Keep the body to what every run of that modality needs.
- **Skills load as `safer:NAME`** in both Claude Code and Codex (`/safer:requirements`, `/safer:architect`). The plugin slug is `safer`; the marketplace is `safer-by-default`. In-repo docs use the `/safer:NAME` form literally.

## Where things live at runtime

- **Claude Code**: `/plugin marketplace add chughtapan/safer-by-default`, then `/plugin install safer@safer-by-default`. The plugin's `bin/` is auto-prepended to `PATH`, so `safer-publish`, `safer-vp`, and friends need no extra setup. Skills load from `~/.claude/plugins/cache/safer-by-default/safer/<version>/`.
- **Codex**: `./setup-codex` from a clone. It resolves source via `$SAFER_SOURCE_DIR`, then the CC plugin cache, then `~/.local/share/safer-by-default/`. Wrappers in `~/.codex/skills/safer-NAME/` point at the source by path rather than inlining it.
- **From source**: `./setup` is a sanity check, not an installer. The marketplace is the installer.

## Other assets

`docs/contracts/` holds four worked-example contract templates with a README on when to reach for each. `scenarios/` is the cc-judge calibration suite. `bin/` holds the shared helpers (see `ARCHITECTURE.md` → CLI helpers); anything only one skill calls stays inline in that skill. The architecture analyzer and its LSP server are a separate repository, [chughtapan/safer-architecture-lsp](https://github.com/chughtapan/safer-architecture-lsp). This plugin ships no LSP runtime.

## Skill routing

Stamina review on a high-blast-radius artifact (public-surface PR, contract, architect plan) → invoke `/safer:stamina`.
