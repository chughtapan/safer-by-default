/**
 * @file Resolve architecture options from a project's ESLint flat
 * config. The analyzer's `ArchitectureOptionsInput` schema is the
 * source of truth for shape — `eslint.config.{mjs,js,cjs}` is the
 * place projects already configure their linting, so reading the
 * architecture options from the same file avoids a second config
 * surface.
 *
 * Convention: architecture options live at
 * `settings["agent-code-guard"].architecture` in the flat config.
 * Multiple entries may carry settings; their `settings` objects are
 * shallow-merged in array order (later entries win) for any entry
 * whose `files` (and not `ignores`) glob matches a representative
 * source file at the project root.
 *
 * The resolver is intentionally narrow:
 *   - Only `eslint.config.{mjs,js,cjs}` are loaded. `.ts` configs
 *     would need a transformer; punt until a real project asks.
 *   - The glob matcher implements the subset of minimatch used in
 *     real flat configs (`**`, `*`, literal segments). Bare-string
 *     patterns and string arrays are honoured; functions and
 *     RegExps in `files`/`ignores` are treated as "matches" (i.e.,
 *     the entry's settings are considered) — better to over-include
 *     than to silently drop configuration.
 *   - Any failure (missing file, import error, malformed shape)
 *     returns `null`. The caller falls back to defaults.
 */

import fs from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";

const CONFIG_FILENAMES = [
  "eslint.config.mjs",
  "eslint.config.js",
  "eslint.config.cjs",
];

const REPRESENTATIVE_SOURCE_FILES = [
  "src/index.ts",
  "src/main.ts",
  "index.ts",
  "main.ts",
];

interface FlatConfigEntry {
  readonly files?: unknown;
  readonly ignores?: unknown;
  readonly settings?: unknown;
}

/**
 * Look up `settings["agent-code-guard"].architecture` from the
 * eslint flat config at `projectRoot`, resolved against a
 * representative source file. Returns `null` when no config is
 * present, no entries match, or the architecture key is absent.
 * @param projectRoot Absolute path to the package root that owns the
 * eslint config.
 * @returns Architecture options bag suitable for
 * `analyzeWorkspace({ projectRoot, ...options })`, or `null`.
 */
export async function resolveArchitectureOptionsFromEslint(
  projectRoot: string,
): Promise<Record<string, unknown> | null> {
  const configPath = findConfigPath(projectRoot);
  if (configPath === null) return null;

  const flatConfig = await importFlatConfig(configPath);
  if (flatConfig === null) return null;

  const representative = pickRepresentativeFile(projectRoot);
  const merged: Record<string, unknown> = {};
  for (const entry of flatConfig) {
    if (!isEntry(entry)) continue;
    if (!entryAppliesTo(entry, representative, projectRoot)) continue;
    if (typeof entry.settings === "object" && entry.settings !== null) {
      Object.assign(merged, entry.settings as Record<string, unknown>);
    }
  }

  const guard = merged["agent-code-guard"];
  if (typeof guard !== "object" || guard === null) return null;
  const arch = (guard as Record<string, unknown>).architecture;
  if (typeof arch !== "object" || arch === null) return null;
  return arch as Record<string, unknown>;
}

function findConfigPath(projectRoot: string): string | null {
  for (const name of CONFIG_FILENAMES) {
    const candidate = path.join(projectRoot, name);
    try {
      if (fs.statSync(candidate).isFile()) return candidate;
    } catch {
      continue;
    }
  }
  return null;
}

async function importFlatConfig(
  configPath: string,
): Promise<readonly FlatConfigEntry[] | null> {
  try {
    // Cache-bust per call so the LSP picks up edits without restart;
    // small cost since project counts are bounded and eslint configs
    // are tiny modules.
    const url = pathToFileURL(configPath).toString() + `?t=${Date.now()}`;
    const mod = (await import(url)) as { default?: unknown };
    const cfg = mod.default ?? mod;
    if (!Array.isArray(cfg)) return null;
    return cfg as readonly FlatConfigEntry[];
  } catch {
    return null;
  }
}

function pickRepresentativeFile(projectRoot: string): string {
  for (const rel of REPRESENTATIVE_SOURCE_FILES) {
    const candidate = path.join(projectRoot, rel);
    try {
      if (fs.statSync(candidate).isFile()) return candidate;
    } catch {
      continue;
    }
  }
  // Fall back to the synthetic src/index.ts — the matcher will treat
  // it the same as a real file for `src/**/*.ts` globs, which is the
  // common case.
  return path.join(projectRoot, "src/index.ts");
}

function isEntry(value: unknown): value is FlatConfigEntry {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function entryAppliesTo(
  entry: FlatConfigEntry,
  filePath: string,
  projectRoot: string,
): boolean {
  // No `files` → entry applies everywhere unless explicitly ignored.
  const inFiles =
    entry.files === undefined
      ? true
      : matchesAnyGlob(toStringList(entry.files), filePath, projectRoot);
  if (!inFiles) return false;
  if (entry.ignores !== undefined) {
    if (matchesAnyGlob(toStringList(entry.ignores), filePath, projectRoot)) {
      return false;
    }
  }
  return true;
}

function toStringList(raw: unknown): readonly string[] {
  if (typeof raw === "string") return [raw];
  if (!Array.isArray(raw)) return [];
  const out: string[] = [];
  for (const item of raw) {
    if (typeof item === "string") out.push(item);
  }
  return out;
}

function matchesAnyGlob(
  patterns: readonly string[],
  filePath: string,
  projectRoot: string,
): boolean {
  if (patterns.length === 0) return false;
  const relative = path.relative(projectRoot, filePath).split(path.sep).join("/");
  for (const pattern of patterns) {
    if (globMatches(pattern, relative)) return true;
  }
  return false;
}

/**
 * Match a single eslint-style glob against a posix-style relative
 * path. Supports the subset that actually appears in real flat
 * configs: literal segments, `*` (one segment, no slash), `**`
 * (zero or more segments). Brace expansion and character classes
 * are out of scope.
 * @param pattern Glob pattern.
 * @param relative Posix-style path relative to the project root.
 * @returns True if the pattern matches.
 */
export function globMatches(pattern: string, relative: string): boolean {
  // Normalize leading "./" if present.
  const normalisedPattern = pattern.replace(/^\.\//, "");
  const regex = globToRegExp(normalisedPattern);
  return regex.test(relative);
}

function globToRegExp(pattern: string): RegExp {
  let out = "^";
  let i = 0;
  while (i < pattern.length) {
    const c = pattern[i];
    if (c === "*" && pattern[i + 1] === "*") {
      // **
      if (pattern[i + 2] === "/") {
        // **/ matches zero or more directory segments
        out += "(?:.*/)?";
        i += 3;
        continue;
      }
      out += ".*";
      i += 2;
      continue;
    }
    if (c === "*") {
      // single * matches anything but a slash
      out += "[^/]*";
      i += 1;
      continue;
    }
    if (c === "?") {
      out += "[^/]";
      i += 1;
      continue;
    }
    if ("./+^${}()|[]\\".includes(c)) {
      out += "\\" + c;
      i += 1;
      continue;
    }
    out += c;
    i += 1;
  }
  out += "$";
  return new RegExp(out);
}
