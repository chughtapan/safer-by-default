// In-process probe: bypass test-utils/index.js (which pulls vitest via rpc-error).
// Replicates startCoreTestServer() inline to measure same-process boot + restart.

import { readFileSync, existsSync } from "node:fs";
import { join, dirname } from "node:path";
import { pathToFileURL } from "node:url";
import { performance } from "node:perf_hooks";

const MOLTZAP = "/home/tapanc/moltzap";
const SERVER_DIST = `${MOLTZAP}/packages/server/dist`;

process.chdir(MOLTZAP);

const { createCoreApp } = await import(pathToFileURL(`${SERVER_DIST}/app/server.js`).href);
const { makeEffectKysely } = await import(pathToFileURL(`${SERVER_DIST}/db/effect-kysely-toolkit.js`).href);

async function boot() {
  const t0 = performance.now();
  const { KyselyPGlite } = await import("/home/tapanc/moltzap/node_modules/.pnpm/kysely-pglite@0.6.1_@electric-sql+pglite@0.4.4_kysely@0.28.16_pg@8.20.0/node_modules/kysely-pglite/dist/index.js");
  const kpg = await KyselyPGlite.create(); // in-memory
  const appDb = makeEffectKysely({ dialect: kpg.dialect });
  const schemaPath = join(SERVER_DIST, "app", "core-schema.sql");
  const srcSchema = `${MOLTZAP}/packages/server/src/app/core-schema.sql`;
  const usePath = existsSync(schemaPath) ? schemaPath : srcSchema;
  const schema = readFileSync(usePath, "utf-8");
  await kpg.client.exec(schema);

  const coreApp = createCoreApp({
    db: appDb,
    dbCleanup: async () => { await appDb.destroy(); },
    port: 0,
    corsOrigins: ["*"],
    devMode: true,
  });
  await new Promise((r) => setTimeout(r, 200));
  const base = `http://localhost:${coreApp.port}`;
  const bootMs = performance.now() - t0;
  return { coreApp, appDb, client: kpg.client, base, bootMs };
}

async function reg(base, name) {
  const r = await fetch(`${base}/api/v1/auth/register`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ name }),
  });
  if (!r.ok) throw new Error(`register ${name}: ${r.status} ${await r.text()}`);
  return r.json();
}

async function runOnce(label) {
  const srv = await boot();
  const tReg = performance.now();
  const alice = await reg(srv.base, "alice");
  const bob = await reg(srv.base, "bob");
  const regMs = performance.now() - tReg;

  // Count agents directly in db
  const rows = await srv.appDb.selectFrom("agents").selectAll().execute();

  const tStop = performance.now();
  await srv.coreApp.close();
  try { await srv.client.close(); } catch {}
  const stopMs = performance.now() - tStop;

  return {
    label,
    bootMs: +srv.bootMs.toFixed(0),
    regMs: +regMs.toFixed(0),
    stopMs: +stopMs.toFixed(0),
    agents: rows.length,
    aliceId: alice.agentId,
    bobId: bob.agentId,
  };
}

// Run twice in the SAME process; confirm isolation.
const r1 = await runOnce("run1");
const r2 = await runOnce("run2");

console.log(JSON.stringify({ r1, r2 }, null, 2));
console.log(
  `\nisolation=${r1.aliceId !== r2.aliceId && r1.bobId !== r2.bobId ? "YES" : "NO"}`,
);
console.log(`agent_count_each_run=${r1.agents},${r2.agents} (expected 2,2)`);
