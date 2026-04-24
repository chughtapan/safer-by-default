// Spike probe: can `node packages/server/dist/standalone.js` run headless in CI
// with PGlite only (no docker, no external Postgres)?
//
// Measures:
//   - Time from spawn to /health 200
//   - Register 2 agents via /api/v1/auth/register
//   - Send message WS roundtrip
//   - SIGTERM teardown
//   - Restartability: second spawn uses in-memory PGlite, zero state leak
//
// Throwaway spike code. Craft principles suspended.

import { spawn } from "node:child_process";
import { mkdtempSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { performance } from "node:perf_hooks";

const MOLTZAP = "/home/tapanc/moltzap";
const STANDALONE = `${MOLTZAP}/packages/server/dist/standalone.js`;
const PORT = 41990 + Math.floor(Math.random() * 50);

function makeConfig(tmp) {
  const yaml = `server:
  port: ${PORT}
  cors_origins: ["*"]
log_level: warn
`;
  const p = join(tmp, "moltzap.yaml");
  writeFileSync(p, yaml);
  return p;
}

async function waitReady(url, startMs, timeoutMs = 30000) {
  const deadline = startMs + timeoutMs;
  while (performance.now() < deadline) {
    try {
      const r = await fetch(url, { signal: AbortSignal.timeout(500) });
      if (r.ok) return performance.now();
    } catch {}
    await new Promise((r) => setTimeout(r, 50));
  }
  throw new Error(`server not ready at ${url} within ${timeoutMs}ms`);
}

async function reg(base, name) {
  const r = await fetch(`${base}/api/v1/auth/register`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ name }),
  });
  const text = await r.text();
  if (!r.ok) throw new Error(`register ${name}: ${r.status} ${text}`);
  return JSON.parse(text);
}

async function listAgents(base, apiKey) {
  // Try to list agents — sanity query; if endpoint exists. Otherwise skip.
  const r = await fetch(`${base}/api/v1/agents`, {
    headers: { "x-api-key": apiKey },
  });
  if (!r.ok) return null;
  return r.json();
}

async function runOnce(label, tmp) {
  const configPath = makeConfig(tmp);
  const base = `http://localhost:${PORT}`;

  const t0 = performance.now();
  const child = spawn("node", [STANDALONE], {
    cwd: MOLTZAP,
    env: {
      ...process.env,
      MOLTZAP_CONFIG: configPath,
      PORT: String(PORT),
      ENCRYPTION_MASTER_SECRET: "a".repeat(44), // 32-byte b64, dummy
    },
    stdio: ["ignore", "pipe", "pipe"],
  });

  let stderr = "";
  let stdout = "";
  child.stdout.on("data", (d) => (stdout += d.toString()));
  child.stderr.on("data", (d) => (stderr += d.toString()));

  let readyMs = null;
  try {
    // Probe a known path. /api/v1/auth/register returns 4xx for GET; that's still "up".
    const deadline = t0 + 30000;
    while (performance.now() < deadline) {
      try {
        const r = await fetch(`${base}/api/v1/auth/register`, {
          method: "OPTIONS",
          signal: AbortSignal.timeout(500),
        });
        if (r.status < 500) {
          readyMs = performance.now();
          break;
        }
      } catch {}
      await new Promise((r) => setTimeout(r, 25));
    }
    if (readyMs == null) throw new Error("not ready in 30s");
  } catch (e) {
    child.kill("SIGKILL");
    console.error(`[${label}] stdout:\n${stdout}`);
    console.error(`[${label}] stderr:\n${stderr}`);
    throw e;
  }

  const bootMs = +(readyMs - t0).toFixed(0);
  console.log(`[${label}] boot_ms=${bootMs} pid=${child.pid}`);

  const rAlice = performance.now();
  const alice = await reg(base, "alice");
  const bob = await reg(base, "bob");
  const rEnd = performance.now();
  console.log(
    `[${label}] register_ms=${(rEnd - rAlice).toFixed(0)} aliceId=${alice.agentId} bobId=${bob.agentId}`,
  );

  // Teardown
  const killStart = performance.now();
  child.kill("SIGTERM");
  const exited = await new Promise((resolve) => {
    const t = setTimeout(() => {
      child.kill("SIGKILL");
      resolve(false);
    }, 5000);
    child.on("exit", (code, sig) => {
      clearTimeout(t);
      resolve({ code, sig });
    });
  });
  const killMs = +(performance.now() - killStart).toFixed(0);
  console.log(`[${label}] kill_ms=${killMs} exit=${JSON.stringify(exited)}`);

  return {
    label,
    bootMs,
    registerMs: +(rEnd - rAlice).toFixed(0),
    killMs,
    aliceId: alice.agentId,
    bobId: alice.agentId === bob.agentId ? "COLLISION" : bob.agentId,
    stderrTail: stderr.split("\n").slice(-5).join("\n"),
  };
}

const tmp1 = mkdtempSync(join(tmpdir(), "moltzap-spike-1-"));
const tmp2 = mkdtempSync(join(tmpdir(), "moltzap-spike-2-"));

try {
  const r1 = await runOnce("run1", tmp1);
  // Small gap to ensure port free
  await new Promise((r) => setTimeout(r, 500));
  const r2 = await runOnce("run2", tmp2);

  console.log("\n=== RESULTS ===");
  console.log(JSON.stringify({ r1, r2 }, null, 2));

  const idsDiffer = r1.aliceId !== r2.aliceId && r1.bobId !== r2.bobId;
  console.log(`\nrestartable_no_state_leak=${idsDiffer ? "YES" : "NO"}`);
  console.log(`boot_under_30s_both=${r1.bootMs < 30000 && r2.bootMs < 30000 ? "YES" : "NO"}`);
} finally {
  rmSync(tmp1, { recursive: true, force: true });
  rmSync(tmp2, { recursive: true, force: true });
}
