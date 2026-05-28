# Composing safer skills with Claude Code Workflows

safer skills are **prose rulebooks** an agent reads and follows. Claude Code's **Workflow tool**
runs a deterministic JavaScript orchestration script (`agent()` / `parallel()` / `pipeline()`).
This doc explains where the two compose, where they must not, and how the four reference workflow
scripts in this repo stay faithful to doctrine.

## The boundary: deterministic fan-out vs. human-gated lifecycle

A skill's orchestration splits along one line:

- **Deterministic fan-out / barrier / pure reduce** — dispatch N independent passes, wait for all,
  combine their structured results with a pure function. This is exactly what a Workflow script is
  good at, and where prose orchestration is unreliable ("the model remembers to fire all N and
  aggregate them correctly").
- **Human-gated discipline** — the contract OK, ratchet-up-always-parks, the N budget, every stop
  condition, round-2/3 authorization. These are judgment gates, not deterministic predicates. A
  Workflow must **never** advance one.

A Workflow may own the first and must not own the second. Auto-chaining "consensus == DONE →
merge" across a ratchet boundary would turn the plugin's scope-discipline gates into rubber stamps
— the exact failure the doctrine exists to prevent.

This also keeps `review-senior` **Invariant 11** intact ("no code-level dispatcher; the routing
table IS the dispatcher; adding a second is a SPEC-revision trigger"): the Workflow **executes the
prose rulebook**, it is not a second, competing dispatcher. The prose stays authoritative.

## Feasibility limits (why skills cannot *depend* on Workflow)

1. **Subagents/teammates cannot invoke Workflow.** "Subagents cannot spawn other subagents." A
   skill dispatched as a teammate (e.g. stamina Mode B, any modality dispatched by orchestrate)
   has no Workflow tool. Only a **main-loop** agent (the user's session, or the orchestrate
   team-lead, or a cron-invoked orchestrate) can call it.
2. **Opt-in gated.** Workflow fires only when the session is in ultracode mode, the user included
   the word "workflow", or a saved workflow command runs. A skill saying "run this workflow" does
   not bypass the gate.
3. **Claude-Code-only.** Codex has no Workflow tool.
4. **Nested workflows blocked one level.** A Workflow's `agent()` calls cannot themselves spawn
   workflows — fine for leaf reviewers/personas, which is all these scripts dispatch.

Therefore every skill's prose rulebook is **authoritative** and is the required path for teammates,
Codex, and non-opted-in sessions. The Workflow path is an **opt-in optimization** for the
main-loop case, fenced as `### Workflow path (Claude Code, opt-in)` in each skill's SKILL.md.

> Implementation note: these scripts use top-level `await`/`return` (valid inside the Workflow
> harness's async wrapper). A standalone TS/JS parser — your editor's LSP, `node --check` — will
> mis-flag them. Validate by running them through the Workflow tool, not `node --check`.

## Per-skill verdict (all 18 skills)

| Skill | Fit | Why |
|---|---|---|
| `stamina` | **strong** | Already a fan-out → barrier → deterministic consensus reduce. Maps ~1:1; the Mode-A/Mode-B teammate-spawn detection dissolves in a Workflow runtime. |
| `docs-reader` | **strong** | 4 cold-start personas in parallel → severity-weighted aggregator (a pure function over a closed failure-mode enum). |
| `verify` | **strong** | Phase 3.5 dispatches up to 8 conditional gstack targets → verdict-precedence fold. Pure trigger evaluation + pure reduce. |
| `orchestrate` | **moderate** | The richest fan-out (the per-wave dispatch — see below), but wrapped in the contract gate, ratchet parks, and a cross-session lifecycle that cannot be one Workflow run. |
| `review-senior` | **moderate** | Dispatch-then-aggregate is scriptable, but Invariant 11 names the routing table as *the* dispatcher; a code dispatcher here is a SPEC-revision trigger. Composed targets are gstack `/`-skills, not `agent()` subagents. |
| `ux-audit` | **moderate** | Seven inspection protocols are a parallelizable sweep, but the goal/persona front gate is an `AskUserQuestion`, and most value is model judgment (goal-link, severity). |
| `research` | **moderate** | The round loop is scriptable (loop-until-confidence), but it is sequential (round N+1 depends on round N), and the codex supervisor must stay a genuinely separate cross-model call. |
| `contract-migrate` | **moderate** | A genuine loop-over-a-set (per-tracked-MODULE.md regenerate-and-diff), parallelizable, but the dry-run confirmation and the "diff = bug vs. drift?" call are human gates. |
| `diagnose` | **moderate** | Its only fan-out (N-direction forks) is delegated *up* to orchestrate and is a ratchet-up that always parks; the codex verdict must stay a separate cross-model opinion. |
| `dogfood` | none | N=1 by charter (one cold-start subagent). A primitive a workflow *calls*, not a workflow host. |
| `spike` | none | One question, one branch, one verdict. No fan-out. |
| `contract` | none | Single-author spec authoring behind the human contract gate; `AskUserQuestion` ambiguity resolution is irreducible. |
| `contract-init` | none | Single-folder export-graph read; deliberately de-CLI'd because the judgment can't be mechanized. |
| `architect` | none | Single-author design; the Iron Rule (ship everything but the bodies) is a model brake. |
| `implement-junior` / `-senior` / `-staff` | none | Single-author, single-PR. The scope brakes (Budget Gate, Ratchet, stop rules) are model-driven. |
| `setup` | none | Already a deterministic bash spine, gated by many `AskUserQuestion` prompts; no agents to orchestrate. |

## The four reference workflows

Each is a runnable, faithful encoding of its skill's deterministic core, with the gate-preservation
invariants encoded literally. Shared pure functions live in a `.mjs` (canonical, tested); the
scripts inline a mirror because Workflow scripts cannot import local files.

- **`skills/orchestrate/dispatch-wave.workflow.js`** (centerpiece) — runs ONE dispatch wave:
  computes the ready set (`ready-set.mjs`), fans out the ready modalities in parallel with
  `isolation:'worktree'`, awaits all, returns structured receipts. Replaces the Step 5d `CronCreate`
  poll loop, swarm-socket discovery, dead-pane cleanup, per-tick cap math, and marker-parsing.
  **Gates nothing** — every receipt returns to the prose lifecycle, which applies the contract
  gate, the ratchet, and the stop conditions between waves. The cross-session lifecycle stays prose.
- **`skills/stamina/dispatch.workflow.js`** — fans out N reviewers, reduces to the Phase-4 consensus
  (`consensus.mjs`). No auto-merge, no label transition; BLOCKED/ESCALATED ratchet upstream,
  NEEDS_CONTEXT parks; never reads the diff (Iron Rule).
- **`skills/verify/phase35.workflow.js`** — evaluates the 8 Phase-3.5 triggers, dispatches only the
  fired targets (report-only forms — verify never self-edits), folds via the precedence table. Ring
  1 and the final SHIP/HOLD stay in verify.
- **`skills/docs-reader/personas.workflow.js`** — 4 cold-start personas (isolation is the iron
  rule), deterministic severity-weighted aggregator. Runs exactly one round; round 2/3 stay human
  gates; CONTRADICTION escalates; emit-only.

## How to run one

From a main-loop session that has opted in (ultracode, or include "workflow" in your ask):

```text
Workflow({ scriptPath: "skills/stamina/dispatch.workflow.js", args: { dispatchSet, n, mode, targetUrl, atCeiling } })
```

The skill's prose assembles `args` from GitHub / `safer-diff-scope` first, then invokes the
Workflow, then applies the gates to the returned receipts. On Codex, as a dispatched teammate, or
without opt-in, follow the skill's prose rulebook directly — it is authoritative and complete.

## A note on the SPEC

Invariant 11 is defined in "SPEC r4.1 §5(h)", which is not checked into this repo. The
reconciliation above (a Workflow executes the rulebook; it is not a second dispatcher) is recorded
here and in `PRINCIPLES.md` Part 3; the authoritative SPEC's owner should mirror it.
