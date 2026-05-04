# Invitation — dialog only

**When.** The user has a vague idea or open question. They want to think through the problem with the orchestrator before any code or design lands.

**User instruction looks like:**

- "look into the latency on the dashboard route"
- "what would it take to support multi-region writes?"
- "is this tractable?"
- "check this out"

**Granted scope.** A single `/safer:investigate` (or `/safer:spec` / `/safer:research` / `/safer:spike`) dispatch. Nothing downstream. After the artifact publishes, the orchestrator asks the user what to authorize next.

## Contract

**Goal.** Understand the source of latency on the dashboard route.

**Acceptance.**
- [ ] `/safer:investigate` writeup published with two-layer root cause (Immediate + Underlying).
- [ ] Recommendation routed to the user for next-step decision.

**Autonomy budget.**
- Dispatch `/safer:investigate`.
- Read code, run reproductions, examine logs.
- Run `git log`, `git blame`, `git bisect` for regression diagnosis.

**Always-park.**
- Ratchet-up (any modality escalating upstream).
- Any modality dispatch beyond `/safer:investigate`.
- Any code edit on tracked files.
- Opening any PR.
- Force-push, branch deletion, infra/CI/deploy edits.
- Schema migrations, prod deploys, secret operations.
- Posting outside the repo (Slack, email, external API).

Doctrine: `<SHA>`
Drafted: `<ts>`
OK'd: `<ts>` by `<user@github>`

## What happens after publish

After the investigate writeup lands, orchestrator posts a follow-up question: "Investigation done. What autonomy do you want to grant for the fix?" Options typically include:

- `AMEND CONTRACT: extend to vp-engg through-merge` — autonomous fix end-to-end (see [`bug-fix-end-to-end.md`](./bug-fix-end-to-end.md)).
- `AMEND CONTRACT: extend to architect → stop` — see the design before implementation (see [`architect-and-stop.md`](./architect-and-stop.md)).
- `STOP CONTRACT: handing off to a human` — close the epic; investigation is the deliverable.

The orchestrator never auto-advances from invitation; the user explicitly grants the next phase.
