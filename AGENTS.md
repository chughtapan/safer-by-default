# AGENTS.md

Rules of engagement for any agent reading this repo. Read this *before* invoking any skill in `skills/`. Read [`PRINCIPLES.md`](./PRINCIPLES.md) for the full doctrine; this file is the operational summary.

## Read first

1. [`PRINCIPLES.md`](./PRINCIPLES.md) — four-part doctrine (craft, discipline, stamina, communication). Every skill projects from these principles.
2. The skill you're about to invoke. Read its `SKILL.md` end-to-end before running its workflow.
3. The parent epic's `## Contract` block (if dispatched by `/safer:orchestrate`). The contract bounds your autonomy — goal, acceptance criteria, autonomy budget, and always-park items.

## Skills by modality

| Modality | Skill | When to invoke |
|---|---|---|
| **Design** | `/safer:spec` | Ambiguous intent → spec doc |
| | `/safer:architect` | Approved spec → module layout + interface stubs |
| | `/safer:investigate` | Reproducible bug → root cause writeup |
| | `/safer:spike` | Feasibility question → throwaway code + verdict |
| | `/safer:research` | Open question → hypothesis ledger |
| | `/safer:ux-audit` | UI surface → heuristic findings |
| **Execution** | `/safer:implement-junior` | One module's internals; no public-surface change |
| | `/safer:implement-senior` | Cross-module within an approved plan |
| | `/safer:implement-staff` | New modules per approved spec |
| **Review / verify** | `/safer:review-senior` | Pre-merge PR review |
| | `/safer:verify` | Test run + acceptance check + ship/hold |
| | `/safer:dogfood` | Cold-start read of a docs artifact |
| | `/safer:docs-reader` | Multi-persona docs review |
| | `/safer:stamina` | Fan-out review for high-blast artifacts |
| **Bootstrap** | `/safer:setup` | One-time TypeScript repo bootstrap |
| | `/safer:typescript` | TS craft floor (auto-applied by `implement-*`) |
| **Orchestration** | `/safer:orchestrate` | Multi-modality intent → GitHub epic + sub-issues |

## Conventions

**Discipline over capability.** Just because a skill *can* do something doesn't mean it should. Stay in your lane. If the work needs a different modality, escalate via `safer-escalate --to <higher>` and stop.

**Artifacts are the record.** Every skill publishes its output to GitHub (issue, comment, PR review) before it considers itself done. Status lives in issue labels, not local files. No "trust me, I did it."

**Errors are typed.** Tagged unions or discriminated results. No `throw new Error("bad")`, no bare `catch {}`. Validate at every boundary; trust types inside the module.

**Stop rules are literal.** When a stop rule fires, halt. Do not "just keep trying." Produce the escalation artifact and stop.

**No sideways edits.** A bug fix in module A does not touch module B. Cross-module work routes to `/safer:implement-senior` or higher, not to a quick edit.

## Where things live

- **Skills**: `skills/<name>/SKILL.md` — one folder per modality. Each is self-contained.
- **CLI helpers**: `bin/safer-*` — auto-prepended to `PATH` in any session with the plugin enabled. Skills invoke them by bare name.
- **Doctrine**: [`PRINCIPLES.md`](./PRINCIPLES.md) at repo root.
- **Architecture map**: [`ARCHITECTURE.md`](./ARCHITECTURE.md).
- **Contract templates**: `docs/contracts/` — worked examples for orchestration contracts.
- **Calibration suite**: `scenarios/` — cc-judge eval scenarios for doctrine adherence.
- **Local state**: `~/.safer/analytics/events.jsonl` (modality events) and `~/.safer/last-update-check` (1h cache).
- **Pipeline state**: GitHub issues. Parent epic carries the contract; sub-issues track each modality's work.

## The update gate

User-initiated entry-point skills (`/safer:spec`, `/safer:architect`, `/safer:investigate`, `/safer:spike`, `/safer:research`, `/safer:setup`, `/safer:ux-audit`) halt at the preamble when `safer-update-check` reports an upgrade and `SAFER_PARENT_ISSUE` / `SAFER_SUBISSUE` are unset. The user is told to run `/plugin marketplace update safer-by-default` and `/plugin install safer@safer-by-default` before re-running.

`/safer:orchestrate` gates only on fresh-pipeline starts (no open `safer:parent` epic exists yet). Autonomous re-entry — cron-loop ticks, parent-epic polling — skips the gate so in-flight pipelines drain.

Dispatched skills (when running under `SAFER_PARENT_ISSUE`) skip the gate entirely. The pipeline finishes; the user upgrades after.

## Composition with gstack

safer-by-default treats [`gstack`](https://github.com/garrytan/gstack) as a hard dependency. Every safer skill that needs broad-toolbox capability (`/simplify`, `/review`, `/codex`, `/plan-eng-review`, `/plan-devex-review`, `/security-review`, `/ship`) calls into gstack inline. `/safer:setup` fails fast if gstack is absent.

Doctrine precedence: safer wins on scope; gstack ETHOS wins on quality-within-scope. See `PRINCIPLES.md` → "Composing with gstack" for the precedence rule and the `/investigate` name-collision rule.

User-prompting gstack skills run hold-scope autonomous when invoked from inside a safer skill body. User-facing prompts route up to `/safer:orchestrate`, which surfaces them via `AskUserQuestion`. No skill body initiates a user prompt directly.

## Anti-patterns (do not do these)

- **Sideways fix.** Touching module B because A's bug "kind of" routes through it. Escalate.
- **Skip the artifact.** "I did the work, here's a summary." Publish the artifact via `safer-publish` before declaring DONE.
- **Auto-amend the contract.** Contracts amend through explicit `AMEND CONTRACT:` comments authored by repo collaborators on the parent epic. Never inferred from a skill run.
- **Bypass the gate with `--no-update-check`.** No such flag exists. The gate exists because a stale skill body and a fresh remote can disagree on doctrine. Upgrade first.
- **Add a new modality on the fly.** New modalities ship through `/safer:spec` → `/safer:architect` → review, not as a one-line edit to `skills/`.
- **Fix tests by deleting them.** Tests fail because the code or the spec is wrong. Investigate.

## Adding a new skill

1. Read [`SKILL.md.tmpl`](./SKILL.md.tmpl) and copy it to `skills/<name>/SKILL.md`.
2. Fill in the sections. Match the conventions of an existing same-modality skill.
3. Update `.claude-plugin/marketplace.json` and `.claude-plugin/plugin.json` description if the skill count changes.
4. Add a row to the table at the top of this file.
5. Run `tests/run-tests.sh` to confirm nothing regressed.
6. Bump VERSION + add a CHANGELOG entry.

## When in doubt

Park. Post the parked state on the parent epic with what you tried, what's missing, and what you'd recommend. Wait for the contract amendment. Doing nothing is better than doing the wrong thing.
