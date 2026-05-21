#!/usr/bin/env node

/**
 * @file CI shim. Runs the architecture analyzer against the cwd's
 * project, prints each finding, and exits non-zero on any
 * error-severity diagnostic. Invocation: `node lsp/architecture/check.js`.
 *
 * Monorepo handling: if cwd declares pnpm/npm/yarn workspaces, the
 * analyzer is run once per workspace package (each carries its own
 * `tsconfig.json`); findings from every package are merged into the
 * single output stream. Single-project repos fall through to the
 * pre-fix single `analyzeWorkspace(cwd)` invocation.
 *
 * Per-package architecture options come from
 * `settings["agent-code-guard"].architecture` in each package's
 * eslint flat config (`eslint.config.{mjs,js,cjs}`). Packages
 * without an eslint config or with a malformed shape fall back to
 * analyzer defaults.
 */

import process from "node:process";
import { analyzeWorkspace } from "./analyzer/index.js";
import { resolveArchitectureOptionsFromEslint } from "./eslint-options-resolver.js";
import { discoverProjectRoots } from "./workspace-discovery.js";

async function main(): Promise<void> {
  const cwd = process.cwd();
  const discovered = discoverProjectRoots(cwd);
  let hasError = false;
  for (const projectRoot of discovered.projectRoots) {
    const options = await resolveArchitectureOptionsFromEslint(projectRoot).catch(() => null);
    const report = analyzeWorkspace({ ...(options ?? {}), projectRoot });
    for (const finding of report.diagnostics) {
      if (finding.severity === "error") hasError = true;
      const line = `${finding.severity.toUpperCase()} ${finding.ruleId} ${finding.file}: ${finding.message}`;
      process.stdout.write(`${line}\n`);
    }
  }
  process.exit(hasError ? 1 : 0);
}

main().catch((err) => {
  process.stderr.write(`${err instanceof Error ? err.stack ?? err.message : String(err)}\n`);
  process.exit(2);
});
