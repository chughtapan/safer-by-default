/**
 * @file Architecture-LSP + ESLint-CLI dogfood. Spawns the architecture
 * LSP (the same binary the production lsp-proxy invokes as a sidecar)
 * against a fixture carrying a `no-cross-domain-sibling-import`
 * violation, AND shells out to `eslint` against the same fixture to
 * prove `agent-code-guard/record-cast` fires via the CLI surface. Asserts:
 *
 *   1. The architecture LSP publishes a diagnostic with
 *      `code === "no-cross-domain-sibling-import"` and a populated
 *      `codeDescription.href` pointing at PRINCIPLES.md.
 *   2. The architecture LSP shuts down cleanly via `shutdown` + `exit`.
 *   3. ESLint CLI exits non-zero on the fixture with at least one
 *      `agent-code-guard/record-cast` violation surfaced.
 *
 * The proxy layer (typescript-language-server + lsp-proxy.py) has its
 * own end-to-end smoke test at .github/workflows/lsp-proxy-smoke.yml;
 * this dogfood targets the two diagnostic surfaces themselves.
 *
 * Run: `pnpm dogfood` from `lsp/architecture/`. Exits non-zero on
 * failure.
 */

import assert from "node:assert/strict";
import { type ChildProcessWithoutNullStreams, spawn } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const SCRIPT_DIR = import.meta.dirname;
// Walk up from SCRIPT_DIR until we find `.claude-plugin/plugin.json`.
// Works whether this file runs from source (bun dogfood.ts) or from
// the compiled dist/ tree (legacy `node dist/dogfood.js`).
function findPluginRoot(start: string): string {
  let cur = start;
  const root = path.parse(cur).root;
  while (cur !== root) {
    if (fs.existsSync(path.join(cur, ".claude-plugin", "plugin.json"))) {
      return cur;
    }
    cur = path.dirname(cur);
  }
  throw new Error(`plugin root (containing .claude-plugin/plugin.json) not found above ${start}`);
}
const PLUGIN_ROOT = findPluginRoot(SCRIPT_DIR);
const FIXTURE_ROOT = path.join(PLUGIN_ROOT, "lsp", "architecture", "dogfood-fixtures", "two-lsp");
const FIXTURE_FILE = path.join(FIXTURE_ROOT, "src", "auth", "client.ts");
const FIXTURE_TEXT = fs.readFileSync(FIXTURE_FILE, "utf8");
const FIXTURE_URI = pathToFileURL(FIXTURE_FILE).toString();
const FIXTURE_WORKSPACE_URI = pathToFileURL(FIXTURE_ROOT).toString();

const PRINCIPLES_URL_PREFIX =
  "https://github.com/chughtapan/safer-by-default/blob/main/PRINCIPLES.md";

class JsonRpcError extends Error {
  constructor(readonly code: number, message: string) {
    super(message);
    this.name = "JsonRpcError";
  }
}

interface LspServerEntry {
  readonly name: string;
  readonly command: string;
  readonly args: readonly string[];
}

interface Diagnostic {
  readonly code?: string | number;
  readonly codeDescription?: { readonly href?: string };
  readonly source?: string;
  readonly message?: string;
}

interface PublishDiagnostics {
  readonly uri: string;
  readonly diagnostics: readonly Diagnostic[];
}

interface DocumentDiagnosticReport {
  readonly kind: "full" | "unchanged";
  readonly items?: readonly Diagnostic[];
}

interface ServerCapabilities {
  readonly diagnosticProvider?: unknown;
}

interface InitializeResult {
  readonly capabilities?: ServerCapabilities;
}

interface PendingRequest {
  resolve: (value: unknown) => void;
  reject: (err: unknown) => void;
}

interface JsonRpcMessage {
  readonly jsonrpc?: "2.0";
  readonly id?: number | string;
  readonly method?: string;
  readonly params?: unknown;
  readonly result?: unknown;
  readonly error?: { code: number; message: string };
}

type ServerRequestHandler = (method: string, params: unknown) => unknown;

// Hardcoded architecture-LSP entry. Bypasses the proxy layer; the proxy
// has its own smoke test (.github/workflows/lsp-proxy-smoke.yml). The
// command + args must match what `lsp/proxy/run.sh` writes into the
// generated config so this test exercises the same binary that ships.
function architectureLspEntry(): LspServerEntry {
  return {
    name: "agent-code-guard-architecture",
    command: "bun",
    args: [path.join(PLUGIN_ROOT, "lsp", "architecture", "server", "index.ts")],
  };
}

function substituteRoot(arg: string): string {
  return arg.replaceAll("${CLAUDE_PLUGIN_ROOT}", PLUGIN_ROOT);
}

class LspClient {
  readonly name: string;
  readonly diagnostics: PublishDiagnostics[] = [];
  readonly #proc: ChildProcessWithoutNullStreams;
  readonly #pending = new Map<number | string, PendingRequest>();
  readonly #onServerRequest: ServerRequestHandler;
  #nextId = 1;
  #buffer = Buffer.alloc(0);
  #stderrTail = "";

  constructor(entry: LspServerEntry, onServerRequest: ServerRequestHandler) {
    this.name = entry.name;
    this.#onServerRequest = onServerRequest;
    const resolvedArgs = entry.args.map(substituteRoot);
    this.#proc = spawn(entry.command, resolvedArgs, {
      stdio: ["pipe", "pipe", "pipe"],
      cwd: FIXTURE_ROOT,
      env: { ...process.env, PATH: lspPath() },
    });
    this.#proc.stdout.on("data", (chunk: Buffer) => this.#handleChunk(chunk));
    this.#proc.stderr.on("data", (chunk: Buffer) => {
      const text = chunk.toString("utf8");
      this.#stderrTail = (this.#stderrTail + text).slice(-4000);
    });
    this.#proc.on("exit", () => this.#failPending("LSP process exited"));
  }

  #failPending(reason: string): void {
    for (const pending of this.#pending.values()) {
      pending.reject(new JsonRpcError(-32099, reason));
    }
    this.#pending.clear();
  }

  request(method: string, params: unknown): Promise<unknown> {
    const id = this.#nextId++;
    this.#write({ jsonrpc: "2.0", id, method, params });
    return new Promise((resolve, reject) => {
      this.#pending.set(id, { resolve, reject });
    });
  }

  notify(method: string, params: unknown): void {
    this.#write({ jsonrpc: "2.0", method, params });
  }

  stderrTail(): string {
    return this.#stderrTail;
  }

  awaitExit(timeoutMs: number): Promise<number | null> {
    return new Promise((resolve) => {
      // SIGTERM first to give the LSP a chance to flush; if it lingers
      // past `timeoutMs`, SIGKILL it. Orphaned eslint-server children
      // spawned by `launch.js` get cleaned by the kernel once their
      // parent dies, but SIGKILL skips finalizers we may have queued.
      const termTimer = setTimeout(() => this.#proc.kill("SIGTERM"), timeoutMs);
      const killTimer = setTimeout(() => {
        this.#proc.kill("SIGKILL");
        resolve(null);
      }, timeoutMs + 1_000);
      this.#proc.on("exit", (code) => {
        clearTimeout(termTimer);
        clearTimeout(killTimer);
        resolve(code);
      });
    });
  }

  killHard(): void {
    if (this.#proc.exitCode === null) this.#proc.kill("SIGKILL");
  }

  #write(message: JsonRpcMessage): void {
    const body = JSON.stringify(message);
    const header = `Content-Length: ${Buffer.byteLength(body, "utf8")}\r\n\r\n`;
    this.#proc.stdin.write(header + body);
  }

  #handleChunk(chunk: Buffer): void {
    this.#buffer = Buffer.concat([this.#buffer, chunk]);
    while (true) {
      const headerEnd = this.#buffer.indexOf("\r\n\r\n");
      if (headerEnd < 0) return;
      const header = this.#buffer.subarray(0, headerEnd).toString("utf8");
      const match = /Content-Length: (\d+)/.exec(header);
      if (match === null || match[1] === undefined) {
        throw new Error(
          `[${this.name}] malformed LSP frame; missing Content-Length: ${header}`,
        );
      }
      const length = parseInt(match[1], 10);
      const bodyStart = headerEnd + 4;
      if (this.#buffer.length < bodyStart + length) return;
      const body = this.#buffer.subarray(bodyStart, bodyStart + length).toString("utf8");
      this.#buffer = this.#buffer.subarray(bodyStart + length);
      let parsed: JsonRpcMessage;
      try {
        parsed = JSON.parse(body) as JsonRpcMessage;
      } catch (err) {
        // A malformed frame in a 'data' event handler would otherwise
        // crash the process and hang every in-flight request. Surface
        // it and fail the pending pool so main() can exit non-zero.
        process.stderr.write(
          `[${this.name}] malformed JSON-RPC body: ${(err as Error).message}\n`,
        );
        this.#failPending("malformed JSON-RPC frame");
        continue;
      }
      this.#dispatch(parsed);
    }
  }

  #dispatch(msg: JsonRpcMessage): void {
    if (msg.method === "textDocument/publishDiagnostics" && msg.params !== undefined) {
      this.diagnostics.push(msg.params as PublishDiagnostics);
      return;
    }
    if (msg.method !== undefined && msg.id !== undefined) {
      // Server-to-client request. Reply once; a thrown handler closes
      // over a pending request and would hang the eslint LSP.
      try {
        const result = this.#onServerRequest(msg.method, msg.params);
        this.#write({ jsonrpc: "2.0", id: msg.id, result });
      } catch (err) {
        this.#write({
          jsonrpc: "2.0",
          id: msg.id,
          error: { code: -32603, message: (err as Error).message },
        });
      }
      return;
    }
    if (msg.method !== undefined && msg.id === undefined) {
      if (msg.method === "window/logMessage") {
        const lm = msg.params as { type?: number; message?: string } | undefined;
        process.stderr.write(`[${this.name}] log(${lm?.type ?? "?"}): ${lm?.message ?? ""}\n`);
      }
      return;
    }
    if (msg.id !== undefined) {
      const pending = this.#pending.get(msg.id);
      if (pending !== undefined) {
        this.#pending.delete(msg.id);
        if (msg.error !== undefined) pending.reject(msg.error);
        else pending.resolve(msg.result);
      }
    }
  }
}

function lspPath(): string {
  // Prepend the fixture's `node_modules/.bin` so the syntax launcher's
  // child `vscode-eslint-language-server` resolves to the fixture's
  // own install. The architecture LSP does not depend on PATH.
  const fixtureBin = path.join(FIXTURE_ROOT, "node_modules", ".bin");
  const current = process.env.PATH ?? "";
  return `${fixtureBin}${path.delimiter}${current}`;
}

async function initialize(client: LspClient): Promise<InitializeResult> {
  const result = (await client.request("initialize", {
    processId: process.pid,
    rootUri: FIXTURE_WORKSPACE_URI,
    workspaceFolders: [{ uri: FIXTURE_WORKSPACE_URI, name: "two-lsp-fixture" }],
    capabilities: {
      textDocument: {
        publishDiagnostics: { codeDescriptionSupport: true },
        diagnostic: { dynamicRegistration: false, relatedDocumentSupport: false },
      },
      workspace: {
        workspaceFolders: true,
        configuration: true,
      },
    },
    initializationOptions: {
      // Older vscode-eslint-language-server builds gate flat config
      // behind this flag; newer ones auto-detect.
      experimental: { useFlatConfig: true },
      validate: "on",
    },
  })) as InitializeResult;
  client.notify("initialized", {});
  return result;
}

function supportsPullDiagnostics(capabilities: ServerCapabilities | undefined): boolean {
  return capabilities?.diagnosticProvider !== undefined;
}

async function pullDiagnostics(
  client: LspClient,
  fileUri: string,
): Promise<readonly Diagnostic[]> {
  const report = (await client.request("textDocument/diagnostic", {
    textDocument: { uri: fileUri },
  })) as DocumentDiagnosticReport | null;
  return report?.items ?? [];
}

async function shutdown(client: LspClient): Promise<void> {
  try {
    await client.request("shutdown", null);
    client.notify("exit", null);
  } catch (err) {
    process.stderr.write(
      `[dogfood] ${client.name}: shutdown failed: ${formatJsonRpcError(err)}\n`,
    );
  }
}

function formatJsonRpcError(err: unknown): string {
  if (err instanceof Error) return err.message;
  if (typeof err === "object" && err !== null) {
    const o = err as { code?: number; message?: string };
    return `code=${o.code ?? "?"} message=${o.message ?? "(none)"}`;
  }
  return String(err);
}

async function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function findDiagnostic(
  client: LspClient,
  predicate: (d: Diagnostic) => boolean,
): Diagnostic | null {
  for (const pub of client.diagnostics) {
    for (const d of pub.diagnostics) {
      if (predicate(d)) return d;
    }
  }
  return null;
}

async function waitForRule(
  client: LspClient,
  predicate: (d: Diagnostic) => boolean,
  deadline: number,
): Promise<Diagnostic | null> {
  while (Date.now() < deadline) {
    const hit = findDiagnostic(client, predicate);
    if (hit !== null) return hit;
    await sleep(200);
  }
  return null;
}

function assertPrinciplesUrl(client: string, code: string, href: string | undefined): void {
  assert.ok(
    typeof href === "string" && href.startsWith(PRINCIPLES_URL_PREFIX),
    `${client}: codeDescription.href for ${code} should start with ${PRINCIPLES_URL_PREFIX}; got ${String(href)}`,
  );
}

function reportDiagnostics(client: LspClient): void {
  process.stdout.write(`\n[${client.name}] diagnostics received:\n`);
  for (const pub of client.diagnostics) {
    const rel = path.relative(FIXTURE_ROOT, fileURLToPath(pub.uri));
    process.stdout.write(`  ${rel}: ${pub.diagnostics.length} diagnostic(s)\n`);
    for (const d of pub.diagnostics) {
      process.stdout.write(
        `    code=${String(d.code)} href=${d.codeDescription?.href ?? "(none)"}\n`,
      );
    }
  }
  const stderr = client.stderrTail().trim();
  if (stderr.length > 0) {
    process.stdout.write(`[${client.name}] stderr tail:\n${stderr}\n`);
  }
}

interface EslintWorkspaceConfig {
  readonly validate: "on" | "off";
  readonly packageManager: string;
  readonly useESLintClass: boolean;
  readonly experimental: { readonly useFlatConfig: boolean };
  readonly codeAction: {
    readonly disableRuleComment: { readonly enable: boolean };
    readonly showDocumentation: { readonly enable: boolean };
  };
  readonly codeActionOnSave: { readonly enable: boolean; readonly mode: string };
  readonly format: boolean;
  readonly quiet: boolean;
  readonly onIgnoredFiles: "off" | "warn";
  readonly options: Record<string, unknown>;
  readonly rulesCustomizations: readonly unknown[];
  readonly run: "onType" | "onSave";
  readonly problems: { readonly shortenToSingleLine: boolean };
  readonly nodePath: string | null;
  readonly workingDirectory: { readonly mode: "auto" | "location" };
  readonly workspaceFolder: { readonly uri: string; readonly name: string };
}

function eslintConfigurationItem(): EslintWorkspaceConfig {
  // vscode-eslint's client sends one configuration per scope via
  // `workspace/configuration`. Defaults fill missing fields, but the
  // server still expects a non-null reply per scope.
  return {
    validate: "on",
    packageManager: "pnpm",
    useESLintClass: false,
    experimental: { useFlatConfig: true },
    codeAction: {
      disableRuleComment: { enable: false },
      showDocumentation: { enable: true },
    },
    codeActionOnSave: { enable: false, mode: "all" },
    format: false,
    quiet: false,
    onIgnoredFiles: "off",
    options: {},
    rulesCustomizations: [],
    run: "onType",
    problems: { shortenToSingleLine: false },
    nodePath: null,
    workingDirectory: { mode: "auto" },
    workspaceFolder: {
      uri: FIXTURE_WORKSPACE_URI,
      name: "two-lsp-fixture",
    },
  };
}

function handleServerRequest(method: string, params: unknown): unknown {
  switch (method) {
    case "workspace/configuration": {
      const items = (params as { items?: readonly unknown[] } | undefined)?.items ?? [];
      return items.map(() => eslintConfigurationItem());
    }
    case "workspace/workspaceFolders":
      return [{ uri: FIXTURE_WORKSPACE_URI, name: "two-lsp-fixture" }];
    case "client/registerCapability":
    case "client/unregisterCapability":
      return null;
    default:
      // Unknown server-to-client method; log so a future LSP feature
      // doesn't silently get `null` and quietly skip handshakes.
      process.stderr.write(`[dogfood] unhandled server request: ${method}\n`);
      return null;
  }
}

interface ExercisedServer {
  readonly client: LspClient;
  readonly capabilities: ServerCapabilities | undefined;
  readonly fileUri: string;
}

async function exerciseServer(entry: LspServerEntry): Promise<ExercisedServer> {
  process.stdout.write(`\n==> spawning ${entry.name}\n`);
  const client = new LspClient(entry, handleServerRequest);
  const init = await initialize(client);

  client.notify("textDocument/didOpen", {
    textDocument: {
      uri: FIXTURE_URI,
      languageId: "typescript",
      version: 1,
      text: FIXTURE_TEXT,
    },
  });
  return { client, capabilities: init.capabilities, fileUri: FIXTURE_URI };
}

function pullSignature(items: readonly Diagnostic[]): string {
  return items.map((d) => String(d.code)).sort().join("|");
}

async function collectFromServer(
  server: ExercisedServer,
  ruleCode: string,
  deadline: number,
): Promise<Diagnostic | null> {
  if (!supportsPullDiagnostics(server.capabilities)) {
    return waitForRule(server.client, (d) => d.code === ruleCode, deadline);
  }
  // Pull-mode servers (eslint LSP) never publish; poll until the rule
  // appears or the deadline elapses. Dedupe identical-result pushes so
  // `reportDiagnostics` doesn't echo the same payload every cycle.
  let lastSig = "";
  while (Date.now() < deadline) {
    const items = await pullDiagnostics(server.client, server.fileUri).catch(
      () => [] as readonly Diagnostic[],
    );
    const sig = pullSignature(items);
    if (items.length > 0 && sig !== lastSig) {
      server.client.diagnostics.push({ uri: server.fileUri, diagnostics: items });
      lastSig = sig;
    }
    const hit = items.find((d) => d.code === ruleCode);
    if (hit !== undefined) return hit;
    await sleep(300);
  }
  return null;
}

async function runEslintCli(): Promise<{ exitCode: number; stdout: string; stderr: string }> {
  // Runs the fixture's own eslint binary (installed at `dogfood-fixtures/two-lsp/node_modules/.bin/eslint`)
  // against the violating fixture file. PATH carries the local node_modules/.bin so subprocesses can find it.
  return new Promise((resolve) => {
    const child = spawn("eslint", [FIXTURE_FILE], {
      cwd: FIXTURE_ROOT,
      env: { ...process.env, PATH: lspPath() },
    });
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (b: Buffer) => { stdout += b.toString("utf8"); });
    child.stderr.on("data", (b: Buffer) => { stderr += b.toString("utf8"); });
    child.on("exit", (code) => resolve({ exitCode: code ?? -1, stdout, stderr }));
  });
}

async function main(): Promise<void> {
  assert.ok(fs.existsSync(FIXTURE_FILE), `fixture file not found: ${FIXTURE_FILE}`);

  // 1. Architecture LSP — diagnostic surface that ships behind the proxy.
  const architecture = await exerciseServer(architectureLspEntry());

  // 30 s covers fresh-CI cold-start: ts.Program load can run several seconds on first call.
  const deadline = Date.now() + 30_000;
  const archHit = await collectFromServer(
    architecture,
    "no-cross-domain-sibling-import",
    deadline,
  );

  reportDiagnostics(architecture.client);

  let exitCode = 0;
  try {
    assert.ok(
      archHit !== null,
      "architecture LSP did not publish a no-cross-domain-sibling-import diagnostic within 30s",
    );
    assertPrinciplesUrl(
      "architecture",
      "no-cross-domain-sibling-import",
      archHit.codeDescription?.href,
    );
    process.stdout.write("\n[dogfood] architecture LSP published the expected diagnostic ✓\n");
  } catch (err) {
    process.stderr.write(`\n[dogfood] FAIL (architecture LSP): ${(err as Error).message}\n`);
    exitCode = 1;
  }

  await shutdown(architecture.client);
  const archCode = await architecture.client.awaitExit(5_000);
  if (archCode !== 0) {
    process.stderr.write(
      `[dogfood] architecture LSP did not exit cleanly (code=${String(archCode)})\n`,
    );
    exitCode = 1;
  }
  architecture.client.killHard();

  // 2. ESLint CLI — syntax-floor surface that ships via /safer:verify and
  // any pre-commit/CI integration the project has.
  const eslintResult = await runEslintCli();
  try {
    assert.ok(
      eslintResult.exitCode !== 0,
      `eslint exited 0 on a fixture with a known violation; stdout:\n${eslintResult.stdout}\nstderr:\n${eslintResult.stderr}`,
    );
    assert.ok(
      eslintResult.stdout.includes("agent-code-guard/record-cast"),
      `eslint output missing record-cast rule; stdout:\n${eslintResult.stdout}`,
    );
    process.stdout.write("[dogfood] eslint CLI surfaced agent-code-guard/record-cast ✓\n");
  } catch (err) {
    process.stderr.write(`[dogfood] FAIL (eslint CLI): ${(err as Error).message}\n`);
    exitCode = 1;
  }

  process.exit(exitCode);
}

await main();
