# Phase 5e — permission_request response protocol

When Step 1a surfaces a `permission_stall:` anomaly in the sweep summary, the team-lead MUST respond within the same tick. Sitting on a permission_request past one sweep tick is a Forbidden-list violation.

**Decision sequence (always in this order):**

1. **Read the pane capture** (the last ~40 lines printed under the `permission_stall:` line). Extract the actual tool name and the actual command. The truncated inbox JSON is unreliable; the pane capture is authoritative.
2. **Classify the request.** Three checks, in order:
   - **Scope.** Is the request inside the teammate's named sub-issue scope? Cross-scope requests get denied. The teammate is escalating sideways instead of upstream (Principle 8 violation).
   - **Destructive-action rules.** Per existing rules in PRINCIPLES.md, the team-lead does NOT approve `rm -rf` outside the working directory, `git push --force` to protected branches, `DROP TABLE`, or any irreversible operation without explicit user authorization.
   - **Session-level authorization.** If the user has pre-authorized the operation class for this session (e.g., "approve all rebases on this branch"), apply it; otherwise default-deny destructive operations.
3. **Respond via one of three mechanisms:**
   - **Approve via SendMessage.** Send the teammate a message naming the approval and any conditions: `{"to": "<teammate>", "summary": "permission approved", "message": "Approved: <tool> <command>. Proceed."}`. The teammate reads its inbox and the dialog clears on acceptance.
   - **Deny via Escape + SendMessage.** Dismiss the modal first, then explain the denial:
     ```bash
     SWARM_SOCKET=$(ls /tmp/tmux-$(id -u)/claude-swarm-* | head -1)
     tmux -S "$SWARM_SOCKET" send-keys -t <paneId> Escape
     ```
     Follow with `SendMessage({to: "<teammate>", message: "Denied: <reason>. Escalate to <upstream-modality> if blocked."})`.
   - **Take the action from team-lead context, then notify.** When the action is safer from team-lead context (lockfile cleanup, branch hygiene, anything that requires repo-level authority the teammate does not need), perform the action in the team-lead pane, dismiss the teammate's dialog with `tmux send-keys Escape`, then SendMessage the teammate that the action is done and to proceed.

**Discovery.** The claude-swarm tmux socket is at `/tmp/tmux-<uid>/claude-swarm-<pid>`, NOT `default`. Confirm with `ls /tmp/tmux-$(id -u)/claude-swarm-*`. Hardcoding `default` silently scans the wrong panes. Capture-pane returns blank, the regex never matches, and stuck dialogs go unnoticed.

**Audit.** Every Phase 5e response logs a one-line entry to the parent epic comment: `permission_decision: teammate=<name> tool=<tool> verdict=<approve|deny|sideaction> reason="<short>"`. The audit line is not optional. The next operator reading the epic must be able to reconstruct why each request was answered the way it was.

