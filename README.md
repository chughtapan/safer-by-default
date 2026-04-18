# safer-by-default

Your coding agent is miscalibrated.

It was trained on human-written code — decades of it — written under one constraint that does not apply to it: typing was expensive for humans. That is why its training corpus is saturated with `throw new Error("bad")`, `as Record<string, unknown>`, `try { ... } catch {}`, `Promise<T>` return types, `if`-else without a `never` default, and untyped `process.env.FOO!` reads. Those were the compromises humans made when keyboard time was scarce. For an agent, keyboard time is not scarce. The agent can produce code that *eliminates classes of error by construction* — the way a compiler eliminates register-allocation bugs — if it is calibrated to do so.

It is not. This plugin recalibrates.

## Two axes

**Part 1 — Use your powers (craft).** Four principles for eliminating classes of error at the type level: types beat tests, validate at every boundary, typed errors not raw throws, exhaustiveness over optionality.

**Part 2 — Stay in your lane (scope).** Four principles for scope discipline: the junior-dev rule, the budget gate, literal stop rules, the ratchet (escalate up, never around).

Read [PRINCIPLES.md](./PRINCIPLES.md) for the full doctrine. Read any skill's `SKILL.md` to see one projection of the principles onto one kind of work.

## Install

```
git clone --single-branch --depth 1 https://github.com/chughtapan/safer-by-default.git ~/.claude/skills/safer-by-default
cd ~/.claude/skills/safer-by-default
./setup
```

Requirements: `gh` (authenticated), `git`, `bash`, `bun` (for the template generator). Optional: [`zapbot`](https://github.com/chughtapan/zapbot) for richer publish paths (falls back to `gh` cleanly if absent).

## Skill catalog

Thirteen skills, grouped by modality.

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
