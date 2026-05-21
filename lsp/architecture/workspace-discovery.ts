/**
 * @file Workspace-aware project-root discovery. The architecture
 * analyzer is single-project: one `tsconfig.json` per
 * `analyzeWorkspace` call. The LSP server (and the `check.ts` CI
 * shim) need to map an opaque workspace root — what Claude Code
 * sends in `initialize.workspaceFolders[].uri`, or whatever `cwd`
 * the CI invocation happens to use — to the list of per-package
 * project roots the analyzer should actually walk.
 *
 * Supported workspace declarations:
 *   - `pnpm-workspace.yaml` with a top-level `packages:` list
 *   - `package.json` with a `workspaces` field (npm/yarn-style array,
 *     or `{ packages: […] }` object form)
 *
 * A workspace package counts only if it has its own
 * `tsconfig.json`; the analyzer cannot run without one. Glob globbing
 * supports the patterns that show up in real monorepos (`packages/*`,
 * `apps/**`, leading `!` for negation); fancier minimatch syntax is
 * not implemented and emits no findings beyond the literal directory
 * walk. If no workspace declaration is found, the workspaceRoot is
 * returned as a single-entry list — matching the pre-fix behaviour.
 */

import fs from "node:fs";
import path from "node:path";

export type WorkspaceDiscoverySource =
  | "pnpm-workspace"
  | "package-json-workspaces"
  | "fallback";

export interface WorkspaceDiscoveryResult {
  /** Absolute project-root paths the analyzer should be run against. */
  readonly projectRoots: readonly string[];
  /** Where the project roots came from. `fallback` means single-project. */
  readonly source: WorkspaceDiscoverySource;
}

/**
 * Resolve the analyzer project roots that live under `workspaceRoot`.
 * @param workspaceRoot Absolute path to the LSP workspace folder / CLI cwd.
 * @returns Project roots + the source of the discovery.
 */
export function discoverProjectRoots(
  workspaceRoot: string,
): WorkspaceDiscoveryResult {
  const pnpmPatterns = readPnpmWorkspacePatterns(workspaceRoot);
  if (pnpmPatterns !== null) {
    const roots = expandAndFilter(workspaceRoot, pnpmPatterns);
    if (roots.length > 0) {
      return { projectRoots: roots, source: "pnpm-workspace" };
    }
  }
  const npmPatterns = readPackageJsonWorkspacePatterns(workspaceRoot);
  if (npmPatterns !== null) {
    const roots = expandAndFilter(workspaceRoot, npmPatterns);
    if (roots.length > 0) {
      return { projectRoots: roots, source: "package-json-workspaces" };
    }
  }
  return { projectRoots: [workspaceRoot], source: "fallback" };
}

function expandAndFilter(
  workspaceRoot: string,
  patterns: readonly string[],
): readonly string[] {
  const positive = patterns.filter((p) => !p.startsWith("!"));
  const negative = patterns
    .filter((p) => p.startsWith("!"))
    .map((p) => p.slice(1));
  const positiveDirs = new Set<string>();
  for (const pattern of positive) {
    for (const dir of expandPattern(workspaceRoot, pattern)) {
      positiveDirs.add(dir);
    }
  }
  const negativeDirs = new Set<string>();
  for (const pattern of negative) {
    for (const dir of expandPattern(workspaceRoot, pattern)) {
      negativeDirs.add(dir);
    }
  }
  const out: string[] = [];
  for (const dir of positiveDirs) {
    if (negativeDirs.has(dir)) continue;
    if (!hasTsconfig(dir)) continue;
    out.push(dir);
  }
  out.sort();
  return out;
}

function readPnpmWorkspacePatterns(
  workspaceRoot: string,
): readonly string[] | null {
  const file = path.join(workspaceRoot, "pnpm-workspace.yaml");
  let text: string;
  try {
    text = fs.readFileSync(file, "utf8");
  } catch {
    return null;
  }
  return parsePnpmWorkspacePackages(text);
}

/**
 * Parse the `packages:` list out of a `pnpm-workspace.yaml`. The pnpm
 * schema is broader (catalogs, overrides, etc.) but only the
 * `packages:` list is load-bearing for project-root discovery, so this
 * parser implements the minimum: top-level `packages:` key followed
 * by a YAML sequence of strings, with `#` comments and optional
 * quoting honoured. Anything else is ignored.
 * @param text File contents of `pnpm-workspace.yaml`.
 * @returns The declared `packages:` patterns (empty array if absent).
 */
export function parsePnpmWorkspacePackages(text: string): readonly string[] {
  const lines = text.split(/\r?\n/);
  const out: string[] = [];
  let inPackages = false;
  let packagesIndent = -1;
  for (const raw of lines) {
    const stripped = stripYamlComment(raw);
    if (stripped.trim() === "") continue;
    const indent = leadingSpaces(stripped);
    if (indent === 0) {
      inPackages = /^packages\s*:/.test(stripped);
      packagesIndent = -1;
      continue;
    }
    if (!inPackages) continue;
    if (packagesIndent === -1) packagesIndent = indent;
    if (indent < packagesIndent) {
      inPackages = false;
      continue;
    }
    const m = stripped.match(/^\s+-\s+(.+?)\s*$/);
    if (m === null) continue;
    out.push(stripYamlQuotes(m[1]));
  }
  return out;
}

function stripYamlComment(line: string): string {
  // Pre-quote `#` is a comment; intra-quote `#` is data. The minimal
  // form used in pnpm-workspace.yaml never embeds `#` inside quoted
  // package patterns, so a literal-quote-aware split is overkill.
  const idx = line.indexOf("#");
  return idx === -1 ? line : line.slice(0, idx);
}

function leadingSpaces(line: string): number {
  let i = 0;
  while (i < line.length && line[i] === " ") i += 1;
  return i;
}

function stripYamlQuotes(value: string): string {
  if (value.length >= 2) {
    const first = value[0];
    const last = value[value.length - 1];
    if ((first === '"' && last === '"') || (first === "'" && last === "'")) {
      return value.slice(1, -1);
    }
  }
  return value;
}

function readPackageJsonWorkspacePatterns(
  workspaceRoot: string,
): readonly string[] | null {
  const file = path.join(workspaceRoot, "package.json");
  let text: string;
  try {
    text = fs.readFileSync(file, "utf8");
  } catch {
    return null;
  }
  let json: unknown;
  try {
    json = JSON.parse(text);
  } catch {
    return null;
  }
  if (typeof json !== "object" || json === null) return null;
  const ws = (json as Record<string, unknown>).workspaces;
  if (Array.isArray(ws)) {
    return ws.filter((x): x is string => typeof x === "string");
  }
  if (typeof ws === "object" && ws !== null) {
    const pkgs = (ws as Record<string, unknown>).packages;
    if (Array.isArray(pkgs)) {
      return pkgs.filter((x): x is string => typeof x === "string");
    }
  }
  return null;
}

function expandPattern(
  workspaceRoot: string,
  pattern: string,
): readonly string[] {
  const normalised = pattern.replace(/\/+$/, "");
  if (normalised === "" || normalised === ".") {
    return isDirectory(workspaceRoot) ? [workspaceRoot] : [];
  }
  const segments = normalised.split("/").filter((s) => s !== "" && s !== ".");
  return walkSegments(workspaceRoot, segments);
}

function walkSegments(
  base: string,
  segments: readonly string[],
): readonly string[] {
  if (segments.length === 0) {
    return isDirectory(base) ? [base] : [];
  }
  const [head, ...rest] = segments;
  if (head === "**") {
    const out = new Set<string>(walkSegments(base, rest));
    for (const child of listChildDirs(base)) {
      for (const dir of walkSegments(path.join(base, child), segments)) {
        out.add(dir);
      }
    }
    return [...out];
  }
  if (head.includes("*")) {
    const matcher = wildcardMatcher(head);
    const out: string[] = [];
    for (const child of listChildDirs(base)) {
      if (!matcher(child)) continue;
      out.push(...walkSegments(path.join(base, child), rest));
    }
    return out;
  }
  const next = path.join(base, head);
  if (!isDirectory(next)) return [];
  return walkSegments(next, rest);
}

function wildcardMatcher(segment: string): (name: string) => boolean {
  const re = new RegExp(
    "^" +
      segment
        .replace(/[.+^${}()|[\]\\]/g, "\\$&")
        .replace(/\*/g, "[^/]*") +
      "$",
  );
  return (name) => re.test(name);
}

function listChildDirs(dir: string): readonly string[] {
  try {
    return fs
      .readdirSync(dir, { withFileTypes: true })
      .filter((entry) => entry.isDirectory())
      .filter((entry) => entry.name !== "node_modules" && !entry.name.startsWith("."))
      .map((entry) => entry.name);
  } catch {
    return [];
  }
}

function isDirectory(filePath: string): boolean {
  try {
    return fs.statSync(filePath).isDirectory();
  } catch {
    return false;
  }
}

function hasTsconfig(dir: string): boolean {
  try {
    return fs.statSync(path.join(dir, "tsconfig.json")).isFile();
  } catch {
    return false;
  }
}
