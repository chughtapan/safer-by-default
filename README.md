# safer-by-default

A Claude skill plugin that recalibrates your coding agent for type-safe, scope-disciplined work. Eight principles in two categories.

## The Problem

Your coding agent is miscalibrated. It was trained on human-written code — decades of it — written under one constraint that does not apply to it: typing was expensive for humans. That is why its training corpus is saturated with `throw new Error("bad")`, `as Record<string, unknown>`, `try { ... } catch {}`, `Promise<T>` return types, `if`-else without a `never` default, and untyped `process.env.FOO!` reads. Those were the compromises humans made when keyboard time was scarce. For an agent, keyboard time is not scarce. The agent can produce code that *eliminates classes of error by construction* — the way a compiler eliminates register-allocation bugs — if it is calibrated to do so.

It is not. This plugin recalibrates.

## Eight Principles: Two Axes

**Part 1 — Use your powers (craft).** Four principles for eliminating classes of error at the type level:
- **Types beat tests:** Use branded types or discriminated unions to make invalid states unrepresentable. Every constraint that can live in the type system should.
- **Validate at every boundary:** Inside a module, trust your types. At boundaries (disk, env, network, another package), decode with a schema.
- **Typed errors not raw throws:** Every error is a tagged union or discriminated result. No `throw new Error("bad")`, no bare `catch {}`.
- **Exhaustiveness over optionality:** Every switch ends in `default: return absurd(x)`. Every `Option`/`Either`/`Result.match` handles both branches explicitly.

**Part 2 — Stay in your lane (scope).** Four principles for scope discipline:
- **Junior-dev rule:** You fill one module. Cross-module reach is a boundary; reach is escalation.
- **Budget gate:** Shape is the rule, not volume. A 500-line module is fine; one line across two modules is not.
- **Literal stop rules:** When a 2nd module is touched, the rule has fired. Do not rationalize. Escalate.
- **The ratchet:** Escalate up (to senior, architect, staff), never sideways. No quick fixes in sibling modules.

Read [PRINCIPLES.md](./PRINCIPLES.md) for the full doctrine. Read any skill's `SKILL.md` to see one projection of the principles onto one kind of work.

## Install

**Pre-check:** If `~/.claude/skills/safer-by-default` already exists (from a prior install), remove it or choose a different path.

**Step 1: Clone the plugin**

```bash
git clone --single-branch --depth 1 https://github.com/chughtapan/safer-by-default.git ~/.claude/skills/safer-by-default
cd ~/.claude/skills/safer-by-default
```

⚠️ **Integrity note:** This clone is fetched over HTTPS with no checksum verification. If you require git signature verification, pin to a release tag instead: add `--branch v<version>` to the clone command. See [Releases](https://github.com/chughtapan/safer-by-default/releases).

**Step 2: Install dependencies**

```bash
./setup
```

`./setup` installs the `eslint-plugin-agent-code-guard` npm package into `.claude/plugins/`, configures `.claude/settings.json` with the lint rules, and probes for required CLIs (`gh`, `git`, `bash`, `bun`). It is idempotent and produces no output unless an error occurs.

**Step 3: Configure GitHub labels** (one time per repo)

```bash
./bin/safer-setup-labels
```

`./bin/safer-setup-labels` creates the GitHub issue labels used by safer-by-default skills (`safer:spec`, `safer:planning`, `safer:implementing`, etc.). Requires `gh` authenticated with `repo` scope and write access to the repository. It is idempotent; running it twice on the same repo is safe.

**Requirements:** `gh` (authenticated with `repo` scope), `git`, `bash`, `bun` (for the template generator).

**Optional:** [`zapbot`](https://github.com/chughtapan/zapbot) for richer publish paths (falls back to `gh` cleanly if absent).

## Use with Codex

This repository is authored as a **Claude-style skill plugin**, not a native Codex plugin. The quickest Codex path is to install a small compatibility layer that:

- links this repo into `~/.codex/skills/safer-by-default`
- creates Codex skill wrappers like `safer:spec`, `safer:architect`, `safer:review-senior`
- links `bin/safer-*` into `~/.local/bin`

Run:

```bash
./setup-codex
```

Then restart Codex so it reloads skills.

Example prompts inside Codex:

- `Use safer:setup to bootstrap this TypeScript repo.`
- `Use safer:spec to turn this idea into a spec.`
- `Use safer:architect for the approved spec in issue #123.`
- `Use safer:review-senior to review this diff.`

Notes:

- The wrappers forward to the original skill docs in this repo; they do not rewrite the doctrine.
- GitHub-backed flows still expect `gh` to be installed and authenticated.
- The upstream docs say `AskUserQuestion`; in Codex that maps to a normal clarification question or the nearest available user-input mechanism.

## Skill catalog

Thirteen skills, grouped by **modality** (the type of work: design, execution, gating, or bootstrap).

Each skill is invoked as a **Claude slash-command** within a Claude Code session. Example: type `/safer:spec` in Claude Code, and the skill runs in your session. Each skill's detailed signature — required arguments, flags, input shapes, and full workflow — is documented in the skill's `SKILL.md` file in this repository.

### Design / exploration

| Skill | When to invoke | Output |
|---|---|---|
| `/safer:spec` | ambiguous intent; no acceptance criteria | spec doc → GitHub issue |
| `/safer:architect` | need module/interface/data-flow structure | design doc + interface stubs |
| `/safer:investigate` | reproducible bug | root-cause writeup + fix recommendation (no fix) |
| `/safer:spike` | "is X feasible?" | throwaway code + go/no-go |
| `/safer:research` | open question, no known answer | hypothesis ledger + validated insights |

### Execution

| Skill | Scope |
|---|---|
| `/safer:implement-junior` | internals of one module; no public-surface changes |
| `/safer:implement-senior` | cross-module within approved plan; no new modules |
| `/safer:implement-staff` | new modules per approved spec |

### Gate / handoff

| Skill | Role |
|---|---|
| `/safer:review-senior` | pre-merge diff review; native PR review |
| `/safer:verify` | tests + acceptance + ship/hold |
| `/safer:orchestrate` | decomposition + routing + tracking (scrum master) |

### Floor + bootstrap

| Skill | Role |
|---|---|
| `/safer:typescript` | TS craft floor; invoked by `implement-*` on TS repos |
| `/safer:setup` | one-time: install `eslint-plugin-agent-code-guard`, flip strict flags, probe |

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

## Companion projects

This plugin does not stand alone. Two companions:

- **[`eslint-plugin-agent-code-guard`](https://github.com/chughtapan/agent-code-guard)** — the lint floor. The `setup` skill installs it. It catches the patterns an agent must not ship (bare catches, unsafe casts, raw SQL, mocked integration tests, hardcoded secrets). The plugin is the floor. This skill catalog is the ceiling.
- **[`zapbot`](https://github.com/chughtapan/zapbot)** — GitHub webhook bot + bridge. If installed, `safer-publish` composes with `/zapbot-publish` to get plannotator review links on published specs/plans. Absent it, `safer-publish` uses plain `gh`.

## Telemetry

Local only. Every skill invocation emits one `safer.skill_run` event to `~/.safer/analytics/events.jsonl`. Nothing is sent anywhere. Delete the directory to purge.

`safer-vp` and `safer-calibration` read these events + `gh` state to produce the VP-level dashboard (scope revert rate, stop-rule fires by modality, funnel, latency).

## License

MIT.
