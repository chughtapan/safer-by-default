// Orchestrate dispatch-wave ready-set resolver — the deterministic DAG gate over the
// decomposition table. Given the rows and their current states, return the rows that are safe to
// dispatch in this wave: queued (`planning`) rows whose every dependency is `done`.
//
// This is the canonical encoding of the dependency-order rule that orchestrate Phase 5 walks in
// prose. dispatch-wave.workflow.js inlines a mirror of `readySet()` (Workflow scripts cannot
// import local files). This module + its --selftest are the source of truth; keep the mirror in
// sync.
//
// The resolver is pure and conservative: it computes WHICH rows are dispatchable, never dispatches
// or transitions anything. Every human gate (contract budget, ratchet-up park, stop conditions)
// is applied by the prose lifecycle AFTER this returns — the resolver only answers "deps satisfied
// and not parked?". A dependency is satisfied iff its row's state is exactly `done`; the
// plan-approved -> done cascade timing is a prose-lifecycle decision, not the resolver's.

/** @typedef {{ subIssue: string|number, state: string, dependsOn?: (string|number)[] }} Row */

const PARKED = new Set(["paused", "awaiting-amendment", "blocked"]);
// Tokens meaning "no dependency" (row is unblocked). NOT included: `#TBD`/`tbd` — that is a
// placeholder for a dependency row that does not exist yet, so it is treated as a real,
// unsatisfied dependency (the prose lifecycle creates it later; the row is not ready until then).
const NO_DEP = new Set(["", "none", "-"]);

const norm = (id) => String(id ?? "").trim().replace(/^#/, "");

/**
 * @param {Row[]} rows
 * @returns {Row[]} the dispatchable subset, in input order
 */
export function readySet(rows) {
  if (!Array.isArray(rows)) return [];
  const stateById = new Map(rows.map((r) => [norm(r.subIssue), r.state]));
  const depDone = (dep) => stateById.get(norm(dep)) === "done";
  const realDeps = (r) =>
    (r.dependsOn ?? []).filter((d) => !NO_DEP.has(norm(d).toLowerCase()));

  return rows.filter(
    (r) =>
      r.state === "planning" &&
      !PARKED.has(r.state) &&
      realDeps(r).every(depDone),
  );
}

// --selftest: exercise the DAG gate. Exit non-zero on any mismatch.
function selftest() {
  const ids = (rows) => readySet(rows).map((r) => norm(r.subIssue)).sort();
  const eq = (a, b) => a.length === b.length && a.every((v, i) => v === b[i]);

  const cases = [
    {
      name: "no-deps planning row is ready",
      rows: [{ subIssue: 1, state: "planning", dependsOn: [] }],
      want: ["1"],
    },
    {
      name: "dep done -> ready; dep open -> not",
      rows: [
        { subIssue: 1, state: "done" },
        { subIssue: 2, state: "planning", dependsOn: ["#1"] },
        { subIssue: 3, state: "planning", dependsOn: ["#2"] },
      ],
      want: ["2"],
    },
    {
      name: "multiple deps: all done -> ready, partial -> not",
      rows: [
        { subIssue: 1, state: "done" },
        { subIssue: 2, state: "done" },
        { subIssue: 3, state: "implementing" },
        { subIssue: 4, state: "planning", dependsOn: ["1", "2"] },
        { subIssue: 5, state: "planning", dependsOn: ["1", "3"] },
      ],
      want: ["4"],
    },
    {
      name: "parked/blocked rows never dispatch",
      rows: [
        { subIssue: 1, state: "awaiting-amendment", dependsOn: [] },
        { subIssue: 2, state: "paused", dependsOn: [] },
        { subIssue: 3, state: "blocked", dependsOn: [] },
      ],
      want: [],
    },
    {
      name: "non-planning states (in-flight / closed) are not candidates",
      rows: [
        { subIssue: 1, state: "implementing", dependsOn: [] },
        { subIssue: 2, state: "review", dependsOn: [] },
        { subIssue: 3, state: "done", dependsOn: [] },
      ],
      want: [],
    },
    {
      name: "#TBD / unknown dep is unsatisfied -> not ready",
      rows: [{ subIssue: 5, state: "planning", dependsOn: ["#TBD"] }],
      want: [],
    },
    {
      name: "'none' dependsOn token means no dependency -> ready",
      rows: [{ subIssue: 7, state: "planning", dependsOn: ["none"] }],
      want: ["7"],
    },
  ];

  let failed = 0;
  for (const c of cases) {
    const got = ids(c.rows);
    if (!eq(got, [...c.want].sort())) {
      failed++;
      console.error(`FAIL: ${c.name}: got [${got}], want [${c.want}]`);
    }
  }
  if (failed > 0) {
    console.error(`ready-set selftest: ${failed} case(s) failed`);
    process.exit(1);
  }
  console.log(`ready-set selftest: ${cases.length} cases passed`);
}

if (process.argv.includes("--selftest")) selftest();
