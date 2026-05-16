#!/usr/bin/env node

/**
 * @file CI shim. Runs the architecture analyzer against the cwd's
 * project, prints each finding, and exits non-zero on any
 * error-severity diagnostic. Invocation: `node lsp/architecture/check.js`.
 */

import process from "node:process";
import { analyzeWorkspace } from "./analyzer/index.js";

function main(): void {
  const report = analyzeWorkspace({ projectRoot: process.cwd() });
  let hasError = false;
  for (const finding of report.diagnostics) {
    if (finding.severity === "error") hasError = true;
    const line = `${finding.severity.toUpperCase()} ${finding.ruleId} ${finding.file}: ${finding.message}`;
    process.stdout.write(`${line}\n`);
  }
  process.exit(hasError ? 1 : 0);
}

main();
