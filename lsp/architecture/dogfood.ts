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
 * Effect-native, mirroring `server/index.ts`: child-process and stdio
 * stay imperative at the edge, every async path is an Effect (JSON-RPC
 * request/response via `Effect.async` over a pending-resume map), failures
 * travel a typed `JsonRpcFailure`/`HarnessError` channel instead of raw
 * throws, and orchestration runs through `Effect.gen`.
 *
 * Run: `pnpm dogfood` from `lsp/architecture/`. Exits non-zero on failure.
 */

import { type ChildProcessWithoutNullStreams, spawn } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { Data, Effect } from "effect";

const STDERR_TAIL_BYTES = 4_000;
const HEADER_SEPARATOR = "\r\n\r\n";
const JSONRPC_INTERNAL_ERROR = -32_603;
const LSP_PROCESS_EXITED_CODE = -32_099;
const SHUTDOWN_GRACE_MS = 1_000;
const PUSH_POLL_INTERVAL_MS = 200;
const PULL_POLL_INTERVAL_MS = 300;
const DIAGNOSTIC_DEADLINE_MS = 30_000;
const SHUTDOWN_TIMEOUT_MS = 5_000;
const DECIMAL_RADIX = 10;
const DID_OPEN_VERSION = 1;
const NO_EXIT_CODE = -1;

const PRINCIPLES_URL_PREFIX =
  "https://github.com/chughtapan/safer-by-default/blob/main/PRINCIPLES.md";

/** A JSON-RPC response carrying an error, or a child process that exited mid-request. */
class JsonRpcFailure extends Data.TaggedError("JsonRpcFailure")<{
  readonly code: number;
  readonly message: string;
}> {}

/** A failed harness assertion (the dogfood's own checks). */
class HarnessError extends Data.TaggedError("HarnessError")<{
  readonly message: string;
}> {}

const out = (text: string): Effect.Effect<void> =>
  Effect.sync(() => {
    process.stdout.write(text);
  });

const err = (text: string): Effect.Effect<void> =>
  Effect.sync(() => {
    process.stderr.write(text);
  });

const expect = (condition: boolean, message: string): Effect.Effect<void, HarnessError> =>
  condition ? Effect.void : Effect.fail(new HarnessError({ message }));

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
  // eslint-disable-next-line agent-code-guard/no-raw-throw-new-error -- module-init invariant: the harness cannot run outside the plugin tree, and this resolves at load time before any Effect context exists.
  throw new Error(`plugin root (containing .claude-plugin/plugin.json) not found above ${start}`);
}
const PLUGIN_ROOT = findPluginRoot(SCRIPT_DIR);
const FIXTURE_ROOT = path.join(PLUGIN_ROOT, "lsp", "architecture", "dogfood-fixtures", "two-lsp");
const FIXTURE_FILE = path.join(FIXTURE_ROOT, "src", "auth", "client.ts");
const FIXTURE_TEXT = fs.readFileSync(FIXTURE_FILE, "utf8");
const FIXTURE_URI = pathToFileURL(FIXTURE_FILE).toString();
const FIXTURE_WORKSPACE_URI = pathToFileURL(FIXTURE_ROOT).toString();

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

interface JsonRpcMessage {
  readonly jsonrpc?: "2.0";
  readonly id?: number | string;
  readonly method?: string;
  readonly params?: unknown;
  readonly result?: unknown;
  readonly error?: { code: number; message: string };
}

type ServerRequestHandler = (method: string, params: unknown) => unknown;

/** A pending request's resume callback: a JSON-RPC response resolves it. */
type ResumeResponse = (response: Effect.Effect<unknown, JsonRpcFailure>) => void;

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

function lspPath(): string {
  // Prepend the fixture's `node_modules/.bin` so the syntax launcher's
  // child `vscode-eslint-language-server` resolves to the fixture's
  // own install. The architecture LSP does not depend on PATH.
  const fixtureBin = path.join(FIXTURE_ROOT, "node_modules", ".bin");
  // eslint-disable-next-line agent-code-guard/no-process-env-at-runtime -- reading PATH to prepend the fixture's local bin for spawned children; this is subprocess plumbing, not application config.
  const current = process.env.PATH ?? "";
  return `${fixtureBin}${path.delimiter}${current}`;
}

class LspClient {
  readonly name: string;
  readonly diagnostics: PublishDiagnostics[] = [];
  readonly #proc: ChildProcessWithoutNullStreams;
  readonly #pending = new Map<number | string, ResumeResponse>();
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
      // eslint-disable-next-line agent-code-guard/no-process-env-at-runtime -- forwarding the parent environment to the spawned LSP child (PATH gets the fixture's node_modules/.bin prepended); subprocess plumbing, not application config.
      env: { ...process.env, PATH: lspPath() },
    });
    this.#proc.stdout.on("data", (chunk: Buffer) => {
      this.#handleChunk(chunk);
    });
    this.#proc.stderr.on("data", (chunk: Buffer) => {
      const text = chunk.toString("utf8");
      this.#stderrTail = (this.#stderrTail + text).slice(-STDERR_TAIL_BYTES);
    });
    this.#proc.on("exit", () => {
      this.#failPending("LSP process exited");
    });
  }

  #failPending(reason: string): void {
    for (const resume of this.#pending.values()) {
      resume(Effect.fail(new JsonRpcFailure({ code: LSP_PROCESS_EXITED_CODE, message: reason })));
    }
    this.#pending.clear();
  }

  request(method: string, params: unknown): Effect.Effect<unknown, JsonRpcFailure> {
    return Effect.async<unknown, JsonRpcFailure>((resume) => {
      const id = this.#nextId++;
      this.#pending.set(id, resume);
      this.#write({ jsonrpc: "2.0", id, method, params });
    });
  }

  notify(method: string, params: unknown): Effect.Effect<void> {
    return Effect.sync(() => {
      this.#write({ jsonrpc: "2.0", method, params });
    });
  }

  stderrTail(): string {
    return this.#stderrTail;
  }

  awaitExit(timeoutMs: number): Effect.Effect<number | null> {
    return Effect.async<number | null>((resume) => {
      // SIGTERM first to give the LSP a chance to flush; if it lingers
      // past `timeoutMs`, SIGKILL it. Orphaned eslint-server children
      // spawned by `launch.js` get cleaned by the kernel once their
      // parent dies, but SIGKILL skips finalizers we may have queued.
      const termTimer = setTimeout(() => this.#proc.kill("SIGTERM"), timeoutMs);
      const killTimer = setTimeout(() => {
        this.#proc.kill("SIGKILL");
        resume(Effect.succeed(null));
      }, timeoutMs + SHUTDOWN_GRACE_MS);
      this.#proc.on("exit", (code) => {
        clearTimeout(termTimer);
        clearTimeout(killTimer);
        resume(Effect.succeed(code));
      });
    });
  }

  killHard(): void {
    if (this.#proc.exitCode === null) this.#proc.kill("SIGKILL");
  }

  #write(message: JsonRpcMessage): void {
    const body = JSON.stringify(message);
    const header = `Content-Length: ${Buffer.byteLength(body, "utf8")}${HEADER_SEPARATOR}`;
    this.#proc.stdin.write(header + body);
  }

  #handleChunk(chunk: Buffer): void {
    this.#buffer = Buffer.concat([this.#buffer, chunk]);
    while (true) {
      const headerEnd = this.#buffer.indexOf(HEADER_SEPARATOR);
      if (headerEnd < 0) return;
      const header = this.#buffer.subarray(0, headerEnd).toString("utf8");
      const match = /Content-Length: (\d+)/.exec(header);
      if (match === null || match[1] === undefined) {
        // A malformed frame in a 'data' handler must not crash the
        // process; fail every in-flight request so main() exits
        // non-zero gracefully instead of throwing into an event loop.
        process.stderr.write(
          `[${this.name}] malformed LSP frame; missing Content-Length: ${header}\n`,
        );
        this.#failPending("malformed LSP frame (missing Content-Length)");
        this.#buffer = Buffer.alloc(0);
        return;
      }
      const length = Number.parseInt(match[1], DECIMAL_RADIX);
      const bodyStart = headerEnd + HEADER_SEPARATOR.length;
      if (this.#buffer.length < bodyStart + length) return;
      const body = this.#buffer.subarray(bodyStart, bodyStart + length).toString("utf8");
      this.#buffer = this.#buffer.subarray(bodyStart + length);
      let parsed: JsonRpcMessage;
      try {
        parsed = JSON.parse(body) as JsonRpcMessage;
      } catch (parseError) {
        process.stderr.write(
          `[${this.name}] malformed JSON-RPC body: ${(parseError as Error).message}\n`,
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
      this.#replyToServerRequest(msg.id, msg.method, msg.params);
      return;
    }
    if (msg.method !== undefined && msg.id === undefined) {
      this.#logNotification(msg.method, msg.params);
      return;
    }
    if (msg.id !== undefined) {
      this.#resolveResponse(msg.id, msg.error, msg.result);
    }
  }

  // Server-to-client request. Reply once; a thrown handler closes over a
  // pending request and would hang the eslint LSP, so failures reply with
  // a JSON-RPC error frame rather than escaping the handler.
  #replyToServerRequest(id: number | string, method: string, params: unknown): void {
    try {
      const result = this.#onServerRequest(method, params);
      this.#write({ jsonrpc: "2.0", id, result });
    } catch (handlerError) {
      this.#write({
        jsonrpc: "2.0",
        id,
        error: { code: JSONRPC_INTERNAL_ERROR, message: (handlerError as Error).message },
      });
    }
  }

  #logNotification(method: string, params: unknown): void {
    if (method === "window/logMessage") {
      const lm = params as { type?: number; message?: string } | undefined;
      process.stderr.write(`[${this.name}] log(${lm?.type ?? "?"}): ${lm?.message ?? ""}\n`);
    }
  }

  #resolveResponse(
    id: number | string,
    error: { code: number; message: string } | undefined,
    result: unknown,
  ): void {
    const resume = this.#pending.get(id);
    if (resume === undefined) return;
    this.#pending.delete(id);
    if (error !== undefined) {
      resume(Effect.fail(new JsonRpcFailure({ code: error.code, message: error.message })));
    } else {
      resume(Effect.succeed(result));
    }
  }
}

function initialize(client: LspClient): Effect.Effect<InitializeResult, JsonRpcFailure> {
  return Effect.gen(function* () {
    const result = (yield* client.request("initialize", {
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
    yield* client.notify("initialized", {});
    return result;
  });
}

function supportsPullDiagnostics(capabilities: ServerCapabilities | undefined): boolean {
  return capabilities?.diagnosticProvider !== undefined;
}

function pullDiagnostics(
  client: LspClient,
  fileUri: string,
): Effect.Effect<readonly Diagnostic[], JsonRpcFailure> {
  return Effect.gen(function* () {
    const report = (yield* client.request("textDocument/diagnostic", {
      textDocument: { uri: fileUri },
    })) as DocumentDiagnosticReport | null;
    return report?.items ?? [];
  });
}

function shutdown(client: LspClient): Effect.Effect<void> {
  return client.request("shutdown", null).pipe(
    Effect.zipRight(client.notify("exit", null)),
    Effect.catchAll((failure) =>
      err(`[dogfood] ${client.name}: shutdown failed: ${failure.message}\n`),
    ),
  );
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

function waitForRule(
  client: LspClient,
  predicate: (d: Diagnostic) => boolean,
  deadline: number,
): Effect.Effect<Diagnostic | null> {
  return Effect.gen(function* () {
    if (Date.now() >= deadline) return null;
    const hit = findDiagnostic(client, predicate);
    if (hit !== null) return hit;
    yield* Effect.sleep(`${PUSH_POLL_INTERVAL_MS} millis`);
    return yield* waitForRule(client, predicate, deadline);
  });
}

function reportDiagnostics(client: LspClient): Effect.Effect<void> {
  return Effect.sync(() => {
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
  });
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

function exerciseServer(entry: LspServerEntry): Effect.Effect<ExercisedServer, JsonRpcFailure> {
  return Effect.gen(function* () {
    yield* out(`\n==> spawning ${entry.name}\n`);
    const client = yield* Effect.sync(() => new LspClient(entry, handleServerRequest));
    const init = yield* initialize(client);
    yield* client.notify("textDocument/didOpen", {
      textDocument: {
        uri: FIXTURE_URI,
        languageId: "typescript",
        version: DID_OPEN_VERSION,
        text: FIXTURE_TEXT,
      },
    });
    return { client, capabilities: init.capabilities, fileUri: FIXTURE_URI };
  });
}

function pullSignature(items: readonly Diagnostic[]): string {
  return items
    .map((d) => String(d.code))
    .sort()
    .join("|");
}

// Pull-mode servers (eslint LSP) never publish; poll until the rule
// appears or the deadline elapses. Dedupe identical-result pushes so
// `reportDiagnostics` doesn't echo the same payload every cycle.
function pollPull(
  server: ExercisedServer,
  ruleCode: string,
  deadline: number,
  lastSig: string,
): Effect.Effect<Diagnostic | null> {
  return Effect.gen(function* () {
    if (Date.now() >= deadline) return null;
    const items = yield* pullDiagnostics(server.client, server.fileUri).pipe(
      Effect.orElseSucceed(() => [] as readonly Diagnostic[]),
    );
    let sig = lastSig;
    if (items.length > 0) {
      const nextSig = pullSignature(items);
      if (nextSig !== lastSig) {
        server.client.diagnostics.push({ uri: server.fileUri, diagnostics: items });
        sig = nextSig;
      }
    }
    const hit = items.find((d) => d.code === ruleCode);
    if (hit !== undefined) return hit;
    yield* Effect.sleep(`${PULL_POLL_INTERVAL_MS} millis`);
    return yield* pollPull(server, ruleCode, deadline, sig);
  });
}

function collectFromServer(
  server: ExercisedServer,
  ruleCode: string,
  deadline: number,
): Effect.Effect<Diagnostic | null> {
  if (!supportsPullDiagnostics(server.capabilities)) {
    return waitForRule(server.client, (d) => d.code === ruleCode, deadline);
  }
  return pollPull(server, ruleCode, deadline, "");
}

interface EslintRun {
  readonly exitCode: number;
  readonly stdout: string;
  readonly stderr: string;
}

function runEslintCli(): Effect.Effect<EslintRun> {
  // Runs the fixture's own eslint binary (installed at
  // `dogfood-fixtures/two-lsp/node_modules/.bin/eslint`) against the
  // violating fixture file. PATH carries the local node_modules/.bin so
  // subprocesses can find it.
  return Effect.async<EslintRun>((resume) => {
    // Spawn the fixture's own eslint by absolute path rather than a PATH
    // lookup, so the command resolves to a fixed, in-tree executable.
    const eslintBin = path.join(FIXTURE_ROOT, "node_modules", ".bin", "eslint");
    const child = spawn(eslintBin, [FIXTURE_FILE], {
      cwd: FIXTURE_ROOT,
      // eslint-disable-next-line agent-code-guard/no-process-env-at-runtime -- forwarding the parent environment to the spawned eslint child (PATH gets the fixture's node_modules/.bin prepended); subprocess plumbing, not application config.
      env: { ...process.env, PATH: lspPath() },
    });
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (b: Buffer) => {
      stdout += b.toString("utf8");
    });
    child.stderr.on("data", (b: Buffer) => {
      stderr += b.toString("utf8");
    });
    child.on("exit", (code) => resume(Effect.succeed({ exitCode: code ?? NO_EXIT_CODE, stdout, stderr })));
  });
}

const main: Effect.Effect<number, HarnessError | JsonRpcFailure> = Effect.gen(function* () {
  yield* expect(fs.existsSync(FIXTURE_FILE), `fixture file not found: ${FIXTURE_FILE}`);

  // 1. Architecture LSP — diagnostic surface that ships behind the proxy.
  const architecture = yield* exerciseServer(architectureLspEntry());

  // 30 s covers fresh-CI cold-start: ts.Program load can run several seconds on first call.
  const deadline = Date.now() + DIAGNOSTIC_DEADLINE_MS;
  const archHit = yield* collectFromServer(
    architecture,
    "no-cross-domain-sibling-import",
    deadline,
  );

  yield* reportDiagnostics(architecture.client);

  let exitCode = 0;
  yield* Effect.gen(function* () {
    yield* expect(
      archHit !== null,
      "architecture LSP did not publish a no-cross-domain-sibling-import diagnostic within 30s",
    );
    const href = archHit?.codeDescription?.href ?? "";
    yield* expect(
      href.startsWith(PRINCIPLES_URL_PREFIX),
      `architecture: codeDescription.href for no-cross-domain-sibling-import should start with ${PRINCIPLES_URL_PREFIX}; got ${href || "(none)"}`,
    );
    yield* out("\n[dogfood] architecture LSP published the expected diagnostic ✓\n");
  }).pipe(
    Effect.catchAll((failure) =>
      err(`\n[dogfood] FAIL (architecture LSP): ${failure.message}\n`).pipe(
        Effect.zipRight(
          Effect.sync(() => {
            exitCode = 1;
          }),
        ),
      ),
    ),
  );

  yield* shutdown(architecture.client);
  const archCode = yield* architecture.client.awaitExit(SHUTDOWN_TIMEOUT_MS);
  if (archCode !== 0) {
    yield* err(`[dogfood] architecture LSP did not exit cleanly (code=${String(archCode)})\n`);
    exitCode = 1;
  }
  yield* Effect.sync(() => architecture.client.killHard());

  // 2. ESLint CLI — syntax-floor surface that ships via /safer:verify and
  // any pre-commit/CI integration the project has.
  const eslintResult = yield* runEslintCli();
  yield* Effect.gen(function* () {
    yield* expect(
      eslintResult.exitCode !== 0,
      `eslint exited 0 on a fixture with a known violation; stdout:\n${eslintResult.stdout}\nstderr:\n${eslintResult.stderr}`,
    );
    yield* expect(
      eslintResult.stdout.includes("agent-code-guard/record-cast"),
      `eslint output missing record-cast rule; stdout:\n${eslintResult.stdout}`,
    );
    yield* out("[dogfood] eslint CLI surfaced agent-code-guard/record-cast ✓\n");
  }).pipe(
    Effect.catchAll((failure) =>
      err(`[dogfood] FAIL (eslint CLI): ${failure.message}\n`).pipe(
        Effect.zipRight(
          Effect.sync(() => {
            exitCode = 1;
          }),
        ),
      ),
    ),
  );

  return exitCode;
});

const program = main.pipe(
  Effect.tap((code) => Effect.sync(() => process.exit(code))),
  Effect.catchAll((failure) =>
    err(`[dogfood] fatal: ${failure.message}\n`).pipe(
      Effect.zipRight(Effect.sync(() => process.exit(1))),
    ),
  ),
);
Effect.runPromise(program);
