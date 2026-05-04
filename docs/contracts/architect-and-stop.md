# Architect and stop

**When.** The spec is settled (either user-authored or already published). You want to see the architect plan before authorizing implementation.

**User instruction looks like:**

- "architect this spec"
- "lay out the modules; I'll decide on impl after"
- "design the shape; stop before any code"

**Granted scope.** A single `/safer:architect` dispatch against an existing spec. The architect publishes its design doc + interface stubs. The chain stops there; orchestrator asks the user what to authorize for implementation.

## Contract

**Goal.** Produce an architect design doc + interface stubs that satisfy the spec at <https://github.com/OWNER/REPO/issues/198#issuecomment-XXX>.

**Acceptance.**
- [ ] Architect design doc published as a comment on this epic, with all 8 sections filled.
- [ ] Stub branch + draft PR opened with `[arch]` title prefix.
- [ ] User-facing summary posted on this epic with "ready for review."

**Autonomy budget.**
- Dispatch `/safer:architect`.
- Open one draft PR for the architect's stub branch (no merge).
- Run `/codex` on the published design doc (architect-internal review-after gate).

**Always-park.**
- Ratchet-up to spec (architect found a spec gap): the spec is the user's contract; revising it requires their authorization.
- Any implement-* dispatch.
- Merging the architect's stub PR.
- Force-push, branch deletion, infra/CI/deploy edits.
- Schema migrations, prod deploys, secret operations.
- Posting outside the repo.

Doctrine: `<SHA>`
Drafted: `<ts>`
OK'd: `<ts>` by `<user@github>`

## What happens after the architect publishes

Orchestrator posts: "Architect plan published at `<URL>`. What autonomy do you want to grant for implementation?" Common follow-ups:

- `AMEND CONTRACT: extend to implement-senior + review-senior + verify + merge` — autonomous build against the plan.
- `AMEND CONTRACT: extend to implement-senior + stop after PR opened` — see the diff before merging.
- `AMEND CONTRACT: ratchet back to spec; the plan revealed a gap` — re-open the spec dialog.
- `STOP CONTRACT: I'll dispatch impl in a separate epic` — close this epic; the architect plan is the deliverable.

This shape is the natural midpoint between [`invitation.md`](./invitation.md) (dialog only, no execution) and [`bug-fix-end-to-end.md`](./bug-fix-end-to-end.md) (full autonomy through merge). Pick it when the design choices are load-bearing enough that you want to read them before the implementation depends on them.
