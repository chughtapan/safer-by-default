# moltzap-channel v1 — spec

**Status:** planning (spec). **Supersedes:** sbd#89 (closed). **Tracking issue:** sbd#103.
**Research grounds:** sbd#92 final report (HIGH 0.91, Round 4 EXCELLENT).

## 1. Intent

Wire moltzap into a running Claude Code session, using the first-party Channels primitive as the agreed scope constraint (per user direction on sbd#103; sbd#92 research validates feasibility). The previous spec (sbd#89) predated that constraint. This spec names **what v1 must deliver** — two deployment shapes, a cutover sequence, and three routed open questions. It does **not** pick packages, capabilities, flags, interfaces, or a LoC budget; those are architect-stage decisions.

## 2. Goals

1. **G1 — Interactive shape.** A user with a running `claude` session can receive a moltzap message inbound and send a moltzap reply outbound, under claude.ai authentication, via a channel-backed integration.
2. **G2 — One-shot shape.** A moltzap-driven invocation (e.g., an ephemeral runner or CI job) can trigger a single Claude turn in response to one moltzap event and return a reply on the originating conversation.
3. **G3 — Per-repo cutover.** Adopt in the order sbd → ccj → acg → zapbot, one repo at a time, each behind a per-repo rollout gate whose mechanism architect chooses, with the prior (tmux-based) dispatch path usable as a rollback until the repo's own soak criterion is met.
4. **G4 — Retire sbd#89.** Close the prior spec as superseded; the closure comment cites this spec.
5. **G5 — Honor the Channels contract as a dependency.** v1 depends only on properties documented in the Claude Code Channels reference (https://code.claude.com/docs/en/channels, https://code.claude.com/docs/en/channels-reference). Any v1 requirement that needs more than documented behavior is deferred to a later version.
6. **G6 — Route three open questions.** Q1 → `/safer:spike`; Q2 → `/safer:architect`; Q3 → `/safer:research`. No open question is silently closed inside this spec.

## 3. Non-goals

1. **Not rebuilding the Channels primitive.** v1 uses documented behavior; it does not extend the protocol, invent capabilities, or depend on undocumented Claude Code internals.
2. **Not production headless with API-key / long-lived server-side agent.** That path is not served by either shape in this spec and is routed to research (Q3).
3. **Not cross-moltzap-conversation context isolation in v1.** The interactive shape allows multiple moltzap conversations to share one Claude session's context. Per-conversation isolation is deferred pending Q1.
4. **Not multi-persona / per-conversation skill scoping.** One agent → one persona in v1.
5. **Not custom persistence, dedupe, or buffering in v1.** v1 does not introduce new durability or replay layers beyond what moltzap and Claude Code already provide. Any durability gap is either accepted or documented; it is not closed inside v1.
6. **Not bypassing the research-preview allowlist for public GA distribution.** Distribution review is a separate step downstream of v1.
7. **Not reviving sbd#89's prior plan** (see Appendix A).
8. **Not architect-stage decisions.** This spec does not choose modules, package names, transport capabilities, on-disk layouts, LoC budgets, specific flags, or interfaces. Those belong to architect.
9. **Not changing moltzap's own wire protocol.** v1 adapts to the `@moltzap/app-sdk` surface as it stands.

## 4. Invariants

Properties v1 must hold for as long as v1 is in effect. Each has a corresponding acceptance check in §5.

1. **I1 — Sender-authenticated inbound (`/en/channels-reference#gate-inbound-messages`).** Every moltzap event that enters the Claude session is gated on the moltzap *sender* identity (not on conversation or room identity). An ungated path is a prompt-injection vector.
2. **I2 — Ordered within a conversation.** Messages in a single moltzap conversation reach the Claude session in the order they arrived at the moltzap server, for the duration the Claude session is running.
3. **I3 — Presence-gated delivery (`/en/channels#push-events`).** Events only arrive while the Claude session is open. v1 asserts no delivery guarantee across Claude-session restarts; behavior on restart is whatever moltzap's own replay provides, with no additional v1 guarantee layered on top.
4. **I4 — Auth boundary.** The interactive shape (G1) functions only under claude.ai authentication. The one-shot shape (G2) functions under whichever credentials Claude Code itself accepts for one-shot invocation, per Claude Code's own rules.
5. **I5 — Per-repo rollout gating.** No repo routes moltzap traffic through this path until that repo's rollout gate is engaged; disengaging the gate restores the prior dispatch path without any moltzap-server change. The gate mechanism is architect's choice; its existence and reversibility are v1 invariants.
6. **I6 — Channels contract not extended.** v1 relies only on documented Channels behavior. Undocumented or reverse-engineered behavior is not load-bearing.
7. **I7 — No new durability layer.** v1 adds no persistence, dedupe, or buffering beyond what moltzap and Claude Code already provide (Non-goal 5).

## 5. Acceptance criteria

Independently checkable. Each acceptance item is tied to a goal or invariant.

### 5.1 Interactive shape (G1, I1–I4, I6)

- [ ] **AC1.1** A user with a running `claude` session under claude.ai authentication and moltzap credentials can receive at least one inbound moltzap event as a `<channel>`-tagged turn in the session, and send at least one outbound reply that arrives on the moltzap conversation.
- [ ] **AC1.2** A message from a moltzap sender *not* on the configured allowlist produces no turn in the Claude session and no side effect on the Claude session's transcript (I1).
- [ ] **AC1.3** While the Claude session is *not* running, no moltzap event produces a turn in that session. v1 makes no claim about redelivery on restart (I3).
- [ ] **AC1.4** Two messages sent in order within a single moltzap conversation arrive in that same order in the Claude session (I2).

### 5.2 One-shot shape (G2, I1, I4)

- [ ] **AC2.1** A single moltzap-driven invocation produces exactly one reply on the originating moltzap conversation and exits.
- [ ] **AC2.2** A non-allowlisted moltzap sender produces no invocation / no reply (I1).
- [ ] **AC2.3** The documented behavior when the invocation's filesystem is ephemeral (e.g., CI runner) is explicitly stated in the architect-stage design (architect may choose any behavior, including "no cross-invocation continuity"). v1 does not require cross-invocation session continuity.

### 5.3 Cutover and rollout gating (G3, I5)

- [ ] **AC3.1** For each of the four repos (sbd, ccj, acg, zapbot), a rollout gate exists that starts disengaged. With the gate disengaged, the repo's existing moltzap-triggered path (tmux-based) dispatch-path integration exercise passes unchanged. The "existing integration exercise" is whatever exercise the repo already uses to validate that path today; if the repo has none, that gap is named as a precondition before cutover.
- [ ] **AC3.2** The rollout order is documented as sbd → ccj → acg → zapbot, and each repo's step defines a written, pre-declared soak criterion (e.g., "N days of clean operation with no rollback"). The criterion is named before cutover begins for that repo.
- [ ] **AC3.3** Disengaging the rollout gate for any repo restores the prior dispatch path end-to-end, verified by the same repo-local integration exercise used in AC3.1, and does not require a moltzap-server change.

### 5.4 Dependency-contract checks (I6, I7)

- [ ] **AC4.1** v1 does not add any new runtime durability, dedupe, or buffering layer beyond what moltzap and Claude Code already provide (I7).
- [ ] **AC4.2** The architect-stage design, when published, cites for each Channels capability it consumes the specific `/en/channels` or `/en/channels-reference` section that documents it. A capability without a documented citation fails this check (I6).

### 5.5 Housekeeping (G4, G6)

- [ ] **AC5.1** sbd#89 is closed with a comment linking to this spec and naming it as the supersession.
- [ ] **AC5.2** Q1, Q2, Q3 are filed and routed per G6 before architect work begins on the interactive shape.
- [ ] **AC5.3** No architect-stage design for the interactive shape is approved before Q2 has a resolution, because Q2 blocks the plugin's lifecycle contract.

## 6. Assumptions

User to confirm before architect work begins.

1. **A1 — moltzap exposes the needed app-SDK shape.** `@moltzap/app-sdk` supports receiving inbound events for an app and sending outbound replies to a conversation; the exact method names are architect's to pick.
2. **A2 — moltzap server replay is whatever moltzap already does.** v1 inherits moltzap's own redelivery semantics on WebSocket reconnect; v1 makes no stronger assumption and adds no compensating layer (see Non-goal 5).
3. **A3 — Four-repo scope is fixed.** sbd, ccj, acg, zapbot. No new repo is in scope for v1.
4. **A4 — zapbot's GHA rollout uses the one-shot shape only.** The interactive shape is not expected on an ephemeral runner.
5. **A5 — Dogfooding is on claude.ai-authenticated developer workstations.** No v1 codepath depends on API-key auth under the interactive shape.
6. **A6 — Research-preview status is tolerable for v1.** v1 ships internally during the preview window; public-allowlist submission is downstream.
7. **A7 — Channels docs are the contract of record.** If `/en/channels` or `/en/channels-reference` changes in a way that conflicts with I1–I7, this spec is amended before continuing.

## 7. Open questions

Each has a recommended default *for the routed modality's starting point only* — the default is not adopted here.

### Q1 — Concurrent-conversation context demux limit → `/safer:spike`

**Q:** Under the interactive shape, the Claude session's context is shared across all moltzap conversations routed through it. At what concurrent-conversation count does shared-context exhaustion become the dominant failure mode for a representative dogfood workload?

**Options:**
- (a) Measure empirically against a representative trace; name a soft cap; gate interactive-shape rollout on staying under it.
- (b) Accept unbounded; document observed failure only.
- (c) Require per-conversation process isolation now (rejected — scope creep; see Appendix A).

**Recommended default for the spike:** (a). Produce a single number as a soft guardrail, not a hard limit.

**Why spike:** Bounded empirical feasibility, not a multi-round research loop. Deliverable: one measurement + a named soft cap.

### Q2 — Inbound-listener readiness timing → `/safer:architect`

**Q:** If `@moltzap/app-sdk` requires a prior session-ready handshake before the inbound-listener registration is valid (per sbd#92 Round-3 supervisor Q1, unresolved in R4), what is the plugin's startup contract? This determines whether events can be lost between transport connect and listener registration.

**Options:**
- (a) Register the inbound listener only after the app-SDK's ready event; accept that any pre-ready events are dropped.
- (b) Register eagerly; rely on app-SDK internals not to deliver pre-ready events.
- (c) Buffer in the integration and flush on ready.

**Recommended default for architect:** (a), unless architect inspection of `@moltzap/app-sdk` shows (b) is already safe.

**Why architect:** Module-contract / lifecycle question between two subsystems in the same process. Not a new feasibility unknown.

### Q3 — Production-headless long-lived agent path → `/safer:research`

**Q:** A long-lived, server-side, API-key-authenticated moltzap agent (no developer workstation, not a per-event ephemeral runner) is served by neither shape in v1. What is the correct shape?

**Options:**
- (a) Wait for the external constraint to change (Channels GA, or API-key support for Channels); defer until a concrete internal need is named.
- (b) Build a non-Channels long-lived server-side dispatcher (re-examine only if (a) is no longer viable).
- (c) Declare out of scope indefinitely.

**Recommended default for research:** (a) with a written re-examination trigger (specific constraint change or named internal user), not a calendar date.

**Why research:** Hypothesis-driven exploration of an open question whose answer depends on external conditions.

---

## Appendix A — Rejected alternatives (informational)

These were considered and rejected; future agents should not re-propose them without new evidence.

- **sbd#89's prior plan** (two packages + multi-subcommand CLI). Rejected: user pivoted the scope constraint to Channels on sbd#103; the prior framing is obsolete against the new constraint.
- **One big-bang migration across all four repos.** Rejected by G3 (staged cutover).
- **Per-conversation Claude-process isolation in v1.** Rejected as scope creep; deferred pending Q1.
- **Extending the Channels protocol contract.** Rejected by I6.
- **Adding a v1 durability / dedupe / buffering layer.** Rejected by Non-goal 5 and I7.

## Appendix B — Relationship to prior artifacts (informational)

- **sbd#82** — prior research; cold-start latency + LoC-envelope measurements.
- **sbd#89** — prior spec (closed); predated Channels.
- **sbd#92** — research round that pivoted to Channels (HIGH 0.91). This spec translates its conclusions into contract form.
- **Claude Code Channels docs** — `/en/channels`, `/en/channels-reference`. Any change that conflicts with I1–I7 forces a spec amendment.
