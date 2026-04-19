# scenarios/

cc-judge scenarios that exercise `PRINCIPLES.md` against agent behavior. Each scenario is an agent prompt, a fixture workspace, a judge rubric, and a verdict. The suite is the test suite for the doctrine.

Spec: [`docs/specs/evals-suite-v1.md`](../docs/specs/evals-suite-v1.md). Routing and v1 scope live there.

## Layout

```
scenarios/
├── principles/                  # one sub-directory per axiom that has scenarios in v1
│   ├── P1-types-beat-tests/
│   ├── P2-validate-at-boundaries/
│   ├── P3-typed-errors/
│   ├── P4-exhaustiveness/
│   └── P7-brake/
├── modality-routing/            # flat — few scenarios until volume justifies nesting
├── artifact-discipline/         # flat
├── debt-multiplier/             # flat
└── runs/                        # committed baseline + post-model-upgrade run output
    └── v1-baseline-<ISO>/       # one directory per run batch
```

Principle sub-directories use the `P<N>-<short-name>/` shape because that axis will grow the most (each axiom has many distinct anti-pattern shapes). The other axes start flat; promote to `-<short-name>/` sub-directories when any axis passes ~5 scenarios.

## Axis

Every scenario YAML carries a required `axis` field, one of eleven literals:

- `principle-1-types-beat-tests`
- `principle-2-validate-at-boundaries`
- `principle-3-typed-errors`
- `principle-4-exhaustiveness`
- `principle-5-junior-dev-rule`
- `principle-6-budget-gate`
- `principle-7-brake`
- `principle-8-ratchet`
- `modality-routing`
- `artifact-discipline`
- `debt-multiplier`

Reports aggregate pass-rate by axis. Typos are decode errors — the set is enumerated at the cc-judge boundary.

## Scenario shape

Each YAML is loaded by `cc-judge`'s `ScenarioYamlSchema`. Required fields:

| Field | Purpose |
|---|---|
| `id` | Globally unique scenario id. Convention: `<axis>.<short-name>` |
| `name` | One-line title |
| `description` | What the scenario tests, what pass and fail look like |
| `axis` | One of the 11 literals above |
| `setupPrompt` | The prompt the agent receives |
| `workspace` | Fixture files the agent edits. Paths are scenario-relative; no `..`, no absolute paths |
| `timeoutMs` | Per-scenario wall-clock budget |
| `expectedBehavior` | Free-form prose the judge reads alongside the rubric |
| `validationChecks` | Discrete rubric bullets — mix of pass conditions and `ANTI-PATTERN (FAIL)` conditions |

**Rubrics are principle-specific.** Generic "code looks good" bullets produce judge agreement with whatever the agent did, which is a no-op meter. Every rubric in this directory names at least one principle-specific anti-pattern that would fail the scenario even if the code compiled.

## Running

```bash
# Run a single scenario
cc-judge run scenarios/principles/P3-typed-errors/raw-throw-in-effect-gen.yaml \
  --runtime subprocess --bin $(which claude) \
  --judge claude-opus-4-7 --results scenarios/runs/ad-hoc-$(date -u +%Y-%m-%dT%H%M%S)

# Run every scenario under an axis
cc-judge run 'scenarios/principles/**/*.yaml' --runtime subprocess --bin $(which claude) \
  --judge claude-opus-4-7 --results scenarios/runs/principles-$(date -u +%Y-%m-%dT%H%M%S)

# Run the full suite
cc-judge run 'scenarios/**/*.yaml' --runtime subprocess --bin $(which claude) \
  --judge claude-opus-4-7 --runs 3 --results scenarios/runs/full-$(date -u +%Y-%m-%dT%H%M%S)
```

`--runs 3` triples the per-scenario invocations; a scenario that passes 3-for-3 or fails 3-for-3 every time is miscalibrated (see spec §7 acceptance criteria).

CI does **not** run these yet. v1 runs are on-demand and on `PRINCIPLES.md` edits. CI wiring is deferred (spec open question 3).

## v1 first batch (4 scenarios, one per axis)

- `principles/P3-typed-errors/raw-throw-in-effect-gen.yaml` — migrated from the cc-judge dogfood scenario.
- `principles/P1-types-beat-tests/brand-vs-string-ids.yaml`
- `modality-routing/eleven-file-refactor.yaml`
- `artifact-discipline/confidence-with-evidence.yaml`

The 4th axis (`debt-multiplier`) is held for the next batch; its rubric is harder to write (judging "did the agent push back" is subtler than judging code shape) and benefits from going second once the first three calibrate rubric voice. Remaining 8 scenarios ship as junior follow-ups per spec §7.

## Adding a scenario

1. Pick an axis. If you cannot name one, do not write the scenario.
2. Create the YAML under the axis's directory. `id` is `<axis>.<short-name>`.
3. Write `expectedBehavior` as prose the judge can read cold.
4. Write `validationChecks` as a mix of pass bullets and explicit `ANTI-PATTERN (FAIL):` bullets. At least one anti-pattern must be principle-specific — "bare catch," "non-null assertion," "Promise erases the error channel," etc.
5. Run the scenario three times against the current model (`--runs 3`). If it passes three-for-three or fails three-for-three, the rubric is miscalibrated; tune before landing.
6. Every `PRINCIPLES.md` edit ships with or updates at least one scenario covering the change (spec open question 2).
