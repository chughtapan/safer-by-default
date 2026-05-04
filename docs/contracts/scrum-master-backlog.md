# Scrum-master backlog

**When.** A parent epic already exists with a decomposition table of sub-issues. You want the orchestrator to drive each sub-issue to its planned exit state, without adding new work.

**User instruction looks like:**

- "process the open sub-issues on epic #198"
- "work through the backlog"
- "churn through these"

**Granted scope.** Per-sub-issue planned exits. The orchestrator dispatches the modality each sub-issue specifies, runs the verify gate where the plan calls for it, and updates the parent's `## Progress` section. No new sub-issues, no decomposition-table edits.

## Contract

**Goal.** Drive each open sub-issue on epic <https://github.com/OWNER/REPO/issues/198> to its planned exit state per the decomposition table.

**Sub-issues in scope (8):**
- #200, #201, #205, #207, #208, #211, #214, #218.
- Anything not currently in the decomposition table is out of scope.

**Acceptance.**
- [ ] Each in-scope sub-issue closed at its planned state (per the table's "Acceptance" column).
- [ ] Parent epic's `## Progress` section reflects all closures.

**Autonomy budget.**
- Dispatch the modality each sub-issue's label specifies.
- Run the verify gate when the sub-issue's plan calls for it.
- Update the parent epic's `## Progress` section after each close.
- Merge implement-* PRs after their planned review chain passes.

**Always-park.**
- Adding a new sub-issue (even a follow-up surfaced by investigate or impl).
- Editing the decomposition table (adding rows, changing dependency order, changing acceptance criteria).
- Ratchet-up from any sub-issue.
- Three-strikes on any sub-issue.
- Force-push, branch deletion, infra/CI/deploy edits.
- Schema migrations, prod deploys, secret operations.
- Posting outside the repo.

Doctrine: `<SHA>`
Drafted: `<ts>`
OK'd: `<ts>` by `<user@github>`

## What this contract is for

Scrum-master is the tightest of the common shapes. The decomposition table is the contract; the orchestrator's job is to execute it faithfully. Anything that would expand the backlog parks for explicit user authorization — the user retains exclusive say over what counts as "in this epic."

Compare with [`bug-fix-end-to-end.md`](./bug-fix-end-to-end.md), where the budget is shape-defined ("any modality in this chain"); here the budget is enumeration-defined ("these 8 specific sub-issues, period").
