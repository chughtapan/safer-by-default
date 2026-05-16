#!/usr/bin/env node

/**
 * @file CI shim. Reads `tsconfig.json` from cwd, runs the
 * architecture analyzer once, prints each finding, and exits
 * non-zero when any error-severity diagnostic is present.
 *
 * Invocation: `node lsp/architecture/check.js` from the consuming
 * repo. No flags, no argparse — CI users wire this into their job
 * script directly.
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
