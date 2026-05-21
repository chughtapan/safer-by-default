import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
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

const monorepoFixtureRoots = new Set<string>();

afterEach(() => {
  for (const root of monorepoFixtureRoots) {
    fs.rmSync(root, { recursive: true, force: true });
  }
  monorepoFixtureRoots.clear();
});

function makeMonorepoFixture(packages: Record<string, Record<string, string>>): string {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "acg-check-monorepo-"));
  monorepoFixtureRoots.add(root);
  fs.writeFileSync(
    path.join(root, "pnpm-workspace.yaml"),
    "packages:\n  - 'packages/*'\n",
  );
  fs.writeFileSync(
    path.join(root, "package.json"),
    JSON.stringify({ name: "monorepo-fixture", private: true }, null, 2),
  );
  for (const [pkgName, files] of Object.entries(packages)) {
    const pkgRoot = path.join(root, "packages", pkgName);
    fs.mkdirSync(pkgRoot, { recursive: true });
    for (const [rel, contents] of Object.entries(files)) {
      const absolute = path.join(pkgRoot, rel);
      fs.mkdirSync(path.dirname(absolute), { recursive: true });
      fs.writeFileSync(absolute, contents);
    }
  }
  return root;
}

const MINIMAL_TSCONFIG = JSON.stringify({
  compilerOptions: {
    target: "ES2022",
    module: "NodeNext",
    moduleResolution: "NodeNext",
    strict: true,
    skipLibCheck: true,
    declaration: true,
    outDir: "./dist",
    rootDir: "./src",
  },
  include: ["src/**/*"],
});

it("check: walks every workspace package when run from a pnpm monorepo root", () => {
  // Clean child package — no error-severity findings.
  const cleanPackage: Record<string, string> = {
    "tsconfig.json": MINIMAL_TSCONFIG,
    "package.json": JSON.stringify({
      name: "clean",
      version: "1.0.0",
      type: "module",
      exports: { ".": "./dist/index.js" },
    }),
    "src/index.ts": "export const x = 1;\n",
  };
  // Child package that fires `no-internal-subpath-export` (error).
  const dirtyPackage: Record<string, string> = {
    "tsconfig.json": MINIMAL_TSCONFIG,
    "package.json": JSON.stringify({
      name: "dirty",
      version: "1.0.0",
      type: "module",
      exports: {
        ".": { import: "./dist/index.js", types: "./dist/index.d.ts" },
        "./*": { import: "./dist/*.js" },
      },
    }),
    "src/index.ts": "export const x = 1;\n",
  };
  const root = makeMonorepoFixture({ clean: cleanPackage, dirty: dirtyPackage });
  const result = spawnSync("node", [CHECK_SCRIPT], { cwd: root, encoding: "utf8" });
  expect(result.status).toBe(1);
  // The finding must be attributed to the dirty package, not the root.
  expect(result.stdout).toMatch(/ERROR no-internal-subpath-export .*packages\/dirty/);
  expect(result.stdout).not.toMatch(/ERROR no-internal-subpath-export .*packages\/clean/);
});

it("check: exits 0 when every monorepo package is clean", () => {
  const cleanPackage: Record<string, string> = {
    "tsconfig.json": MINIMAL_TSCONFIG,
    "package.json": JSON.stringify({
      name: "clean",
      version: "1.0.0",
      type: "module",
      exports: { ".": "./dist/index.js" },
    }),
    "src/index.ts": "export const x = 1;\n",
  };
  const root = makeMonorepoFixture({ a: cleanPackage, b: cleanPackage });
  const result = spawnSync("node", [CHECK_SCRIPT], { cwd: root, encoding: "utf8" });
  expect(result.status).toBe(0);
});
