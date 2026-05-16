import { spawnSync } from "node:child_process";
import path from "node:path";
import { afterEach, expect, it } from "vitest";
import { clearArchitectureCache } from "../analyzer/project/cache/index.js";
import {
  cleanupFixtures,
  makeFixtureProject,
} from "../server/test-support/fixtures.js";
import { makeProject, cleanupArchitectureFixtures } from "../analyzer/test-support/analyzer-fixtures.js";

afterEach(() => {
  cleanupFixtures();
  cleanupArchitectureFixtures();
  clearArchitectureCache();
});

// The check.ts CI shim is the project-level "is this codebase clean"
// surface: it must exit 0 against a healthy fixture and non-zero
// against a fixture that fires any error-severity diagnostic. Both
// behaviors are gated through `analyzeWorkspace`; the script is a thin
// process boundary on top.

const CHECK_SCRIPT = path.resolve(import.meta.dirname, "..", "dist", "check.js");

it("check: exits 0 on a project with no error-severity findings", () => {
  const root = makeFixtureProject();
  const result = spawnSync("node", [CHECK_SCRIPT], { cwd: root, encoding: "utf8" });
  expect(result.status).toBe(0);
});

it("check: exits 1 on a project with an error-severity finding", () => {
  // Construct a fixture that fires `no-internal-subpath-export`
  // (error severity) via a wildcard export. The default
  // `maxWildcardExports` is 0, so a single wildcard subpath fires.
  const root = makeProject({
    "package.json": JSON.stringify({
      name: "fixture",
      version: "1.0.0",
      type: "module",
      exports: {
        ".": { import: "./dist/index.js", types: "./dist/index.d.ts" },
        "./*": { import: "./dist/*.js" },
      },
    }),
    "src/index.ts": "export const x = 1;\n",
  });
  const result = spawnSync("node", [CHECK_SCRIPT], { cwd: root, encoding: "utf8" });
  expect(result.status).toBe(1);
});
