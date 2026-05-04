# Bug fix end-to-end

**When.** A reproducible bug is filed. You want the orchestrator to investigate, fix, verify, and merge — without pinging you on routine progress. Most common dispatch shape.

**User instruction looks like:**

- "fix the day_vote bug end-to-end"
- "fix this regression overnight"
- "investigate and ship the fix"

**Granted scope.** Investigate → implement-junior → review-senior → verify → merge. The chain runs autonomously; the orchestrator pings only on `Always-park` hits or ratchet-up.

## Contract

**Goal.** Fix the day_vote phase regression so DAY_VOTE exits on quorum reached, in the running game and in tests.

**Acceptance.**
- [ ] Reproducible failure case is fixed (regression test added).
- [ ] Existing tests stay green.
- [ ] PR merged to `main`, dogfood reachable.

**Autonomy budget.**
- Dispatch `/safer:investigate`, `/safer:implement-junior`, `/safer:review-senior`, `/safer:verify` in that order.
- Open draft PRs.
- Run lint, typecheck, tests; iterate until green.
- Merge after peer review green AND CI green AND verify SHIP.

**Always-park.**
- Ratchet-up (investigate→spec, investigate→architect, implement-junior→architect): the original assumption was a routine fix; ratchet means it isn't.
- Force-push, branch deletion, infra/CI/deploy edits.
- Adding new sub-issues for follow-up bugs surfaced during investigation.
- LOW-confidence root cause.
- Three-strikes mis-scoping.
- Schema migrations, prod deploys, secret operations.
- Posting outside the repo.

Doctrine: `<SHA>`
Drafted: `<ts>`
OK'd: `<ts>` by `<user@github>`

## Common variants

- **Strict-merge gate.** Add `Always-park: Merging the final PR (require explicit OK before merge)`. The chain runs autonomously through verify, then parks. Use when you want to read the diff yourself before it lands.
- **Restore-don't-rebuild.** When the bug is a regression in code that was working, the investigate writeup will recommend "restore pre-refactor behavior" routed to `implement-junior`. The contract above already handles this — `implement-junior` is in the budget. No changes needed; the recommendation flows through.
- **Sleep mode.** When dispatched late in the day with "by morning" framing, the orchestrator runs in digest-notification mode (one wake-up summary at end of session) instead of milestone notifications. No contract change; just an `Autonomy budget` line: `Notification mode: digest-on-completion`.
