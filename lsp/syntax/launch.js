#!/usr/bin/env node
/**
 * @file Spawns the upstream `vscode-eslint-language-server` (from
 * `vscode-langservers-extracted`) with `--stdio`, inheriting the
 * parent process's stdio and forwarding extra args through. The
 * Claude plugin manifest (`.claude-plugin/plugin.json`) declares this
 * launcher as the entry point for the `agent-code-guard-syntax` LSP;
 * the launcher exists so the manifest can reference a single path
 * regardless of where the ESLint binary lives on the user's machine.
 *
 * If the binary is not on PATH, the launcher reports the missing
 * dependency and exits non-zero. There is no in-repo fallback server;
 * the user runs `/safer:setup` (or installs the binary directly) to
 * get the syntax LSP.
 */

import { spawn } from "node:child_process";

const BIN = "vscode-eslint-language-server";
const child = spawn(BIN, ["--stdio", ...process.argv.slice(2)], {
  stdio: "inherit",
});

child.on("error", (err) => {
  if (err.code === "ENOENT") {
    process.stderr.write(
      `${BIN} not found. Run /safer:setup to install.\n`,
    );
    process.exit(1);
  }
  process.stderr.write(`${BIN} failed to start: ${err.message}\n`);
  process.exit(1);
});

child.on("exit", (code, signal) => {
  if (signal !== null) process.kill(process.pid, signal);
  else process.exit(code ?? 0);
});
