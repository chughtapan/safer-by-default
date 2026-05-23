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
  process.env.CARTESIA_VOICE_ID ?? "a0e99841-438c-4a64-b679-ae501e7d6091"; // Barbershop Man (Cartesia public voice)
const CARTESIA_VERSION = "2026-03-01";
const CARTESIA_MODEL = "sonic-2";
const SAMPLE_RATE = 24_000;

if (!CARTESIA_API_KEY) {
  console.error("CARTESIA_API_KEY is not set — export it (see ~/.bashrc)");
  process.exit(1);
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

interface SceneAudio {
  id: number;
  text: string;
}

function parseSsml(ssml: string): SceneAudio[] {
  const re = /<!--\s*scene:\s*(\d+)\s*-->\s*([\s\S]*?)(?=<!--\s*scene:|$)/g;
  const out: SceneAudio[] = [];
  let m: RegExpExecArray | null;
  while ((m = re.exec(ssml)) !== null) {
    out.push({ id: parseInt(m[1], 10), text: m[2].trim() });
  }
  return out;
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

  if (args.length < 2) {
    console.error("Usage: bun tts.ts <transcript.ssml> <manifest.json>");
    console.error("       bun tts.ts --text 'hello world' --out /tmp/hi.wav");
    process.exit(2);
  }

  const [ssmlPath, manifestPath] = args;
  const ssml = readFileSync(ssmlPath, "utf8");
  const manifest = JSON.parse(readFileSync(manifestPath, "utf8"));
  const scenes = parseSsml(ssml);

  if (scenes.length === 0) {
    console.error(
      `No scenes found in ${ssmlPath}. Expected <!-- scene: N --> markers.`,
    );
    process.exit(1);
  }

  if (!existsSync("audio")) mkdirSync("audio", { recursive: true });

  const sceneDuration = new Map<number, number>(
    manifest.scenes.map((s: { id: number; durationSec: number }) => [
      s.id,
      s.durationSec,
    ]),
  );

  const finalPaths: string[] = [];
  for (const scene of scenes) {
    const target = sceneDuration.get(scene.id);
    if (target === undefined) {
      console.warn(
        `Scene ${scene.id} has no manifest entry; skipping`,
      );
      continue;
    }

    const rawPath = `audio/scene_${scene.id}_raw.wav`;
    const padPath = `audio/scene_${scene.id}_pad.wav`;
    const outPath = `audio/scene_${scene.id}.wav`;

    const wordCount = scene.text.split(/\s+/).filter(Boolean).length;
    console.log(
      `Scene ${scene.id}: synthesizing (~${wordCount} words, target ${target}s)`,
    );
    await synthesize(scene.text, rawPath);

    let actual = durationOfWav(rawPath);
    let fitPath = rawPath;
    if (actual > target + 0.5) {
      const tempo = actual / target;
      const clamped = Math.min(2.0, tempo);
      console.warn(
        `  ⚠ scene ${scene.id} narration ${actual.toFixed(1)}s > target ${target}s — compressing with atempo=${clamped.toFixed(2)}`,
      );
      const fittedPath = `audio/scene_${scene.id}_fitted.wav`;
      const r = spawnSync(
        "ffmpeg",
        [
          "-y",
          "-i",
          rawPath,
          "-af",
          `atempo=${clamped.toFixed(3)}`,
          "-c:a",
          "pcm_s16le",
          "-ar",
          String(SAMPLE_RATE),
          fittedPath,
        ],
        { stdio: ["ignore", "ignore", "pipe"] },
      );
      if (r.status !== 0) {
        throw new Error(`ffmpeg atempo failed: ${r.stderr}`);
      }
      fitPath = fittedPath;
      actual = durationOfWav(fitPath);
    }
    const padDur = Math.max(0.05, target - actual);
    makeSilenceWav(padDur, padPath);
    concatWavs([fitPath, padPath], outPath);

    finalPaths.push(outPath);
  }

  concatWavs(finalPaths, "narration.wav");
  console.log(
    `Wrote narration.wav (${durationOfWav("narration.wav").toFixed(1)}s across ${finalPaths.length} scenes)`,
  );
}

main().catch((e) => {
  console.error(e?.message ?? e);
  process.exit(1);
});
