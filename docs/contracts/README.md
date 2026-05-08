# Contract examples

Worked contract templates for common dispatch shapes. Each example is a real `## Contract` section as it would appear on a parent epic body — copy, adapt, post.

The four-section format is doctrine (`PRINCIPLES.md → Contracts`). These examples show what the sections look like in practice for the dispatch patterns that come up most.

| File | Shape | When to use |
|---|---|---|
| [`invitation.md`](./invitation.md) | dialog only | Vague intent; you want to think it through before any execution. |
| [`bug-fix-end-to-end.md`](./bug-fix-end-to-end.md) | diagnose → impl → review → verify → merge | A reproducible bug; you want the chain to ship the fix while you sleep. |
| [`scrum-master-backlog.md`](./scrum-master-backlog.md) | per-sub-issue execution against an existing epic | A decomposed epic exists; the orchestrator works the backlog without adding scope. |
| [`architect-and-stop.md`](./architect-and-stop.md) | spec → architect; stop before implement | Spec is settled; you want to read the architect plan before authorizing implementation. |

Two patterns recur across all examples:

- **`Always-park` always includes ratchet-up.** When a downstream modality discovers it needs to escalate (diagnose→spec, architect→spec, implement-*→architect), the original contract's assumption was wrong. Always parks for amendment.
- **`Always-park` always includes the irreversible-action defaults.** Force-push, branch deletion, schema migrations, prod deploys, secret operations, external posts. Even when the budget authorizes "merge", these specific actions still park.

When in doubt, copy [`bug-fix-end-to-end.md`](./bug-fix-end-to-end.md) and trim. It's the most common shape.
