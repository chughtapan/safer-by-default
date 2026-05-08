# safer-by-default

A Claude skill plugin that recalibrates your coding agent for type-safe, scope-disciplined work. Four parts: craft, discipline, stamina, communication.

## The Problem

Your coding agent is miscalibrated. It was trained on human-written code — decades of it — written under one constraint that does not apply to it: typing was expensive for humans. That is why its training corpus is saturated with `throw new Error("bad")`, `as Record<string, unknown>`, `try { ... } catch {}`, `Promise<T>` return types, `if`-else without a `never` default, and untyped `process.env.FOO!` reads. Those were the compromises humans made when keyboard time was scarce. For an agent, keyboard time is not scarce. The agent can produce code that *eliminates classes of error by construction* — the way a compiler eliminates register-allocation bugs — if it is calibrated to do so.

It is not. This plugin recalibrates.

## Four parts

**Part 1 — Craft.** Four principles for compiler-grade output:
- **Types beat tests:** Move constraints into the type system. Branded types, discriminated unions, exhaustive matches — the compiler catches every site, every reader, forever.
- **Validate at every boundary:** Inside a module, trust your types. At boundaries (disk, env, network, another package), decode with a schema.
- **Errors are typed, not thrown:** Tagged unions or discriminated results. No `throw new Error("bad")`, no bare `catch {}`, no `Promise<T>` that erases the error channel.
- **Exhaustiveness over optionality:** Every switch ends in `default: return absurd(x)`. Every `Option`/`Either`/`Result.match` handles both branches.

**Part 2 — Discipline.** Four principles for scope:
- **Discipline over capability:** The question is not "can I do this." The question is "is this mine to do."
- **The Budget Gate:** Shape, not volume. A 500-line module is fine; one line across two modules is not.
- **The Brake:** Stop rules are literal. When fired, stop writing code. Produce the escalation artifact.
- **The Ratchet:** Escalate up, never sideways. No quick fixes in sibling modules.

**Part 3 — Stamina.** How leverage-class artifacts earn `done`. N heterogeneous review passes, set by blast radius × reversibility, capped at 4. Internal one-module changes ship on N=1; public-surface or destructive changes go up to N=4.

**Part 4 — Communication.** How work hands off. Contracts (autonomy is granted, not assumed). Durable records (the forge is the record; edit in place, never amend; doctrine SHA-stamped at OK time; code references pinned). Output receipts (status, confidence, effort, process issues — every artifact declares all four). Writing for the cold-start reader (present-tense; portable; the next agent has none of your context).

Read [PRINCIPLES.md](./PRINCIPLES.md) for the full doctrine. Read any skill's `SKILL.md` for one projection of the principles onto one kind of work.

## Install

### Claude Code (plugin marketplace)

Inside a Claude Code session:

```text
/plugin marketplace add chughtapan/safer-by-default
/plugin install safer@safer-by-default
```

Skills register under the `safer:<name>` namespace (`/safer:spec`, `/safer:architect`, …). The plugin's `bin/` directory is auto-prepended to `PATH`, so `safer-publish`, `safer-vp`, `safer-update-check`, etc. are available immediately. No `./setup` step required.

### Codex

Codex has no plugin marketplace, so we install via a script:

```bash
git clone --depth 1 https://github.com/chughtapan/safer-by-default.git
cd safer-by-default
./setup-codex
```

`./setup-codex` resolves the safer-by-default source in this order:

1. `$SAFER_SOURCE_DIR` if set (developer escape hatch).
2. The Claude Code plugin cache at `~/.claude/plugins/cache/safer-by-default/safer-by-default/<latest>` if you've already installed via the CC marketplace.
3. `~/.local/share/safer-by-default/` — cloned fresh from GitHub if absent, refreshed otherwise.

It then symlinks `bin/safer-*` into `~/.local/bin/` and creates Codex skill wrappers at `~/.codex/skills/safer-<name>/`. Restart Codex to pick them up. The clone you used to invoke the script is not the source of truth and can be deleted.

### Per-repo setup (both flavors)

One-time, after the plugin is installed:

```bash
safer-setup-labels
```

Creates the GitHub issue labels (`safer:spec`, `safer:planning`, `safer:implementing`, …) the skills publish under. Requires `gh` authenticated with `repo` scope. Idempotent.

### Working from source (developers)

```bash
git clone https://github.com/chughtapan/safer-by-default.git
cd safer-by-default
./setup       # sanity check; not an installer
```

`./setup` verifies dependencies (`gh`, `git`, `bash`, `gh auth status`), prepares the analytics state dir, makes binaries executable, and removes any legacy `~/.claude/skills/safer-*` symlinks left by previous versions of this script. The canonical install path is the marketplace command above.

### Requirements

- `gh` (authenticated with `repo` scope), `git`, `bash`, `bun` (for the template generator).
- [gstack](https://github.com/chughtapan/gstack) installed at `~/.claude/skills/gstack/`. safer-by-default treats gstack as a hard dependency — every safer skill calls gstack tools (`/simplify`, `/review`, `/codex`, `/plan-eng-review`, `/security-review`, `/ship`, etc.) inline. `/safer:setup` fails fast if gstack is absent.
- **Optional:** [`zapbot`](https://github.com/chughtapan/zapbot) for richer publish paths (falls back to `gh` cleanly if absent).

## Use with Codex

Once `./setup-codex` has run, Codex sees the safer skills as `safer:<name>` wrappers. Example prompts:

- `Use safer:setup to bootstrap this TypeScript repo.`
- `Use safer:spec to turn this idea into a spec.`
- `Use safer:architect for the approved spec in issue #123.`
- `Use safer:review-senior to review this diff.`

Notes:

- The wrappers forward to the original skill docs in this repo; they do not rewrite the doctrine.
- GitHub-backed flows still expect `gh` to be installed and authenticated.
- The upstream docs say `AskUserQuestion`; in Codex that maps to a normal clarification question or the nearest available user-input mechanism.

## Skill catalog

Seventeen skills, grouped by **modality** (the type of work: design, execution, review, or bootstrap).

Each skill is invoked as a **Claude slash-command** within a Claude Code session. Example: type `/safer:spec` in Claude Code, and the skill runs in your session. Each skill's detailed signature — required arguments, flags, input shapes, and full workflow — is documented in the skill's `SKILL.md` file in this repository.

### Design / exploration

| Skill | When to invoke | Output |
|---|---|---|
| `/safer:spec` | ambiguous intent; no acceptance criteria | spec doc → GitHub issue |
| `/safer:architect` | need module/interface/data-flow structure | design doc + interface stubs + every artifact that defines the system (docs, configs, scripts, CI, deploy files) |
| `/safer:investigate` | reproducible bug | root-cause writeup + fix recommendation (no fix) |
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

### Floor + bootstrap

| Skill | Role |
|---|---|
| `/safer:typescript` | TS craft floor; invoked by `implement-*` on TS repos |
| `/safer:setup` | one-time: install `eslint-plugin-agent-code-guard`, flip strict flags, probe; gstack hard-dep precondition check |

## How work flows

```
user intent
    │
    ▼
/safer:orchestrate       ─── creates parent epic + sub-issues on GitHub
    │
    ├── /safer:spec         → spec published to sub-issue
    ├── /safer:architect    → design doc + interfaces published
    ├── /safer:implement-*  → draft PR opened
    ├── /safer:review-senior → native PR review
    └── /safer:verify       → ship/hold verdict on PR
```

**Parent epic + sub-issues:** The orchestrate skill breaks one user intent into a GitHub issue (parent epic) and creates child sub-issues for each work unit (spec, architecture, implementation, review). Each sub-issue tracks one modality of work.

**Scope discipline:** The principles enforce that each skill works in isolation — one module, one design phase, one code review — without reaching sideways into sibling work. The `/safer:implement-junior` skill, for example, fills one module's internals and does not touch a second file. If a second file is needed, the work is escalated to a senior skill that has permission to cross module boundaries.

Every skill publishes its artifact to GitHub before considering itself done. Status lives in issue labels, not local files. `safer-vp` renders the project dashboard from events + `gh` outcomes.

## Composing with gstack

safer is the SDS modality spine. [gstack](https://github.com/chughtapan/gstack) is a parallel toolbox of interactive workflow skills (`/codex`, `/qa`, `/ship`, `/plan-*`, `/health`, etc.). gstack is a hard dependency: every safer skill assumes the gstack tools it names are present. Install gstack alongside this plugin.

Individual skills name their own gstack tool usage inline in the workflow prose where the tool is called. There is no central routing table; the skill body is the dispatcher.

**Investigate name collision.** safer and gstack both ship a skill named `investigate`. Always qualify in safer docs: `/safer:investigate` (reproduce-and-name-the-cause); `/gstack:investigate` (gstack workflow). Bare `/investigate` is disallowed in safer docs.

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
