# tests/test-linear-v2

Test scaffolds for Linear taxonomy v2. Stub only — architect adds test *names*, not bodies. Implementer fills each bullet with a runnable test.

## Acceptance-to-test map

Each bullet below corresponds to one acceptance criterion from sbd#113 spec rev 2. One criterion may produce multiple tests.

- [ ] `test-taxonomy-single-source-of-truth.sh` — grep every live project name across repo; assert matches confined to `config/linear-taxonomy.yaml`. Covers "Single source of truth" and "No second hard-coded list."
- [ ] `test-taxonomy-schema-validation.sh` — feeds malformed YAML fixtures into `validate_taxonomy`; asserts tag 11 or 12 per shape. Covers schema invariants.
- [ ] `test-taxonomy-labelmap-crossref.sh` — labelMap project not in projects → tag 12. Covers Invariant 1.
- [ ] `test-resolve-manual-override.sh` — rule (1) highest. Covers precedence.
- [ ] `test-resolve-parent-ref-with-project.sh` — rule (2) matches when parent has project.
- [ ] `test-resolve-parent-ref-empty-project.sh` — rule (2) marker present, parent has no project → falls through to rule (3) then (4) then no-match. Covers fallthrough semantics concern raised in sbd#120.
- [ ] `test-resolve-parent-heading.sh` — rule (3) matches via `## Parent` + `#N`.
- [ ] `test-resolve-parent-heading-single-hop.sh` — Q3 decision: grandparent is NOT consulted even if parent has no project.
- [ ] `test-resolve-label-keyword.sh` — rule (4) first-match-wins against labelMap order.
- [ ] `test-resolve-no-match.sh` — every rule misses; resolver returns empty stdout, exit 0; caller substitutes catchall.
- [ ] `test-resolve-moltzap-fixtures.sh` — sbd#103, sbd#107, sbd#108, sbd#109 → `Moltzap migration`. Acceptance: "Moltzap sub-issues route correctly." This test is the spot-check addressing sbd#120 concern 2.
- [ ] `test-linear-auth-header-shape.sh` — captures the outbound Authorization header (via curl interceptor or a test-only HTTP_PROXY); asserts literal substring `Bearer ` never appears. Covers #112 regression test required by acceptance.
- [ ] `test-drift-report-no-drift.sh` — taxonomy matches live Linear → exit 0, empty delta.
- [ ] `test-drift-report-missing-in-linear.sh` — taxonomy has extra project → exit 2, delta names the project.
- [ ] `test-drift-report-extra-in-linear.sh` — Linear has extra project → exit 2, delta names the project.
- [ ] `test-bootstrap-missing-project.sh` — fail-loudly path; exit 42, stderr names first missing project.
- [ ] `test-cli-assign-projects-dry-run.sh` — end-to-end against a fixture set; asserts RESULT line shape.
- [ ] `test-cli-unknown-subcommand.sh` — exit 1, usage on stdout.

Every file above contains a single `echo "NOT IMPLEMENTED"; exit 99` line in the architect PR. Implementer replaces each with a real test body.
