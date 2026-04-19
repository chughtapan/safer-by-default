# moltzap migration — v1 spec

**Modality:** spec (plan-class deliverable; see `/safer:spec`)
**Parent issue:** chughtapan/safer-by-default#89
**Research ledger:** chughtapan/safer-by-default#82 (HIGH confidence, 0.91)
**Status:** draft for `plan-approved`
**Date:** 2026-04-19

## 0. Framing

Replace the tmux-pane + inbox-file dispatch used by `/safer:orchestrate` with moltzap-registered agents exchanging messages over the existing moltzap server, without protocol changes to moltzap and without losing `claude --resume` session continuity. v1 runs tmux and moltzap side-by-side behind a per-repo env flag so every phase has a 5-minute rollback.

The shape of the work is fixed by research (sbd#82):

- **Two new packages** (not three): `@moltzap/cli-channel` (listener) and `@safer/dispatch-moltzap` (dispatch strategy). Operator CLI subcommands fold into the existing `@moltzap/client` CLI rather than a third package (sbd#82 I7, Round 7–8).
- **Four-repo rollout**, `sbd → ccj → acg → zapbot`, each gated on its own env flag (sbd#82 I6 + migration table).
- **tmux retained 30 days** post-final-cutover (sbd#82 migration table, phase 5).
- **Cold-start p95 ≤ 2.92s** and **resume p50 ≈ 0.72s** are measured baselines (sbd#82 I5, n=10 / n=4); well under the 5s dispatch budget called out in sbd#72.

Per-package public interfaces, concrete schemas, file-level layouts, and test scaffolding belong to `/safer:architect` and are out of scope here (Principle 5). Sections below name what must be true about each package; they do not pick libraries beyond what research already fixed, and they do not write code.

---

## 1. Package specs

The deliverable is three units of work. The count matches issue #89's framing; packaging count is two (unit C lands inside an existing package per sbd#82 I7).

### 1.A — `@moltzap/cli-channel`

**Location.** `packages/cli-channel/` in the moltzap monorepo (home: `/home/tapanc/moltzap`), mirroring the `packages/nanoclaw-channel/` and `packages/openclaw-channel/` precedents listed in `moltzap/README.md`.

**Purpose.** A long-running listener: subscribes to inbound moltzap messages on behalf of one registered agent; spawns `claude -p` per inbound message against a per-conversation workspace; posts the model reply back to moltzap; persists Claude session ids so subsequent turns use `--resume <sid>`.

**Dependencies (required).**
- `@moltzap/app-sdk` (workspace) — the "app built on moltzap" primitive (`MoltZapApp`, message subscription, heartbeat, reconnection). Research I1 fixes this scaffold choice against `packages/app-sdk/src/app.ts:60..90`.
- `@moltzap/protocol` (workspace) — typebox schemas for message parts.
- Node built-ins only for process management (`child_process`, `fs/promises`, `path`). **No** new npm dependencies beyond what `@moltzap/app-sdk` already pulls — open question Q1 confirms this.

**Dependencies (forbidden in v1).**
- Any moltzap **server-core** import. The channel is a client-side app.
- Any framework that implies multi-host HA (Redis, etcd, zookeeper). HA is out of scope (sbd#82 I3, R2).
- Any pre-warm or daemonization framework (pm2, systemd wrappers). Rejected by H5 (sbd#82).

**API surface (spec-level, not the final signatures).**
- A single factory that accepts a config object and returns a handle exposing `start()`, `stop()`, and observable lifecycle events. The exact signature is architect-stage work.
- Config must cover: moltzap server URL, agent API key, agent display name, CLI binary path, CLI arg vector, per-call CLI timeout, workspace root, session-store path, lease path, and an `ephemeral` boolean for GHA mode. The config surface is fixed by research I4 + I8; defaults are architect-stage work.
- No public exports beyond the factory, the config type, and a small error-code enum. Internal helpers (FIFO queue, session-store reader/writer, lease manager, CLI spawner) are non-exported per Principle 5 (Junior Dev Rule — module boundaries are load-bearing).

**Error handling (contract, not code).**
- Exactly three terminal CLI failure modes, each surfaced as a reply in the inbound conversation: **ENOENT** (CLI binary missing → instruct user to install), **non-zero exit** (include exit code + last N lines of stderr), **timeout** (configurable per-call ceiling; default 120s per I4).
- Session-id resolution failures (`--resume` against a sid Claude no longer recognizes) retry once **session-less** and drop the sid from the store. This is the 5-LoC recovery path from I4 (sbd#82 Round 4). This is not a user-visible error.
- Per-conversation FIFO is **mandatory**; I2 is explicit that parallel `--resume <sid>` on the same session races Claude's transcript file. Violating this is a correctness bug, not a performance one.
- Lease file: 30s refresh, 60s stale-abort. Second-host start against an occupied lease must fail with a clear error message naming the host in the lease (R2 mitigation).
- Crash-recovery for in-flight messages is delegated to moltzap's missed-message fetch on reconnect. The channel does **not** keep an on-disk queue.

**Invariants.**
- One cli-channel process per registered moltzap agent, per host (lease-enforced).
- Per-conversation ordering: for any `conversationId`, replies post in the same order inbound messages arrived.
- `--resume <sid>` never runs concurrently for the same sid.
- Session-store writes are atomic (tmp-file + rename).
- Workspace directories are never auto-deleted (H4 rejected auto-TTL; prune is explicit operator action).

**Test plan (acceptance-level, architect will refine).**
- Unit: happy path (inbound → CLI spawn → reply posted → session persisted).
- Unit: each of the three error modes produces the expected error reply shape.
- Unit: session-not-found on `--resume` drops the sid and retries session-less.
- Unit: FIFO order preserved under n=100 concurrent inbound messages to the same conversation.
- Unit: second-host start against occupied lease fails with stated error.
- Integration against a local moltzap server: round-trip a single message; assert `.session_id` is captured from `claude -p --output-format json` stdout per I4.
- Integration: 10-message session with `--resume` continuity, asserting turn-N recalls turn-(N-1) content. This reproduces the 2.15s wall-clock resume observation from sbd#82 Round 4.

**LoC target.** ~220 (sbd#82 I2). Budget-gate signal only; not a pass/fail criterion.

---

### 1.B — `@safer/dispatch-moltzap`

**Location.** A new workspace package in `/home/tapanc/safer-by-default`. The repo currently has no `packages/` directory — architect must decide whether to introduce one or to ship this as a sibling to `bin/` and `skills/`. Both are within Principle-5 bounds for a new module; architect makes the call.

**Purpose.** The orchestrate-side "dispatch strategy" abstraction: given a sub-issue that has reached `plan-approved`, create (or reuse) a DM conversation with the target teammate agent and post the dispatch prompt. Also: given a teammate, expose an async stream of inbound messages (the teammate's reply path). This is what the `/safer:orchestrate` skill calls instead of `tmux split-pane` + `Agent(team_name=…)` when `SAFER_DISPATCH=moltzap`.

**Dependencies (required).**
- `@moltzap/app-sdk` — consumed as an **external npm dependency**, not workspace. safer-by-default is not part of the moltzap monorepo.
- `@moltzap/protocol` — same.
- No coupling to `@moltzap/cli-channel`. The dispatch side doesn't spawn Claude; it talks to a channel that does.

**Dependencies (forbidden in v1).**
- Direct moltzap server HTTP calls (use `@moltzap/app-sdk`, which normalizes retry/reconnect).
- Any tmux import or shell-out to tmux. Strict separation — tmux path is a parallel module the orchestrate skill selects by env flag, not a fallback the moltzap strategy layers over.

**API surface (spec-level).**
- A `DispatchStrategy` interface with three operations: `dispatchTask(task, teammate) → { conversationId }`; `readInbox(teammate) → AsyncIterable<Message>`; `markAvailable(teammate) → Promise<void>`. Exact signatures are architect-stage.
- A factory that returns the moltzap implementation of that interface. Taxonomy-wise: the **interface** lives in the orchestrate skill's work (so the tmux path can also implement it); the moltzap **implementation** lives in this package. Architect decides whether the interface file lives here, in sbd root, or in the orchestrate skill directory.
- `taskId ↔ conversationId` mapping persisted to `~/.moltzap/cli-channel/task-conv-map.json` (shared path with cli-channel by design: both reader and writer) with atomic-write discipline identical to the cli-channel session store.

**Error handling.**
- `dispatchTask` must flush the mapping file **before** posting the first message. Posting-first-then-writing would orphan the conversation on crash.
- Reconnect during `readInbox` must be transparent: `@moltzap/app-sdk` handles transport reconnection; this package retries at most once on application-level replay gaps before surfacing.
- No "graceful downgrade to tmux" path. If moltzap is unreachable and this strategy was selected, fail loudly and let the orchestrate loop decide to flip the env flag (manual operator action). Silent fallback would hide the kind of incident the rollback contract (§2) is designed to be triggered by.

**Invariants.**
- Exactly one DM conversation per `taskId` — reused across re-dispatches; never created twice.
- The `taskId → conversationId` file is append-only during a migration phase (entries removed only by explicit `moltzap cli-channel prune`).
- `readInbox` yields messages in moltzap-server order for a given conversation.

**Test plan (acceptance-level).**
- Unit: `dispatchTask` creates conversation on cold path, reuses on warm path.
- Unit: mapping file flushed atomically before first message post.
- Unit: `readInbox` correctly demultiplexes messages across multiple conversations.
- Integration with a local moltzap server: full dispatch round-trip (orchestrate ↔ cli-channel ↔ Claude binary), asserting message arrives and session-id survives across turns.
- Integration: env-flag override routes through tmux path when `SAFER_DISPATCH=tmux` is set even while the moltzap strategy is constructed — verifies non-coupling at the orchestrate call site.

**LoC target.** ~150 (sbd#82 I2).

---

### 1.C — CLI subcommands in `@moltzap/client`

**Location.** New file(s) under `packages/client/src/cli/commands/` in the moltzap monorepo, alongside existing CLI commands. Research I7 fixes this as the correct home — the existing CLI has registration, config, and socket-path plumbing (`packages/client/src/cli/config.ts:17`, `packages/client/src/service.ts:289` per sbd#82 I3).

**Purpose.** Operator surface for running and maintaining cli-channel listeners on a host.

**Dependencies.**
- `@moltzap/cli-channel` (workspace, consumer of 1.A).
- Existing `@moltzap/client` CLI framework (no new top-level deps).

**Subcommands to cover.**
- `moltzap cli-channel register --name <n> --server <url>` — creates an agent via the existing HTTP register endpoint shown in `moltzap/README.md:17..25`; appends to a declarative `agents.yaml`.
- `moltzap cli-channel start --config agents.yaml` — boots N listeners from that YAML; supervises them in-process; exits clean on SIGTERM. Must honor `MOLTZAP_CLI_CHANNEL_EPHEMERAL=1` for GHA mode (I8).
- `moltzap cli-channel prune --older-than <duration>` — removes workspace directories and matching session-store entries older than the given duration. Idempotent.
- `moltzap cli-channel status` — prints agent name, connection state, workspace count, and last-inbound timestamp. Must read from on-disk state even when the daemon is **not** running, so operators can inspect state after a crash.

**Error handling.**
- `register` must handle moltzap server 4xx/5xx distinctly from network errors and print actionable messages.
- `start` must refuse to boot if the lease file exists and is fresh; error message must name the holding host.
- `prune` must never delete a workspace whose session-id is currently pinned by an in-flight lease. Enforce by reading lease first.
- `status` must print "daemon not running" cleanly (not an error) when no process holds the lease.

**Invariants.**
- All four subcommands are idempotent except `register`, which is create-once.
- `start` runs to terminal signal; it does not background itself. Operators who want daemonization use their OS supervisor (systemd/launchd/docker). This matches moltzap precedent (`packages/server/src/standalone.ts`).

**Test plan.**
- Unit per subcommand: happy path + one error path each.
- Integration: `register → start → send a message via @moltzap/client → see reply → stop → prune --older-than 0 → status shows empty`. This is the cold-start acceptance for the operator surface.

**LoC target.** ~100 (sbd#82 I2).

---

## 2. Per-repo migration runbook

Source order and rollback contract are from sbd#82's migration-sequencing table and I6. The generic runbook below applies to each repo; repo-specific deltas follow.

### 2.0 Generic runbook (four steps per repo)

1. **Pre-flight.** Confirm `@moltzap/cli-channel` and `@moltzap/client` CLI changes are on npm at the version the repo will pin. Confirm `@safer/dispatch-moltzap` builds green against that version. Confirm the repo's CI has the env flag wired (see §3).
2. **Agent registration.** On the host(s) that will run this repo's teammates, run `moltzap cli-channel register` per teammate role (one agent per role: `researcher`, `architect`, `implement-junior`, etc.). Commit the resulting `agents.yaml` to the repo (non-secret: names + server URL only; API keys go to the host keystore / GHA secrets).
3. **Cutover.** Set the per-repo env flag to `moltzap` (see §3 for variable name). Dispatch a canary sub-issue that exercises spec → architect → implement-junior → verify, end to end. Observe dispatch p95 latency and session-continuity on the canary.
4. **Soak.** Run normally for the per-phase soak duration (§7). Keep the tmux path available; do not yet delete tmux code.

### 2.1 safer-by-default (sbd) — Phase 1

- Runbook per §2.0.
- Canary sub-issue: one `safer:implement-junior` sub-task on a toy module with a ≤20-LoC change. The pair (`dispatch → implement-junior → review-senior`) is the acceptance loop per sbd#82 migration-table phase 1.
- **Exit criterion (sbd#82 phase 1 row):** three consecutive green dispatch cycles end-to-end across the spec → architect → implement-junior → verify chain.
- **Rollback:** set `SAFER_DISPATCH=tmux` (the default); no code changes required. RTO < 5 minutes (sbd#82 I6).

### 2.2 cc-judge (ccj) — Phase 2

- Runbook per §2.0. `@moltzap/cli-channel` listeners run per-judge-role.
- **Exit criterion (sbd#82 phase 2 row):** Stryker mutation-test suite passes on a moltzap-dispatched ccj run. Stryker was wired as a required gate in the commit series `46745e2` / ccj PR #7, so this is a non-negotiable binary signal.
- **Rollback:** `CCJ_DISPATCH=tmux`. RTO < 5 minutes.

### 2.3 agent-code-guard (acg) — Phase 3

- Runbook per §2.0.
- acg is interactive (author-in-the-loop review of PR diffs). Rollout is **opt-in per author**: authors who want to dogfood set the flag; others do not. This is the narrowest change in the sequence because the UX contract is human-facing.
- **Exit criterion (sbd#82 phase 3 row):** participating authors confirm unchanged UX across at least one full week of day-to-day use.
- **Rollback:** `AGENT_CODE_GUARD_DISPATCH=tmux` (flag naming: §3). RTO < 5 minutes.

### 2.4 zapbot — Phase 4

- Runbook per §2.0 with an additional GHA step: set `MOLTZAP_CLI_CHANNEL_EPHEMERAL=1` and configure `actions/cache@v4` keyed on the workflow run such that the session store survives job retries but is explicitly ephemeral across workflow runs (sbd#82 I8).
- The moltzap server URL and per-agent API keys are GHA repository secrets.
- Cache-miss on the session store is **acceptable**: cli-channel's session-not-found recovery (I4) drops the sid and retries session-less, which is correct behavior in a fresh runner. This is the R3 mitigation from sbd#82.
- **Exit criterion (sbd#82 phase 4 row):** one full spec → ship cycle green on a live PR.
- **Rollback:** `ZAPBOT_DISPATCH=tmux`. Because zapbot runs in CI, a rollback is a single repo-variable flip (not a code push). RTO < 5 minutes (bounded by GitHub's variable-propagation).

### 2.5 Soak + teardown

- **Phase 5 (30 days, all repos):** both paths retained; tmux is the fall-back. This is sbd#82's migration-table phase 5. No production re-plumbing; watch for the backout triggers listed in sbd#82 I6 (Stryker regression > 5%, dispatch p95 > 5s, session-not-found rate > 1% of turns).
- **Phase 6 (separate milestone):** delete tmux dispatch code. Out of scope for this spec.

### 2.6 Rollback decision contract (per sbd#82 I6)

Rollback is **mechanical**, not discretionary, and is triggered by any of:

1. Stryker regression > 5% on moltzap-dispatched runs (ccj).
2. Dispatch p95 latency > 5s for ≥ 2 consecutive hours.
3. Session-not-found rate > 1% of all `--resume` attempts (per sbd#82 I4).

On trigger: flip the per-repo env flag to `tmux`; file a sub-issue labeled `safer:investigate` naming the trigger and last known-green commit; do not re-flip until investigation closes.

---

## 3. Env-flag scheme + backward-compat

### 3.1 Variable names

| Repo | Variable | Values | Default (v1) |
|---|---|---|---|
| safer-by-default | `SAFER_DISPATCH` | `moltzap` \| `tmux` | `tmux` |
| cc-judge | `CCJ_DISPATCH` | `moltzap` \| `tmux` | `tmux` |
| agent-code-guard | `AGENT_CODE_GUARD_DISPATCH` | `moltzap` \| `tmux` | `tmux` |
| zapbot | `ZAPBOT_DISPATCH` | `moltzap` \| `tmux` | `tmux` |

Per-repo names (rather than a single `DISPATCH_STRATEGY`) keep the four rollout phases independent — flipping sbd does not implicitly flip ccj.

Additional moltzap-side variables (shared):

| Variable | Owner | Purpose |
|---|---|---|
| `MOLTZAP_SERVER_URL` | cli-channel + dispatch-moltzap | server endpoint |
| `MOLTZAP_AGENT_KEY` | cli-channel | per-listener API key (host keystore / GHA secret) |
| `MOLTZAP_CLI_CHANNEL_EPHEMERAL` | cli-channel | `1` enables GHA mode (workspace at `$RUNNER_TEMP`, no lease) per sbd#82 I8 |

### 3.2 Default posture during migration

During Phases 1–4, default is `tmux` on every repo. The dispatch strategy is selected **only** when the env flag is explicitly set to `moltzap`. Rationale: a missing/empty variable must not silently enable a new path — Principle 7 (Brake).

### 3.3 Backward-compat invariants

- Neither path requires the other to be installed. A repo with `SAFER_DISPATCH=tmux` must work on a host with no moltzap client installed; a repo with `SAFER_DISPATCH=moltzap` must work on a host with no tmux (this second direction is the one that unblocks zapbot in GHA).
- The orchestrate skill's sub-issue state labels (`planning`, `review`, `plan-approved`, `implementing`, `verifying`, `done`, `abandoned`) are unchanged. No label rename, no schema migration. Per-repo env-flag flip is the only operator-visible change.
- Artifact-discipline is unchanged: every modality still publishes to GitHub. moltzap is a dispatch transport, not an artifact store.
- During Phases 1–4, any sub-issue started on one path must complete on the same path. Operators do not flip the env flag mid-task. This invariant is not enforced by code; it is a runbook rule (§2.6 rollback excepted: a trigger aborts in-flight work by design).

---

## 4. Phase-0 Dockerfile fix

**Scope.** This is a prerequisite to Phase 1, not a feature. It is listed separately from the rollout (§7) because it is upstream of every integration test the other sections call for.

**Symptom (sbd#82 R5, CONFIRMED):** `docker compose -f docker-compose.example.yml up -d --build` fails with `pnpm filter build exit 2` during the moltzap server container build. This blocked the end-to-end latency measurement Q-FU3 during research and will block every integration test in §1.A, §1.B, and §1.C if not fixed first.

**Acceptance criteria (for architect, not for this spec).**
- `docker compose -f docker-compose.example.yml up -d --build` completes green from a clean checkout of `/home/tapanc/moltzap` on a stock Ubuntu 22.04 host.
- The resulting server container passes `/healthz` (or the equivalent existing check) within 30s of `up`.
- The fix is a **one-commit surgical change** to the Dockerfile / `docker-compose.example.yml` / `pnpm-workspace.yaml` triad. Not a refactor. Not a build-system migration.
- The fix does not introduce a new base image or a new Node version. Version changes are separate scope.

**Out of scope for Phase-0.**
- Any change to the server's runtime behavior.
- Any change to published-package names or versions.
- CI wiring for the fixed Dockerfile (that follows Phase-0 in Phase-1 pre-flight).

**Dispatch.** File this as a standalone sbd sub-issue labeled `safer:investigate` (root-cause) + `safer:implement-junior` (fix). One-commit change. This spec does **not** attempt the diagnosis — per Principle 5, that is an investigate-modality artifact.

---

## 5. Phase-1 gate measurements

Two measurements gate exit from Phase 1 to Phase 2, in addition to the "three consecutive green dispatch cycles" criterion already stated in §2.1.

### 5.1 Q-FU4 — resume-time vs transcript size (sbd#82 load-bearing)

**Why gating.** Research I5 measured resume p50 = 0.72s at **n=4** on short transcripts. R1 names resume-time scaling as a MED likelihood risk. Q-FU4 is tagged load-bearing because it decides whether the v1 design survives real long sessions or needs the v2 `stream-json` long-running mode (scoped separately, not here).

**Procedure.**
- Exercise a 100-turn session on a sbd teammate under `SAFER_DISPATCH=moltzap`.
- Sample `claude -p --resume <sid>` wall-clock at turns 10, 25, 50, 75, 100. 10 samples per point. Total n = 50.
- Record the per-point p50 and p95.

**Gate thresholds.**
- **Pass:** p95 at turn 100 ≤ 2s.
- **Degrade:** p95 at turn 100 > 2s and ≤ 5s → ship Phase 2 but open a spike sub-issue for `stream-json` long-running mode.
- **Fail:** p95 at turn 100 > 5s → halt Phase 2; re-triage to `/safer:spike` for the long-running-mode design before ccj rollout.

**Ownership.** `implement-staff` for the module under test; data gathered during sbd dogfooding in Phase 1.

### 5.2 FU2 — long-session subscription behavior

**Context.** sbd#82 Q-FU2 flags `MoltZapApp.onMessage` wildcard-vs-per-key subscription as unread at research time. A wrong subscription model would silently drop reply messages in long conversations.

**Procedure.**
- During the 100-turn Q-FU4 run, assert every reply posted from cli-channel is delivered to the `@safer/dispatch-moltzap` `readInbox` consumer.
- Expected: 100 replies seen. Zero dropped.

**Gate threshold.** Any dropped message fails the gate. No soft-degrade.

### 5.3 Out of scope for Phase-1 gates

- Cross-host HA (R2, deferred to v2+).
- Multi-agent simultaneous sessions > 10 (not in zapbot's realistic workload profile).
- Encryption-enabled message paths (existing moltzap encryption is opt-in and orthogonal).

---

## 6. Orchestrate skill changes

The changes below fit inside the existing `/safer:orchestrate` SKILL.md and its sibling files under `skills/orchestrate/`. Architect decides the exact file-level edits; the spec scope is what must become true.

### 6.1 Abstraction: a dispatch strategy boundary

Orchestrate today dispatches by calling `TeamCreate` + `Agent(team_name=…)`, which in practice becomes a tmux-pane split. A reader of `skills/orchestrate/SKILL.md:95`, `:263`, `:402`, `:442–519`, and `:515–525` will find tmux references woven through Phase 5, dead-pane cleanup, and capacity accounting.

This is the R4 risk from sbd#82 (MED likelihood): tmux assumptions are not confined to a single call site. The v1 change must **not** attempt to wholesale remove tmux — it must route through a strategy abstraction and land the moltzap implementation behind the env flag.

**What must be true after v1:**
1. A named "dispatch strategy" boundary exists in the skill's doctrine, with exactly two implementations in v1: `tmux` (the current behavior, now named) and `moltzap` (new, powered by `@safer/dispatch-moltzap`).
2. The env flag (§3.1) selects between them at the skill-entry boundary — a single read at the top of Phase 5, not threaded through every step.
3. Every tmux call site in `SKILL.md` (dead-pane cleanup, capacity accounting, `kill-pane`, `list-panes -a -F '#{pane_id}'`) is reachable **only** on the `tmux` path. The `moltzap` path has its own equivalents: "dead agent" = cli-channel listener not reporting heartbeat; "capacity" = count of live conversations vs. a budget per host.
4. Phase 5a's "auto-dispatch" step 6 (introduced by commit `3e1ee8d`) works on both paths. The marker-filter work queue is agnostic to transport.

### 6.2 Specific doctrinal deltas

- **SKILL.md §Dispatch (line 263 area):** generalize "Dispatch via a team. First `TeamCreate`…" to "Dispatch via the configured strategy. The `tmux` strategy uses `TeamCreate` + `Agent(team_name=…)`. The `moltzap` strategy uses `@safer/dispatch-moltzap`."
- **SKILL.md §Dead-pane cleanup (line ~442–478):** generalize "pane" → "teammate process". Tmux-specific commands (`tmux list-panes`, `tmux kill-pane`) stay under the `tmux` strategy. The `moltzap` strategy reads cli-channel heartbeat from the moltzap server presence API.
- **SKILL.md §Capacity (line ~515–525):** the "pane ceiling 20" is tmux-specific. The `moltzap` path has a separate host-level budget (architect decides). Both budgets live in the strategy, not in the outer loop.
- **SKILL.md §Stop rules:** add a rule: "`"no space for new pane"` is a `tmux`-strategy signal; on the `moltzap` strategy, the equivalent is a moltzap `rate_limited` error. Both abort the tick identically."
- **SKILL.md anti-patterns:** add "do not silently fall back from `moltzap` to `tmux` on error — §2.6 rollback is explicit operator action."
- **Dispatch prompt templates** (§Per-modality dispatch prompt templates referenced at `SKILL.md:402`): unchanged. Prompts are transport-agnostic.

### 6.3 What v1 does **not** change

- The sub-issue label taxonomy.
- The parent-epic structure.
- `safer-publish`, `safer-transition-label`, `safer-heartbeat`, `safer-reconcile` binaries. They are transport-agnostic.
- Step 6's work-queue scan + auto-dispatch (commit `3e1ee8d`).
- The team-lead role. Team-lead continues to live in pane 0 on the `tmux` path and as a designated moltzap agent on the `moltzap` path; its responsibilities are identical.

---

## 7. Rollout timeline with per-repo advance gates

Durations are **minimums**. An advance-gate miss holds the phase open; no phase auto-advances on calendar time alone. The sequence is fixed by sbd#82.

| Phase | Min duration | Repo(s) | Entry gate | Exit gate |
|---|---|---|---|---|
| 0 | 1 week | moltzap | `plan-approved` on #89 | Dockerfile §4 green; `@moltzap/cli-channel` + `@moltzap/client` CLI subcommands published to npm; `@safer/dispatch-moltzap` builds green against that version |
| 1 | 1 week | sbd | Phase 0 exit | §2.1 three-green-cycles **AND** §5.1 Q-FU4 gate **AND** §5.2 FU2 gate |
| 2 | 1 week | ccj | Phase 1 exit | §2.2 Stryker green on moltzap-dispatched run |
| 3 | 1 week | acg | Phase 2 exit | §2.3 authors confirm unchanged UX across 1 week |
| 4 | 1 week | zapbot | Phase 3 exit | §2.4 one full spec → ship cycle green on a live PR |
| 5 | 30 days | all | Phase 4 exit | no §2.6 backout event across the window |
| 6 | — | — | Phase 5 exit | (separate milestone — delete tmux dispatch path) |

**Gates are AND-composed.** Phase 1 exit requires all three (three-green + Q-FU4 + FU2). A soft-degrade on Q-FU4 (§5.1) does not block Phase 2 but does open a follow-up spike.

**Backout during any phase** reverts to the prior phase's configuration per §2.6 and §3.2.

---

## 8. Rejected alternatives

### 8.1 One-big-bang migration (all four repos cut over simultaneously)

**Rejected.** The rollback contract (§2.6, sbd#82 I6) requires per-repo RTO < 5 minutes. A big-bang cutover collapses four independent rollbacks into one, which (a) forces a retreat across unrelated blast radii on any single trigger, and (b) makes it impossible to attribute a Stryker regression on ccj to the dispatch change vs. some unrelated ccj commit. Per-repo sequencing is the cheapest form of insurance available.

### 8.2 Keep tmux forever (no migration)

**Rejected.** Two blocking constraints make this non-viable:

- **GHA zapbot (sbd#82 I8, R3).** GHA runners are ephemeral and do not support long-running tmux panes across job boundaries. zapbot is already awkwardly pinned to tmux and would remain so.
- **Multi-agent scaling (sbd#82 Round 5, R2).** Tmux's pane ceiling (empirically ~20 per `SKILL.md:515`) is a hard cap on concurrent teammates. moltzap's message transport has no equivalent cap at v1 scale. "Keep tmux forever" freezes the team size.

### 8.3 moltzap-native "teams bundle" (a single moltzap package that bundles both cli-channel and dispatch-moltzap)

**Rejected.** This was the implicit framing before sbd#82 Round 7–8 split the packages. The reasons for splitting (documented in sbd#82 I7):

- **Different repos.** `@moltzap/cli-channel` lives in the moltzap monorepo (alongside `nanoclaw-channel` and `openclaw-channel`, which it is shaped like). `@safer/dispatch-moltzap` lives in safer-by-default. Bundling them would force safer-by-default to vendor-in code from the moltzap repo or vice-versa.
- **Different consumers.** `cli-channel` is consumed by operators on agent-runner hosts (and by GHA runners). `dispatch-moltzap` is consumed by the orchestrate skill in safer-by-default. They share a persisted-file contract (`~/.moltzap/cli-channel/`), not a code path.
- **Different release cadences.** The operator surface (cli-channel + CLI subcommands) is moltzap release cadence. The dispatch strategy is tied to `/safer:orchestrate` changes.

A shared types package (e.g. `@moltzap/cli-channel-protocol`) is a reasonable v2 refactor if a third consumer appears. v1 uses file-shape contracts documented in §1.A and §1.B plus the sbd#82 I3/I4 fixtures.

### 8.4 Pre-warm pool of idle `claude` processes

**Rejected (sbd#82 H5).** 1s first-turn savings at the cost of 50–100 MB RAM per idle process. Poor trade at v1 scale; may revisit at Phase 6 if the concurrent-agent count grows past the point where cold-start latency becomes user-visible.

### 8.5 Auto-TTL cleanup of workspaces

**Rejected (sbd#82 H4).** Silent loss of resumable conversations is worse than a disk-fills alert. Explicit `moltzap cli-channel prune` aligns with moltzap's no-magic-cleanup precedent.

### 8.6 Session-id via reserved message part or conversation metadata

**Rejected (sbd#82 H2, H3).** Message-part leaks UUIDs to peers and introduces ordering hazards; metadata field requires a moltzap protocol change that sbd#72 explicitly forbade. Sidecar JSON map (I4) is the decision on record.

---

## 9. Assumptions (user to confirm)

1. The moltzap monorepo is the correct home for `@moltzap/cli-channel` and the CLI subcommand changes. Alternative: a separate `safer-moltzap-channel` package outside the moltzap monorepo. Assumed **no**.
2. safer-by-default's `@safer/dispatch-moltzap` package introduces a `packages/` directory to a repo that currently has none. Alternative: ship as a subdirectory of `bin/` or `skills/orchestrate/`. **Architect decides**; this spec does not pre-commit.
3. The per-repo env flag naming in §3.1 is acceptable. Alternative: one shared `DISPATCH_STRATEGY` variable. Assumed **per-repo**, to decouple rollout phases.
4. 30-day soak in Phase 5 starts at Phase 4 exit, not at Phase 1 exit.
5. The `--output-format json` contract on `claude -p` is stable across the Phase-0-through-Phase-5 timeline. If Claude's CLI changes the shape of the `.session_id` field in the interim, it is a blocking incident for the whole rollout.
6. zapbot's GHA secret-propagation timeline is acceptable as the upper bound on §2.4 rollback RTO.

---

## 10. Open questions (recommended defaults stated)

1. **Should `@safer/dispatch-moltzap` define the `DispatchStrategy` interface, or should it live in the orchestrate skill's directory?**
   **Options:** (A) in the package; (B) in the skill; (C) in a third shared module.
   **Recommended default:** (B) — the skill owns its own extension points. Architect to confirm.
2. **Should `MOLTZAP_CLI_CHANNEL_EPHEMERAL=1` disable the lease file entirely, or use a transient lease at `$RUNNER_TEMP`?**
   **Options:** (A) no lease in ephemeral mode; (B) transient lease in runner tempdir.
   **Recommended default:** (A) — single-runner invariant in GHA makes the lease unnecessary and adds a failure mode (stale lease from a previous run). Confirm against sbd#82 I3/I8.
3. **Phase-0 Dockerfile fix — does the one-commit budget hold, or is a larger refactor warranted?**
   **Options:** (A) one-commit surgical fix; (B) allow a scoped refactor if the root cause is structural.
   **Recommended default:** (A) — a refactor turns a prerequisite into a deliverable. If diagnosis reveals a structural issue, re-file as a separate `safer:architect` sub-issue.
4. **Does the FU2 gate (§5.2) need to run against both a local moltzap server and a remote one, or is local sufficient for Phase 1?**
   **Recommended default:** local sufficient. Remote latency is a Phase 4 (zapbot) concern.
5. **`@safer/dispatch-moltzap` consumes `@moltzap/app-sdk` as an external npm package — is the published version mature enough for sbd's pinning policy?**
   **Recommended default:** pin to the version released at Phase 0 exit. If the published package is pre-1.0, architect should propose a vendoring strategy separately.

---

## 11. Acceptance criteria (rolled up)

- [ ] Phase-0 Dockerfile fix lands; `docker compose up -d --build` green on stock Ubuntu 22.04.
- [ ] `@moltzap/cli-channel` published to npm with the API surface and invariants of §1.A.
- [ ] `@moltzap/client` gains the four CLI subcommands of §1.C, each with §1.C invariants.
- [ ] `@safer/dispatch-moltzap` published to npm (or workspace-consumed by sbd) with the API surface and invariants of §1.B.
- [ ] `/safer:orchestrate` doctrine reflects the §6 strategy-boundary changes; env-flag read exists at a single skill-entry point.
- [ ] All four repos have their env flag wired (§3.1) with `tmux` as the v1 default.
- [ ] Phase 1 exits on §2.1 + §5.1 + §5.2 gates all green.
- [ ] Phase 2 exits on §2.2 Stryker gate green.
- [ ] Phase 3 exits on §2.3 UX-unchanged signal from ≥ 1 author over ≥ 1 week.
- [ ] Phase 4 exits on §2.4 full spec → ship cycle green on a live PR in zapbot.
- [ ] Phase 5 (30 days) elapses with zero §2.6 backout events across all four repos.
- [ ] No §2.6 rollback contract is ever silently bypassed; every rollback has a `safer:investigate` sub-issue.

---

## 12. References

- sbd#82 research report (HIGH 0.91): https://github.com/chughtapan/safer-by-default/issues/82#issuecomment-4274927604
- sbd#89 spec issue (this document's parent).
- sbd#72 spike (forbade moltzap protocol changes).
- moltzap monorepo: `/home/tapanc/moltzap`; channel precedents at `packages/nanoclaw-channel/`, `packages/openclaw-channel/`.
- moltzap `@moltzap/app-sdk` primitive: `packages/app-sdk/src/app.ts:60..90` (research I1).
- safer-by-default orchestrate skill: `skills/orchestrate/SKILL.md` (lines 95, 263, 402, 442–478, 515–525 carry tmux assumptions — see §6).

---

## Status marker

`DONE_WITH_CONCERNS` — 5 open questions (§10) with recommended defaults; assumptions (§9) flagged for user confirmation; architect stage owns per-package signature decisions.
