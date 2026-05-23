#!/usr/bin/env bun
import { existsSync, readFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { resolve } from "node:path";

interface Manifest {
  title: string;
  totalDurationSec: number;
  scenes: { id: number; title: string; durationSec: number }[];
}

const XFADE_DURATION = 0.4;
const FOOTER_HEIGHT_PX = 36;
const PR_NUMBER = process.env.PR_NUMBER ?? "?";
const BRANCH =
  process.env.BRANCH ??
  (() => {
    const r = spawnSync("git", ["branch", "--show-current"], {
      encoding: "utf8",
    });
    return r.stdout.trim() || "?";
  })();

const args = process.argv.slice(2);
const manifestPath = args[0] ?? "manifest.json";
const audioPath = args[1] ?? "narration.wav";
const outputPath = args[2] ?? "final.mp4";

const manifest: Manifest = JSON.parse(readFileSync(manifestPath, "utf8"));

function videoDuration(path: string): number {
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

function run(cmd: string[], label: string): void {
  const r = spawnSync(cmd[0], cmd.slice(1), {
    stdio: ["ignore", "pipe", "pipe"],
  });
  if (r.status !== 0) {
    const err = r.stderr ? new TextDecoder().decode(r.stderr).split("\n").slice(-15).join("\n") : "";
    throw new Error(`${label} failed:\n${err}`);
  }
}

// Pass 1: pad each segment to (max(video, audio) + xfade_window) at constant 30fps.
// Doing this as a per-segment ffmpeg run sidesteps the variable-frame-rate
// errors that tpad inside a complex xfade graph triggers.
console.log("Pass 1: per-scene pad to audio length + xfade window");
const paddedSegments: { id: number; path: string; lengthSec: number }[] = [];
for (let i = 0; i < manifest.scenes.length; i++) {
  const s = manifest.scenes[i];
  const segPath = resolve(`segments/scene_${s.id}.mp4`);
  if (!existsSync(segPath)) {
    throw new Error(`Missing segment ${segPath}`);
  }
  const videoSec = videoDuration(segPath);
  const isLast = i === manifest.scenes.length - 1;
  const target = Math.max(videoSec, s.durationSec) + (isLast ? 0 : XFADE_DURATION);
  const padDur = target - videoSec;
  const paddedPath = resolve(`segments/scene_${s.id}_padded.mp4`);

  console.log(
    `  scene ${s.id}: video=${videoSec.toFixed(2)}s audio=${s.durationSec.toFixed(2)}s → pad +${padDur.toFixed(2)}s → target ${target.toFixed(2)}s`,
  );

  run(
    [
      "ffmpeg",
      "-y",
      "-i",
      segPath,
      "-vf",
      `tpad=stop_mode=clone:stop_duration=${padDur.toFixed(3)},fps=30,setpts=PTS-STARTPTS`,
      "-an",
      "-c:v",
      "libx264",
      "-preset",
      "fast",
      "-pix_fmt",
      "yuv420p",
      "-r",
      "30",
      "-fps_mode",
      "cfr",
      paddedPath,
    ],
    `pad scene ${s.id}`,
  );
  paddedSegments.push({ id: s.id, path: paddedPath, lengthSec: target });
}

// Pass 2: xfade chain across padded segments
console.log("\nPass 2: xfade chain + drawtext footer + audio mux");

const inputs: string[] = [];
for (const s of paddedSegments) inputs.push("-i", s.path);
inputs.push("-i", audioPath);

const filters: string[] = [];
let prevLabel = "0:v";
let cumulativeOffset = 0;

for (let i = 1; i < paddedSegments.length; i++) {
  cumulativeOffset += paddedSegments[i - 1].lengthSec - XFADE_DURATION;
  const outLabel = i === paddedSegments.length - 1 ? "vstitched" : `vx${i}`;
  filters.push(
    `[${prevLabel}][${i}:v]xfade=transition=fade:duration=${XFADE_DURATION}:offset=${cumulativeOffset.toFixed(3)}[${outLabel}]`,
  );
  prevLabel = outLabel;
}

if (paddedSegments.length === 1) {
  filters.push(`[0:v]copy[vstitched]`);
}

// Footer overlay
const footerText = `PR #${PR_NUMBER}  •  ${BRANCH}  •  spike/walkthrough`;
const footerEscaped = footerText
  .replace(/\\/g, "\\\\")
  .replace(/:/g, "\\:")
  .replace(/'/g, "\\'");
filters.push(
  `[vstitched]drawtext=text='${footerEscaped}':fontsize=20:fontcolor=white@0.8:x=(w-text_w)/2:y=h-${FOOTER_HEIGHT_PX}:box=1:boxcolor=black@0.6:boxborderw=10[vout]`,
);

const audioInputIndex = paddedSegments.length;
const cmd = [
  "ffmpeg",
  "-y",
  ...inputs,
  "-filter_complex",
  filters.join(";"),
  "-map",
  "[vout]",
  "-map",
  `${audioInputIndex}:a`,
  "-c:v",
  "libx264",
  "-preset",
  "fast",
  "-pix_fmt",
  "yuv420p",
  "-c:a",
  "aac",
  "-b:a",
  "128k",
  "-shortest",
  outputPath,
];

console.log("\nfilter graph:");
console.log(filters.join(";\n"));
console.log("");

const r = spawnSync(cmd[0], cmd.slice(1), {
  stdio: ["ignore", "pipe", "inherit"],
});
if (r.status !== 0) {
  console.error("\nfinal composite failed");
  process.exit(1);
}

const finalDur = videoDuration(outputPath);
console.log(`\nWrote ${outputPath} (${finalDur.toFixed(2)}s)`);
