# Linear project assignment v1 — backfill rules + going-forward convention

**Modality:** spec (`/safer:spec`)
**Source issue:** <https://github.com/chughtapan/safer-by-default/issues/97>
**Parent of:** sbd#95 (Linear team `MOL` setup; 7 projects exist but empty)
**Spike basis:** sbd#88 verdict — Strategy C (GH-primary, Linear native-sync lens). All routing decisions below assume `gh issue` calls remain the agent surface and Linear is a human-tracking lens.

---

## Intent

Linear setup script (sbd#95) created the team and 7 projects but did not populate them. Linear's native GitHub integration syncs title/description/status/labels/assignee/comments, but does **not** auto-assign GH issues to Linear projects. The user opens Linear and sees an empty roadmap. This spec picks the rule that fills the projects without asking teammates to learn a new convention.

## Goals

1. A backfill rule that, applied once, assigns every existing open GH issue across linked repos to the correct Linear project (or to a single named "unassigned" bucket).
2. A going-forward convention that costs zero per-dispatch work for teammates whose sub-issues already inherit from a parent epic.
3. An assignment mechanism that runs without requiring a hosted webhook endpoint.
4. A project inventory that matches actual in-flight epics, with one named catchall so no issue drops on the floor.
5. A cross-repo project model that fits the free-tier 1-team constraint today and has a documented split path for paid-tier later.

## Non-goals

1. Bidirectional sync of Linear project assignment back to GH (Linear is the authority on project membership; GH never reads it).
2. Sync of Linear-specific metadata (cycles, priority, RICE) into GH.
3. Ergonomic improvements for teammates working with Linear directly. Per sbd#88, agents stay on `gh`; Linear is the human's lens.
4. A Linear CLI for teammate use. The community CLI (`@schpet/linear-cli`) is a backstop for the human, not a teammate dependency.
5. Migration of historical (closed) issues. Backfill is open-only; closed issues remain unassigned.

## Invariants

1. **Every open GH issue across linked repos resolves to exactly one Linear project after a backfill pass.** If no rule matches, the issue lands in the catchall project (`SBD ops`); never `null`.
2. **The orchestrate sub-issue body template is unchanged.** The going-forward convention exploits the existing `Parent: #N` line. Any change to the seven dispatch templates is a doctrinal edit and is out of scope here.
3. **Assignment is idempotent.** Running the backfill twice produces the same Linear state; a second pass never moves an already-assigned issue.
4. **Backfill never overwrites a manually-set Linear project.** If a human moved an issue in Linear, the script reads that as authoritative and skips reassignment.
5. **The pipeline degrades safely.** If the backfill subcommand errors, no GH state changes; the worst case is a stale Linear view, not data loss.

## Acceptance criteria

- [ ] **Q1 (mapping rule)** answered with a named primary signal, ranked fallbacks, and an evaluated failure rate / collision profile.
- [ ] **Q2 (convention)** answered with a single chosen convention plus the exact diff against the orchestrate skill (or a justified zero-diff statement).
- [ ] **Q3 (mechanism)** answered with one of {script-at-filing, periodic-backfill, webhook} and a stated reason the others are rejected.
- [ ] **Q4 (inventory)** answered with the reconciled project list (live count vs `#97` body), gaps named, and the catchall project identified.
- [ ] **Q5 (cross-repo)** answered with the free-tier model and the paid-tier split plan.
- [ ] Two implement-junior follow-up issue bodies are pre-written so the team-lead can file them post-merge without further design.
- [ ] Skill-edit spec text for the chosen convention is included as exact diff markdown (or a zero-diff justification with the named single edit point that does change — the parent-epic creator).

## Assumptions (user must confirm)

1. The 7 projects shipped by sbd#95 (`MOL` team) are the intended portfolio. Any divergence from the `#97` body's 6-project list is a bookkeeping fix, not a design call. *(Source: sbd#95 close comment names "7 projects mirroring in-flight epics.")*
2. The user accepts that Linear `MOL` is a misnomer for an SBD-driven team — the abbreviation reflects the Moltzap epic that drove the test, not the eventual team boundary. Renaming is a deferred chore, not a blocker.
3. Free tier (250 issues, 1 team) is the operating constraint until a paid tier is explicitly authorized. The paid-tier split path is designed for, not committed to.
4. The orchestrate auto-monitor cron (`*/2 * * * *`) is the right home for periodic backfill. If the user disables the cron, backfill becomes manual.
5. The catchall project name `SBD ops` is acceptable. If the user prefers `Triage`, `Inbox`, or another name, swap and re-run; no other downstream change.

---

## Q1 — Backfill mapping rule (existing issues)

### Decision

**Primary signal:** `Parent: #N` body line → resolve `#N` to its Linear project.

**Ranked fallbacks (apply in order; first match wins):**

1. **Parent ref** — body line `Parent: #N`; `#N` itself has a Linear project (set via Q2 convention or manual assignment).
2. **Parent inference via `## Parent` heading** — same as (1), but for issues using the long-form heading style observed in some older bodies (`## Parent\n#N`).
3. **Label keyword** — issue carries one of the modality-specific labels that map 1:1 to a project (e.g., `safer:spike` on the Linear-tracking-infra project; `community-feedback` → Community-feedback project). Mapping table maintained in the backfill script.
4. **Catchall** — issue lands in the `SBD ops` project. The backfill script logs each issue routed to catchall so the human can re-route in Linear if desired.

### Failure rate (estimated)

- ~85% of currently open issues have `Parent: #N` (orchestrate-created sub-issues universally do; standalone issues filed directly by the user do not).
- ~10% match a fallback label keyword.
- ~5% land in catchall — these are typically older issues from before the orchestrate convention or one-off user filings.

### Collision

`Parent: #N` is single-valued per issue, so the primary rule is collision-free by construction. If a sub-issue's parent itself is unassigned (the parent never got a project), the parent's parent is consulted (one hop only). If the parent is also unassigned after one hop, fall through to label-keyword.

Label-keyword can collide (e.g., an issue with both `safer:spike` and `community-feedback`); the mapping table is **ordered**, so the first-listed label wins. The script logs every collision with the chosen label so the human can adjust the table.

### Manual override

A `Linear-project: <name>` body line, if present, supersedes all rules. The backfill script reads it via grep, validates the name against the live project list (Linear GraphQL `projects` query), and assigns. Invalid names are logged and skipped (issue stays in its current project; never silently catchalled).

### Rejected alternatives

- **Epic-letter mention in title (`Epic B` → cc-judge project).** Only Epic B and Epic C use this convention; the other 5 projects (Moltzap, Community feedback, Reentrance Tier-1, Testing doctrine, +1 catchall) have no letter. Doesn't generalize. Title-mention is also less reliable than body-structured fields.
- **Label-prefix convention (`project:<name>` on every GH issue).** Adds a per-issue label that orchestrate would have to add at filing time — that's the doctrinal seven-template edit `#97` flags as the boundary cross. Avoid.
- **Manual curation only.** Defeats the purpose: the user opened Linear and saw it empty; the cost of asking the user to drag 100+ issues into projects is precisely what we are eliminating.
- **Parent-epic title regex (e.g., issue body contains "Moltzap").** Brittle; requires a maintained synonym table; collides on cross-cutting work that mentions multiple epic names.

---

## Q2 — Going-forward convention (new issues)

### Decision

**Default-to-parent.** New sub-issues inherit their Linear project from their parent epic via the existing `Parent: #N` body line. **No orchestrate skill edit required for sub-issues.**

The single edit is to the parent-epic creation step (`safer-publish --kind epic`), which has no parent and must declare its own project. Add one optional body line:

```markdown
Linear-project: <project-name>   # e.g., "Moltzap migration"
```

The backfill subcommand reads this line on epics; sub-issues inherit transitively.

### Skill-edit spec text (exact diff for orchestrate Phase 3)

The orchestrate skill's Phase 3 epic body template (`skills/orchestrate/SKILL.md`, around the `Epic body template:` markdown block) gains exactly one new line in the Context section:

```diff
 ## Context

 - **Project:** <name> (<https://github.com/OWNER/REPO>)
+- **Linear project:** <name>   <!-- one of the projects in the MOL team; required if Linear sync is desired -->
 - **Motivation:** <one sentence, in the user's own words if they stated it — why this matters now>
 - **Prior artifacts:** <bullet list of full URLs to every spec, issue, comment, PR, or doc this epic depends on. If none, write "none.">
```

The sub-issue creation block (Phase 4, the `gh issue create` body heredoc) is **unchanged**. Sub-issues already carry `Parent: #$PARENT_NUMBER`, which the backfill walks.

The Phase 3 body-rules list grows by one rule:

```diff
 4. **The `## Next step` section is mandatory.** ...
+5. **The `Linear project` line is mandatory if Linear sync is enabled for this repo.** Pick the project from the live Linear `MOL` team list. If the epic is genuinely cross-project, name the dominant project and add a comment cross-link rather than splitting the epic.
```

That is the entire skill-edit footprint. No change to the seven Step-6d dispatch templates. No change to any teammate prompt. No new label.

### Rejected alternatives

- **Body line on every issue (`Project: <name>`).** Redundant for sub-issues whose parent already declares it. Also forces the seven-template edit that `#97` flags.
- **GitHub label (`project:<name>`).** Adds an extra `--label` flag to every `gh issue create` call across all seven templates. Same boundary cross. Worse, GH labels need to be created once per repo per project name — yet another setup chore.
- **Nothing (rely on backfill catching it).** Defeats Invariant 1; new epics filed mid-cycle would land in catchall until the next backfill pass and the user would see them in the wrong place transiently.

### Edge case: standalone (non-orchestrate) issues

User-filed issues that have no parent and no `Linear-project:` line fall to label-keyword fallback (Q1 rule 3) at backfill time. If neither matches, they land in catchall. This is an acceptable failure mode for the rare standalone case; the user can drag them in Linear.

---

## Q3 — Assignment mechanism

### Decision

**Periodic backfill, invoked by the existing orchestrate auto-monitor cron (`*/2 * * * *`).** The cron's loop body gains one cheap call per tick:

```bash
safer-linear-setup assign-projects --since 5m --quiet
```

Idempotency (Invariant 3) plus the `--since` window keeps the cost negligible — only issues touched (created/updated) in the last 5 minutes are scanned.

A user-invocable full-backfill mode is also exposed:

```bash
safer-linear-setup assign-projects --all --dry-run   # preview
safer-linear-setup assign-projects --all             # apply
```

### Why periodic over the alternatives

- **Script-at-filing-time** (teammate runs `safer-linear-setup assign-project` after `gh issue create`): adds a step to every dispatch in every modality skill. Multiplies the doctrinal-edit surface by N skills. Forgetting it fails open silently.
- **Periodic backfill** (chosen): one home (the cron loop body), one edit, idempotent. Drift window ≤ 2 min. Acceptable for a human-eyes-only lens.
- **Webhook-driven** (GH issue-opened → Linear GraphQL): lowest latency (~seconds) but requires hosting an endpoint, securing a secret, monitoring uptime. Out of scope per `#88`'s sync-strategy reasoning ("integration cost > 2 weeks → NO-GO"). Revisit only if the 2-min drift becomes a felt pain.

### Rejected alternatives — additional notes

- **Cron at lower frequency (e.g., hourly).** A new epic filed at 9:01 doesn't show up until 10:00. The user is one human watching one screen; an hour-stale roadmap is worse than a 2-min-stale one. Frequency is gated by Linear's complexity-points budget (3M/hr per API key, plenty for our scale).
- **On-demand only (no cron).** User has to remember to run a script; defeats the "Linear stays current" promise.

### Subcommand contract (for the implement-junior follow-up)

- Command: `safer-linear-setup assign-projects [--all|--since DURATION] [--dry-run] [--quiet]`
- Reads: `LINEAR_API_KEY` env var (already required by sbd#95 setup).
- Algorithm: list candidate GH issues → for each, resolve project per Q1 ranked rules → look up Linear issue (by `MOL-NN` reference or GH `issueId`) → if its `projectId` differs, mutate via `issueUpdate(input: { projectId })`; else skip. Log `assigned`, `skipped`, `catchall`, `error` counts.
- Idempotency: every mutation is preceded by a `query issue { project { id } }` check.
- Failure mode: per-issue errors are logged and skipped; the run does not abort. Exit code 0 if ≥1 issue was processed without fatal error.

---

## Q4 — Project inventory review

### Reconciliation

Issue `#97` body lists 6 projects: Epic B cc-judge, Epic C zapbot simplify, Moltzap migration, Community feedback agents, Reentrance Tier-1, Testing doctrine.

sbd#95 close comment ships **7** projects ("Team `MOL`, 20 labels colored by modality, 7 projects mirroring in-flight epics"). The 7th is unnamed in the issue trail; the spec assumes it is the Linear-integration project itself, created during dogfood. The backfill subcommand should reconcile by querying the live project list, not by hard-coding either count.

### Recommended inventory (final)

1. **Epic B — cc-judge**
2. **Epic C — zapbot simplify**
3. **Moltzap migration**
4. **Community feedback agents**
5. **Reentrance Tier-1**
6. **Testing doctrine**
7. **Tracking infra** *(new or rename of the spike-created 7th)* — covers sbd#88, sbd#95, sbd#97, this spec, and any follow-up Linear-integration work.
8. **Orchestrate hardening** *(new, gap)* — covers sbd#67 (Step 6 work-queue), sbd#93 (routing doctrine), sbd#36 (auto-monitor), sbd#92 (auto-dispatch testing). These are skill-evolution PRs that currently catch on no project.
9. **SBD ops** *(new, catchall)* — covers anything that does not fit the 8 epic projects (e.g., one-off bin/script chores, dependency bumps, infra fixes). Required by Invariant 1.

### Gaps named

- **Linear-integration meta-project.** Covered by `Tracking infra`. Without it, this spec's own follow-up issues have no project home — embarrassing.
- **Orchestrate skill evolution.** Covered by `Orchestrate hardening`. The `safer:orchestrate` skill is a moving target with its own multi-issue arc; treating it as a permanent project (not an epic that closes) acknowledges this.
- **Catchall.** `SBD ops`. Without it, Invariant 1 is unmeetable.

### Collapses

None recommended. All 6 original epics are in flight and distinct enough that merging them would lose human-tracking value. Deletion only after an epic closes (`done` or `abandoned` on the parent issue).

### Cleanup task

The implement-junior follow-up should reconcile project names with the live Linear team and rename / create as needed. Naming churn is cheap on Linear side (project rename does not break GH sync per the spike's audit of native sync semantics).

---

## Q5 — Cross-repo project model

### Decision (free tier, today)

**One Linear team (`MOL`, eventually renamed to `SBD`). One project per epic, regardless of which repos the epic touches.** Each Linear issue carries a `repo:<name>` label (synced from GH's repo source) so per-repo views are still possible via filter.

Cross-repo epics (Moltzap touches sbd + cc-judge + acg + zapbot) live in **one** project (`Moltzap migration`) and contain issues from all four repos. The user gets a single roadmap row for the epic.

### Decision (paid tier, future)

When the 250-issue cap is hit (estimated within ~8 sessions per `#88`), upgrade to Basic ($10/user/mo) **and** split:

- **Per-repo Linear team** (SBD, ACG, CCJ, ZAP). Each team owns its repo's triage workflow, cycles, label palette.
- **Cross-team projects** for cross-repo epics. Linear's paid tier supports projects spanning teams. The "owning repo" (the one driving the migration) hosts the project; other teams' issues cross-link in.
- **Migration plan:** existing `MOL` team becomes `SBD`; ACG/CCJ/ZAP teams get created empty; cross-repo project membership is widened. One-time GraphQL script; ~1 hour wall-clock.

### Why this shape

- Free-tier 1-team constraint forces today's choice; deferring the split avoids paying for a workflow we may not need.
- The "project is the unit of truth, repo is a label" model lets the human reason in epic-terms, which is the original pain (`#88`: "GitHub's issues UI is per-repo... poor at cross-repo rollup").
- The split path is documented, so when the user upgrades to paid tier the migration is mechanical, not exploratory.

### Rejected alternatives

- **Per-repo project (each repo gets its own copy of the Moltzap project).** Loses cross-repo rollup; defeats `#88`. Also creates ambiguous source of truth — if the same epic has one project per repo, which one tracks the cycle?
- **Per-repo team from day one.** Free tier blocks this (1 team only). Even if we paid up immediately, we would split before knowing whether per-repo triage workflows are worth the overhead.
- **No project layer; rely on labels only.** Labels survive sync but have no roadmap / cycle / progress affordance. Loses the "Large win" entries from the `#88` feature audit.

---

## Open questions

1. **Q1 fallback ordering when label-keyword and catchall both apply.** *Recommended default:* label-keyword wins; catchall is the last resort. Spec assumes this; user can override by reordering the mapping table.
2. **Q4 7th-project identity.** Live name from the sbd#95 setup is unknown to this spec. *Recommended default:* the implement-junior follow-up runs `query teams { projects { name } }`, lists what is there, and the spec inventory table is reconciled in the PR description.
3. **Q5 paid-tier trigger.** Exactly which signal flips us from free to Basic? *Recommended default:* the next time `gh issue list --state open --json url` across all linked repos returns >220 issues (90% of the 250 cap).

---

## Skill-edit spec text — consolidated

For the implement-junior who picks up the orchestrate-edit follow-up: the diff is a **two-line addition** to `skills/orchestrate/SKILL.md` at the Phase 3 epic-body template, plus a one-bullet addition to the body-rules list. Both shown verbatim in Q2 above.

**Verbatim summary of files changed:**

- `skills/orchestrate/SKILL.md` — +2 lines in epic body template (the `Linear-project:` line + comment), +1 bullet in the body-rules list.
- No other skill files changed.
- No teammate dispatch template changed.
- No new GH label, no new env var beyond the existing `LINEAR_API_KEY`.

---

## Implement-junior follow-up #1 — `safer-linear-setup assign-projects` subcommand

> Pre-written for team-lead to file post-merge. Title and body ready to paste into `gh issue create`.

**Title:** `[impl-junior] safer-linear-setup: assign-projects subcommand (backfill + cron tick)`

**Body:**

```markdown
Parent: #97
Modality: implement-junior
Depends on: #97 (spec) merged
Acceptance:
- New subcommand `safer-linear-setup assign-projects` accepts `--all`, `--since DURATION`, `--dry-run`, `--quiet` flags per the spec contract in `docs/specs/linear-project-assignment-v1.md` Q3.
- Algorithm matches the Q1 ranked rules (parent-ref → parent-inference → label-keyword → catchall) with manual `Linear-project:` override.
- Idempotent: every mutation preceded by a `query issue { project { id } }` check; second invocation moves zero issues.
- Logs counts: `assigned`, `skipped`, `catchall`, `error`. Exit code 0 if ≥1 issue processed without fatal error.
- Three unit tests:
  - `test_parent_ref_resolution` — sub-issue body with `Parent: #N` resolves to N's project.
  - `test_manual_override_wins` — `Linear-project:` body line beats parent-ref.
  - `test_catchall_fallback` — issue with no parent, no matching label lands in `SBD ops`.
- The orchestrate cron tick gains one new line: `safer-linear-setup assign-projects --since 5m --quiet`. Edit lives in the cron loop body documented in `skills/orchestrate/SKILL.md` Step 5d, NOT in the dispatch templates.
- Confidence target: HIGH — algorithm is fully specified; Linear GraphQL surface used is the same as sbd#95.

## Context
- Spike: <https://github.com/chughtapan/safer-by-default/issues/88>
- Setup: <https://github.com/chughtapan/safer-by-default/issues/95>
- Spec: <https://github.com/chughtapan/safer-by-default/issues/97>
- Spec doc: `docs/specs/linear-project-assignment-v1.md`

## Status
`planning`
```

**Label:** `safer:implement-junior,planning`

---

## Implement-junior follow-up #2 — orchestrate skill edit (epic body template)

> Pre-written for team-lead to file post-merge.

**Title:** `[impl-junior] orchestrate: epic body template — Linear-project line`

**Body:**

```markdown
Parent: #97
Modality: implement-junior
Depends on: #97 (spec) merged
Acceptance:
- `skills/orchestrate/SKILL.md` Phase 3 epic-body template gains exactly the two-line addition shown verbatim in `docs/specs/linear-project-assignment-v1.md` Q2 ("Skill-edit spec text").
- Phase 3 body-rules list gains exactly the one-bullet addition shown in the same section.
- No change to Phase 4 sub-issue creation block.
- No change to any of the seven Step-6d dispatch templates.
- One new test in the orchestrate skill test suite: rendering the epic body template with a stub project name produces the expected line. (Existing tests must continue to pass.)
- Confidence target: HIGH — pure template edit; spec dictates exact diff.

## Context
- Spec: <https://github.com/chughtapan/safer-by-default/issues/97>
- Spec doc: `docs/specs/linear-project-assignment-v1.md`
- Why "junior" not "senior": the diff is mechanical and the spec specifies the exact lines. No design judgment required.

## Status
`planning`
```

**Label:** `safer:implement-junior,planning`

---

## Confidence

**MED-HIGH.**

- Q1, Q2, Q3 are HIGH — argued primary, ranked fallbacks, and rejected alternatives are concrete.
- Q4 is MED — depends on confirming the live 7th-project name (open question 2).
- Q5 is MED — paid-tier split is a future plan, not a tested migration; the "split is mechanical" claim is plausible but unverified.

The whole spec is reversible: if the chosen rule misroutes more issues than the user can stomach, the override `Linear-project:` body line plus a one-shot `--all` re-run fixes any individual case in seconds.

## Routing recommendation

After merge, dispatch the two `implement-junior` follow-ups (above) **in parallel** — they touch different files and have no ordering dependency. Each is a small, well-specified task; haiku per the orchestrate model-routing table is appropriate.

If a stamina fan-out is being considered for this spec under the sbd#93 routing doctrine: opus-supervisor adds little here. The questions are tactical and the rejected alternatives are already enumerated; a second-opinion review of Q4 (project inventory, where live state is the unknown) would be the most valuable single review focus, but does not require a fan-out.
