import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import {
  discoverProjectRoots,
  parsePnpmWorkspacePackages,
} from "../workspace-discovery.js";

const tempDirs = new Set<string>();

afterEach(() => {
  for (const dir of tempDirs) fs.rmSync(dir, { recursive: true, force: true });
  tempDirs.clear();
});

function makeTempTree(files: Record<string, string>): string {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "acg-workspace-discovery-"));
  tempDirs.add(root);
  for (const [rel, contents] of Object.entries(files)) {
    const absolute = path.join(root, rel);
    fs.mkdirSync(path.dirname(absolute), { recursive: true });
    fs.writeFileSync(absolute, contents);
  }
  return root;
}

const TSCONFIG = JSON.stringify({ compilerOptions: { target: "ES2022" } });

describe("parsePnpmWorkspacePackages", () => {
  it("parses a flat sequence of package patterns", () => {
    const text = ["packages:", "  - 'packages/*'", "  - apps/*"].join("\n");
    expect(parsePnpmWorkspacePackages(text)).toEqual(["packages/*", "apps/*"]);
  });

  it("ignores leading comments and blank lines", () => {
    const text = [
      "# pnpm workspace",
      "",
      "packages:",
      "  # inline comment",
      "  - \"packages/*\"",
    ].join("\n");
    expect(parsePnpmWorkspacePackages(text)).toEqual(["packages/*"]);
  });

  it("stops at the next top-level key", () => {
    const text = [
      "packages:",
      "  - packages/*",
      "catalog:",
      "  - other-thing",
    ].join("\n");
    expect(parsePnpmWorkspacePackages(text)).toEqual(["packages/*"]);
  });

  it("returns an empty list when packages: is absent", () => {
    expect(parsePnpmWorkspacePackages("catalog:\n  - x\n")).toEqual([]);
  });
});

describe("discoverProjectRoots", () => {
  it("expands pnpm-workspace.yaml globs and filters by tsconfig.json", () => {
    const root = makeTempTree({
      "pnpm-workspace.yaml": "packages:\n  - 'packages/*'\n",
      "packages/server/tsconfig.json": TSCONFIG,
      "packages/server/package.json": JSON.stringify({ name: "server" }),
      "packages/client/tsconfig.json": TSCONFIG,
      "packages/client/package.json": JSON.stringify({ name: "client" }),
      // No tsconfig — must be filtered out.
      "packages/docs/package.json": JSON.stringify({ name: "docs" }),
    });
    const result = discoverProjectRoots(root);
    expect(result.source).toBe("pnpm-workspace");
    expect(result.projectRoots).toEqual([
      path.join(root, "packages/client"),
      path.join(root, "packages/server"),
    ]);
  });

  it("applies negative pnpm patterns", () => {
    const root = makeTempTree({
      "pnpm-workspace.yaml": [
        "packages:",
        "  - 'packages/*'",
        "  - '!packages/legacy'",
      ].join("\n"),
      "packages/server/tsconfig.json": TSCONFIG,
      "packages/legacy/tsconfig.json": TSCONFIG,
    });
    const result = discoverProjectRoots(root);
    expect(result.projectRoots).toEqual([path.join(root, "packages/server")]);
  });

  it("expands package.json workspaces array", () => {
    const root = makeTempTree({
      "package.json": JSON.stringify({
        name: "monorepo",
        private: true,
        workspaces: ["packages/*"],
      }),
      "packages/api/tsconfig.json": TSCONFIG,
      "packages/web/tsconfig.json": TSCONFIG,
    });
    const result = discoverProjectRoots(root);
    expect(result.source).toBe("package-json-workspaces");
    expect(result.projectRoots).toEqual([
      path.join(root, "packages/api"),
      path.join(root, "packages/web"),
    ]);
  });

  it("expands package.json workspaces object form", () => {
    const root = makeTempTree({
      "package.json": JSON.stringify({
        name: "monorepo",
        private: true,
        workspaces: { packages: ["packages/*"], nohoist: [] },
      }),
      "packages/api/tsconfig.json": TSCONFIG,
    });
    const result = discoverProjectRoots(root);
    expect(result.source).toBe("package-json-workspaces");
    expect(result.projectRoots).toEqual([path.join(root, "packages/api")]);
  });

  it("falls back to [workspaceRoot] for a single-project repo", () => {
    const root = makeTempTree({
      "tsconfig.json": TSCONFIG,
      "package.json": JSON.stringify({ name: "single" }),
      "src/index.ts": "export const x = 1;\n",
    });
    const result = discoverProjectRoots(root);
    expect(result.source).toBe("fallback");
    expect(result.projectRoots).toEqual([root]);
  });

  it("falls back to [workspaceRoot] when a workspace declaration matches no tsconfig-bearing packages", () => {
    const root = makeTempTree({
      "pnpm-workspace.yaml": "packages:\n  - 'packages/*'\n",
      // Workspace child has no tsconfig — analyzer can't run on it.
      "packages/docs/package.json": JSON.stringify({ name: "docs" }),
    });
    const result = discoverProjectRoots(root);
    expect(result.source).toBe("fallback");
    expect(result.projectRoots).toEqual([root]);
  });

  it("prefers pnpm-workspace.yaml over package.json workspaces when both are present", () => {
    const root = makeTempTree({
      "pnpm-workspace.yaml": "packages:\n  - 'pnpm-pkgs/*'\n",
      "package.json": JSON.stringify({
        name: "mixed",
        workspaces: ["npm-pkgs/*"],
      }),
      "pnpm-pkgs/a/tsconfig.json": TSCONFIG,
      "npm-pkgs/b/tsconfig.json": TSCONFIG,
    });
    const result = discoverProjectRoots(root);
    expect(result.source).toBe("pnpm-workspace");
    expect(result.projectRoots).toEqual([path.join(root, "pnpm-pkgs/a")]);
  });

  it("walks deeper globs with **", () => {
    const root = makeTempTree({
      "pnpm-workspace.yaml": "packages:\n  - 'packages/**'\n",
      "packages/a/tsconfig.json": TSCONFIG,
      "packages/group/b/tsconfig.json": TSCONFIG,
    });
    const result = discoverProjectRoots(root);
    expect(result.projectRoots).toEqual([
      path.join(root, "packages/a"),
      path.join(root, "packages/group/b"),
    ]);
  });

  it("skips node_modules and dotted directories during expansion", () => {
    const root = makeTempTree({
      "pnpm-workspace.yaml": "packages:\n  - 'packages/*'\n",
      "packages/server/tsconfig.json": TSCONFIG,
      "packages/node_modules/pkg/tsconfig.json": TSCONFIG,
      "packages/.cache/tsconfig.json": TSCONFIG,
    });
    const result = discoverProjectRoots(root);
    expect(result.projectRoots).toEqual([path.join(root, "packages/server")]);
  });
});
