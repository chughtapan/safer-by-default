#!/usr/bin/env bun
import { existsSync, readFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { resolve } from "node:path";

interface Manifest {
  title: string;
  totalDurationSec: number;
  scenes: { id: number; title: string; durationSec: number }[];
}

const args = process.argv.slice(2);
const manifestPath = args[0] ?? "manifest.json";
const manifest: Manifest = JSON.parse(readFileSync(manifestPath, "utf8"));

// vhs must run from the repo root so paths like `bat ... spike/walkthrough/...`
// inside the tapes resolve correctly. We capture cwd here, then resolve scene
// tape and output paths against the repo root.
const here = process.cwd(); // expected to be spike/walkthrough/
const repoRoot = resolve(here, "..", "..");

for (const scene of manifest.scenes) {
  const tapeAbs = resolve(here, `segments/scene_${scene.id}.tape`);
  const outputAbs = resolve(here, `segments/scene_${scene.id}.mp4`);

  if (!existsSync(tapeAbs)) {
    throw new Error(`Missing tape for scene ${scene.id}: ${tapeAbs}`);
  }

  console.log(`Scene ${scene.id} (${scene.title}): rendering...`);
  const tStart = Date.now();
  const r = spawnSync(
    "env",
    [
      "-i",
      `PATH=${process.env.PATH ?? ""}`,
      `HOME=${process.env.HOME ?? ""}`,
      "TERM=xterm-256color",
      "vhs",
      tapeAbs,
    ],
    { cwd: repoRoot, stdio: ["ignore", "ignore", "pipe"] },
  );
  if (r.status !== 0) {
    const err = r.stderr ? new TextDecoder().decode(r.stderr) : "";
    throw new Error(`vhs failed for scene ${scene.id}:\n${err}`);
  }

  if (!existsSync(outputAbs)) {
    throw new Error(
      `vhs reported success but ${outputAbs} not found (check tape Output directive)`,
    );
  }

  // Probe actual rendered duration
  const probe = spawnSync(
    "ffprobe",
    [
      "-v",
      "error",
      "-show_entries",
      "format=duration",
      "-of",
      "default=noprint_wrappers=1:nokey=1",
      outputAbs,
    ],
    { encoding: "utf8" },
  );
  const actualSec = parseFloat(probe.stdout.trim());
  const elapsedSec = (Date.now() - tStart) / 1000;
  console.log(
    `  → segments/scene_${scene.id}.mp4 = ${actualSec.toFixed(2)}s (audio target ${scene.durationSec}s) [${elapsedSec.toFixed(1)}s wall]`,
  );
}

console.log(`Rendered ${manifest.scenes.length} segments.`);
