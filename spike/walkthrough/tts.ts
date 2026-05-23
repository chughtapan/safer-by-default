#!/usr/bin/env bun
import {
  existsSync,
  mkdirSync,
  readFileSync,
  writeFileSync,
} from "node:fs";
import { resolve } from "node:path";
import { spawnSync } from "node:child_process";

const CARTESIA_API_KEY = process.env.CARTESIA_API_KEY;
const CARTESIA_VOICE_ID =
  process.env.CARTESIA_VOICE_ID ?? "a0e99841-438c-4a64-b679-ae501e7d6091"; // Barbershop Man
const CARTESIA_VERSION = "2026-03-01";
const CARTESIA_MODEL = "sonic-2";
const SAMPLE_RATE = 24_000;

if (!CARTESIA_API_KEY) {
  console.error("CARTESIA_API_KEY is not set — export it (see ~/.bashrc)");
  process.exit(1);
}

interface Scene {
  id: number;
  title: string;
  titleCard?: string;
  files: string[];
  show: string;
  narration: string;
}

function parsePlan(md: string): { title: string; scenes: Scene[] } {
  const titleMatch = md.match(/^# Walkthrough:\s*(.+)$/m);
  const title = titleMatch?.[1]?.trim() ?? "Walkthrough";

  // Scene header: ## Scene N — name   (no duration; old format with (Ns) also tolerated)
  const headerRe = /^## Scene (\d+)\s*[—-]\s*(.+?)(?:\s*\([^)]*\))?\s*$/gm;
  const headers = [...md.matchAll(headerRe)];
  const scenes: Scene[] = [];

  for (let i = 0; i < headers.length; i++) {
    const h = headers[i];
    const start = h.index! + h[0].length;
    const end = i + 1 < headers.length ? headers[i + 1].index! : md.length;
    const body = md.slice(start, end);

    const field = (name: string): string | undefined => {
      const re = new RegExp(`^\\s*[-*]\\s*${name}:\\s*(.+)$`, "m");
      const m = body.match(re);
      if (!m) return undefined;
      let v = m[1].trim();
      if (v.startsWith("`") && v.endsWith("`")) v = v.slice(1, -1);
      if (v.startsWith('"') && v.endsWith('"')) v = v.slice(1, -1);
      return v;
    };

    const filesRaw = field("Files") ?? "";
    const files =
      filesRaw === "" || filesRaw.toLowerCase() === "none"
        ? []
        : filesRaw.split(",").map((s) => s.trim()).filter(Boolean);

    scenes.push({
      id: parseInt(h[1], 10),
      title: h[2].trim(),
      titleCard: field("Title card"),
      files,
      show: field("Show") ?? `echo "scene ${h[1]}: ${h[2].trim()}"`,
      narration: field("Narration") ?? "",
    });
  }

  return { title, scenes };
}

async function synthesize(transcript: string, outPath: string): Promise<void> {
  const resp = await fetch("https://api.cartesia.ai/tts/bytes", {
    method: "POST",
    headers: {
      "X-API-Key": CARTESIA_API_KEY!,
      "Cartesia-Version": CARTESIA_VERSION,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model_id: CARTESIA_MODEL,
      transcript,
      voice: { mode: "id", id: CARTESIA_VOICE_ID },
      output_format: {
        container: "wav",
        encoding: "pcm_s16le",
        sample_rate: SAMPLE_RATE,
      },
      language: "en",
    }),
  });

  if (!resp.ok) {
    const body = await resp.text();
    throw new Error(`Cartesia ${resp.status} ${resp.statusText}: ${body}`);
  }
  const bytes = new Uint8Array(await resp.arrayBuffer());
  writeFileSync(outPath, bytes);
}

function durationOfWav(path: string): number {
  const r = spawnSync(
    "ffprobe",
    [
      "-v",
      "error",
      "-show_entries",
      "format=duration",
      "-of",
      "default=noprint_wrappers=1:nokey=1",
      path,
    ],
    { encoding: "utf8" },
  );
  return parseFloat(r.stdout.trim());
}

function makeSilenceWav(durationSec: number, outPath: string): void {
  const r = spawnSync(
    "ffmpeg",
    [
      "-y",
      "-f",
      "lavfi",
      "-i",
      `anullsrc=r=${SAMPLE_RATE}:cl=mono`,
      "-t",
      String(durationSec),
      "-c:a",
      "pcm_s16le",
      outPath,
    ],
    { stdio: ["ignore", "ignore", "pipe"] },
  );
  if (r.status !== 0) {
    throw new Error(`ffmpeg silence failed: ${r.stderr}`);
  }
}

function concatWavs(paths: string[], outPath: string): void {
  const listPath = `/tmp/concat-list-${process.pid}.txt`;
  const abs = paths.map((p) => resolve(p));
  writeFileSync(
    listPath,
    abs.map((p) => `file '${p.replace(/'/g, "'\\''")}'`).join("\n") + "\n",
  );
  const r = spawnSync(
    "ffmpeg",
    [
      "-y",
      "-f",
      "concat",
      "-safe",
      "0",
      "-i",
      listPath,
      "-c",
      "copy",
      outPath,
    ],
    { stdio: ["ignore", "ignore", "pipe"] },
  );
  if (r.status !== 0) {
    throw new Error(`ffmpeg concat failed: ${r.stderr}`);
  }
}

async function main() {
  const args = process.argv.slice(2);

  if (args.includes("--text")) {
    const text = args[args.indexOf("--text") + 1];
    const out = args.includes("--out")
      ? args[args.indexOf("--out") + 1]
      : "/tmp/cartesia-test.wav";
    await synthesize(text, out);
    console.log(`Wrote ${out} (${durationOfWav(out).toFixed(2)}s)`);
    return;
  }

  const planPath = args.find((a) => !a.startsWith("--")) ?? "narrative_plan.md";
  const md = readFileSync(planPath, "utf8");
  const plan = parsePlan(md);

  if (plan.scenes.length === 0) {
    console.error(
      `No scenes found in ${planPath}. Expected '## Scene N — name' headers.`,
    );
    process.exit(1);
  }

  if (!existsSync("audio")) mkdirSync("audio", { recursive: true });

  const sceneDurations: { id: number; title: string; durationSec: number; narration: string }[] = [];
  const finalPaths: string[] = [];

  for (const scene of plan.scenes) {
    if (!scene.narration) {
      console.warn(`Scene ${scene.id} has no Narration; skipping`);
      continue;
    }

    const rawPath = `audio/scene_${scene.id}.wav`;
    const paddedPath = `audio/scene_${scene.id}_padded.wav`;
    const silencePath = `audio/scene_${scene.id}_tail.wav`;

    const wordCount = scene.narration.split(/\s+/).filter(Boolean).length;
    console.log(
      `Scene ${scene.id} (${scene.title}): synthesizing ${wordCount} words`,
    );
    await synthesize(scene.narration, rawPath);

    // Add 0.8s tail silence per scene so the viewer has a beat to register
    // the on-screen state before the next scene cuts in.
    const tailSec = 0.8;
    makeSilenceWav(tailSec, silencePath);
    concatWavs([rawPath, silencePath], paddedPath);

    const dur = durationOfWav(paddedPath);
    console.log(`  → ${dur.toFixed(2)}s (narration + ${tailSec}s tail)`);
    sceneDurations.push({
      id: scene.id,
      title: scene.title,
      durationSec: Math.round(dur * 100) / 100,
      narration: scene.narration,
    });
    finalPaths.push(paddedPath);
  }

  concatWavs(finalPaths, "narration.wav");
  const totalDur = durationOfWav("narration.wav");

  const manifest = {
    title: plan.title,
    totalDurationSec: Math.round(totalDur * 100) / 100,
    scenes: sceneDurations,
    note: "Durations measured from synthesized WAVs (audio-first architecture). scene_planner.ts reads these to size vhs Sleeps so video aligns to audio per scene.",
  };
  writeFileSync("manifest.json", JSON.stringify(manifest, null, 2) + "\n");

  console.log(
    `Wrote narration.wav (${totalDur.toFixed(1)}s across ${finalPaths.length} scenes) + manifest.json`,
  );
}

main().catch((e) => {
  console.error(e?.message ?? e);
  process.exit(1);
});
