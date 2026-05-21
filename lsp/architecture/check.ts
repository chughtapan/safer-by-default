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
 */

import process from "node:process";
import { analyzeWorkspace } from "./analyzer/index.js";
import { discoverProjectRoots } from "./workspace-discovery.js";

function main(): void {
  const cwd = process.cwd();
  const discovered = discoverProjectRoots(cwd);
  let hasError = false;
  for (const projectRoot of discovered.projectRoots) {
    const report = analyzeWorkspace({ projectRoot });
    for (const finding of report.diagnostics) {
      if (finding.severity === "error") hasError = true;
      const line = `${finding.severity.toUpperCase()} ${finding.ruleId} ${finding.file}: ${finding.message}`;
      process.stdout.write(`${line}\n`);
    }
  }
  process.exit(hasError ? 1 : 0);
}

main();
