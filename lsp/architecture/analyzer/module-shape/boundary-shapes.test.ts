import * as fc from "fast-check";
import { afterEach, expect, it } from "vitest";
import { analyzeWorkspace } from "../index.js";
import { ARCHITECTURE_DIAGNOSTIC_RULE_IDS } from "../rule-ids.js";
import {
  cleanupArchitectureFixtures,
  diagnosticsByRule,
  folderApiFixture,
  implicitBoundaryFixture,
  makeProject,
  segmentArb,
  sharedKernelCohesionFixture,
} from "../test-support/analyzer-fixtures.js";

afterEach(cleanupArchitectureFixtures);

it("surfaces architecture diagnostics through the analyzer API", () => {
  const root = makeInventoryProject();
  const findings = analyzeWorkspace({ projectRoot: root }).diagnostics.filter(
    (d) => d.ruleId === "no-inventory-barrel",
  );

  expect(findings).toHaveLength(1);
  expect(findings[0]?.ruleId).toBe("no-inventory-barrel");
  expect(findings[0]?.message).toContain("This exports inventory");
});

it("infers the nearest package root when projectRoot is omitted", () => {
  const root = makeInventoryProject();
  const findings = analyzeWorkspace({ projectRoot: root }).diagnostics.filter(
    (d) => d.ruleId === "no-inventory-barrel",
  );

  expect(findings).toHaveLength(1);
  expect(findings[0]?.message).toContain("This exports inventory");
});

it("rule id registry covers every architecture diagnostic family", () => {
  // Spot-check that the registry exposes the rule ids the LSP server
  // wires into `code` and `codeDescription.href` per diagnostic.
  const expected = [
    "no-inventory-barrel",
    "no-public-vendor-type-leak",
    "no-folder-cycle",
    "require-curated-public-facade",
    "folder-explicit-api-required",
    "file-implicit-boundary-module",
    "shared-kernel-cohesion",
    "no-large-folder",
    "folder-readme-required",
    "no-distant-folder-import",
  ];
  for (const ruleId of expected) {
    expect(ARCHITECTURE_DIAGNOSTIC_RULE_IDS).toContain(ruleId);
  }
});

it("Property: folder API diagnostics follow outside concrete imports", () => {
  fc.assert(
    fc.property(
      fc.record({
        apiFolder: segmentArb,
        consumerFolder: segmentArb,
        concreteCount: fc.integer({ min: 2, max: 5 }),
        consumerCount: fc.integer({ min: 1, max: 3 }),
        hasFacade: fc.boolean(),
      }),
      (input) => {
        fc.pre(input.apiFolder !== "index" && input.apiFolder !== input.consumerFolder);
        const root = makeProject(folderApiFixture(input));

        expect(diagnosticsByRule(root, "folder-explicit-api-required").length > 0)
          .toBe(!input.hasFacade);
      },
    ),
    { numRuns: 20 },
  );
});

it("Property: implicit boundary diagnostics follow caller/helper topology", () => {
  fc.assert(
    fc.property(
      fc.integer({ min: 2, max: 4 }),
      fc.integer({ min: 2, max: 4 }),
      fc.boolean(),
      (callerCount, helperCount, explicitBoundaryName) => {
        const boundaryName = explicitBoundaryName ? "boundary-api" : "boundary";
        const root = makeProject(
          implicitBoundaryFixture(boundaryName, callerCount, helperCount),
        );
        const options = explicitBoundaryName
          ? {
            facadeFiles: [
              {
                file: `${boundaryName}.ts`,
                reason: "fixture intentionally declares this non-index boundary",
              },
            ],
          }
          : {};

        expect(diagnosticsByRule(root, "file-implicit-boundary-module", options).length > 0)
          .toBe(!explicitBoundaryName);
      },
    ),
    { numRuns: 16 },
  );
});

it("Property: shared-kernel cohesion follows export consumer overlap", () => {
  fc.assert(
    fc.property(
      fc.integer({ min: 6, max: 10 }),
      fc.integer({ min: 4, max: 6 }),
      fc.boolean(),
      (exportCount, consumerCount, cohesive) => {
        const root = makeProject(
          sharedKernelCohesionFixture(exportCount, consumerCount, cohesive),
        );

        expect(diagnosticsByRule(root, "shared-kernel-cohesion").length > 0)
          .toBe(!cohesive);
      },
    ),
    { numRuns: 16 },
  );
});

function makeInventoryProject(): string {
  return makeProject({
    "src/widgets/index.ts": [
      'export { A } from "./a";',
      'export { B } from "./b";',
      'export { C } from "./c";',
      'export { D } from "./d";',
    ].join("\n"),
    "src/widgets/a.ts": "export const A = 1;\n",
    "src/widgets/b.ts": "export const B = 1;\n",
    "src/widgets/c.ts": "export const C = 1;\n",
    "src/widgets/d.ts": "export const D = 1;\n",
    "src/widgets/e.ts": "export const E = 1;\n",
  });
}
