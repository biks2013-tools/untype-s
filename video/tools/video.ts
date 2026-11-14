// Build tool of the untype demo video.
//
//   node tools/video.ts sheets                         narration sheets + subtitles for every language and profile
//   node tools/video.ts render --lang en [--timing neutral] [--fps 30] [--from 0 --to 10]
//   node tools/video.ts scratch-voice --lang el        placeholder narration with the system voice (narration/<lang>-scratch)
//   node tools/video.ts fit --lang el [--voice narration/el]   fit beat durations to narration clips -> src/timing.<lang>.js
//   node tools/video.ts fit --neutral                  the longer of the fitted el / en durations -> src/timing.neutral.js
//   node tools/video.ts mux --lang el [--voice narration/el]   lay the clips over the rendered video
//
// Narration clips: one file per beat, <voice dir>/<beat id>.(wav|mp3|m4a|aiff).
import { execFileSync, spawn } from "node:child_process";
import { existsSync, mkdirSync, readdirSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

type Beat = { id: string; scene: string; min: number };
type Timed = Beat & { t0: number; dur: number };
type Video = {
  beats: Beat[];
  narration: Record<string, Record<string, string>>;
  timing: Record<string, Record<string, number>>;
  fps: number; width: number; height: number;
};

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const out = join(root, "out");
/** Silence before the voice starts in a beat, and after it ends. */
const LEAD = 0.35;
const TAIL = 0.55;
const CLIP_TYPES = ["wav", "mp3", "m4a", "aiff"];
const SCRATCH_VOICES: Record<string, string> = { el: "Melina", en: "Samantha" };

function arg(name: string): string | undefined {
  const i = process.argv.indexOf(`--${name}`);
  return i >= 0 ? process.argv[i + 1] : undefined;
}
function flag(name: string): boolean {
  return process.argv.includes(`--${name}`);
}
function requireArg(name: string): string {
  const value = arg(name);
  if (!value) {
    throw new Error(`--${name} is required.`);
  }
  return value;
}

async function load(): Promise<Video> {
  const g = globalThis as { UNTYPE_VIDEO?: Video };
  delete g.UNTYPE_VIDEO;
  const bust = `?v=${Date.now()}`;
  await import(pathToFileURL(join(root, "src/timeline.js")).href + bust);
  for (const profile of ["el", "en", "neutral"]) {
    await import(pathToFileURL(join(root, `src/timing.${profile}.js`)).href + bust);
  }
  return g.UNTYPE_VIDEO!;
}

function timed(video: Video, profile: string): Timed[] {
  const overrides = video.timing[profile];
  if (!overrides) {
    throw new Error(`Unknown timing profile "${profile}". Known: ${Object.keys(video.timing).join(", ")}.`);
  }
  let t0 = 0;
  return video.beats.map((beat) => {
    const dur = Math.max(beat.min, overrides[beat.id] ?? 0);
    const item = { ...beat, t0, dur };
    t0 += dur;
    return item;
  });
}

function clipOf(dir: string, id: string): string | undefined {
  return CLIP_TYPES.map((type) => join(dir, `${id}.${type}`)).find(existsSync);
}
function seconds(file: string): number {
  const text = execFileSync("ffprobe", ["-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", file], { encoding: "utf8" });
  const value = parseFloat(text);
  if (!Number.isFinite(value)) {
    throw new Error(`Could not read the duration of ${file}.`);
  }
  return value;
}
function stamp(t: number, sep: string): string {
  const ms = Math.round(t * 1000);
  const p = (n: number, w = 2) => String(n).padStart(w, "0");
  return `${p(Math.floor(ms / 3600000))}:${p(Math.floor(ms / 60000) % 60)}:${p(Math.floor(ms / 1000) % 60)}${sep}${p(ms % 1000, 3)}`;
}
function voiceDir(lang: string): string {
  return resolve(root, arg("voice") ?? join("narration", lang));
}

async function sheets(): Promise<void> {
  const video = await load();
  mkdirSync(out, { recursive: true });
  for (const lang of Object.keys(video.narration)) {
    // A language is narrated on its own timing or on the neutral one.
    for (const profile of [lang, "neutral"]) {
      const beats = timed(video, profile);
      const total = beats[beats.length - 1].t0 + beats[beats.length - 1].dur;
      const rows = beats.map((b) => {
        const text = video.narration[lang][b.id] ?? "";
        const room = Math.max(0, b.dur - LEAD - TAIL);
        return `| ${stamp(b.t0, ".").slice(3, 10)} | \`${b.id}\` | ${b.dur.toFixed(1)} | ${room.toFixed(1)} | ${text.split(/\s+/).filter(Boolean).length} | ${text} |`;
      });
      writeFileSync(join(out, `narration-${lang}-${profile}.md`), [
        `# untype demo: narration (${lang}), timing profile "${profile}"`,
        "",
        `Total ${total.toFixed(1)} s. One clip per beat, saved as \`narration/${lang}/<beat>.wav\` (or mp3, m4a, aiff).`,
        `The voice starts ${LEAD} s into its beat. "Room" is the time the text has in this profile;`,
        "a longer clip is fine: `node tools/video.ts fit` then stretches the beat to the clip.",
        "",
        "| Starts | Beat | Beat (s) | Room (s) | Words | Text |",
        "|---|---|---|---|---|---|",
        ...rows,
        ""
      ].join("\n"));
      const srt = beats.filter((b) => video.narration[lang][b.id]).map((b, i) =>
        `${i + 1}\n${stamp(b.t0 + LEAD, ",")} --> ${stamp(b.t0 + b.dur - 0.15, ",")}\n${video.narration[lang][b.id]}\n`);
      writeFileSync(join(out, `subtitles-${lang}-${profile}.srt`), srt.join("\n"));
    }
  }
  console.log(`Sheets and subtitles written to ${out}`);
}

async function render(): Promise<void> {
  const video = await load();
  const lang = requireArg("lang");
  const profile = arg("timing") ?? "neutral";
  const fps = Number(arg("fps") ?? video.fps);
  const beats = timed(video, profile);
  const total = beats[beats.length - 1].t0 + beats[beats.length - 1].dur;
  const from = Number(arg("from") ?? 0);
  const to = Math.min(total, Number(arg("to") ?? total));
  mkdirSync(out, { recursive: true });
  const file = arg("out") ?? join(out, `untype-demo-${lang}-${profile}.mp4`);

  const { chromium } = await import("playwright");
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: video.width, height: video.height }, deviceScaleFactor: 1 });
  const errors: string[] = [];
  page.on("pageerror", (error) => errors.push(error.message));
  await page.addInitScript(() => { (window as unknown as { __recording: boolean }).__recording = true; });
  await page.goto(`${pathToFileURL(join(root, "src/untype-demo.html")).href}?lang=${lang}&timing=${profile}&t=0`);
  await page.waitForFunction(() => (window as unknown as { __ready?: boolean }).__ready === true);

  const ffmpeg = spawn("ffmpeg", ["-y", "-loglevel", "error", "-f", "image2pipe", "-framerate", String(fps), "-c:v", "png", "-i", "-",
    "-c:v", "libx264", "-preset", "slow", "-crf", "16", "-pix_fmt", "yuv420p", "-movflags", "+faststart", file], { stdio: ["pipe", "inherit", "inherit"] });
  const frames = Math.round((to - from) * fps);
  for (let i = 0; i < frames; i++) {
    await page.evaluate((t) => (window as unknown as { __seek: (t: number) => void }).__seek(t), from + i / fps);
    const png = await page.screenshot({ type: "png" });
    if (!ffmpeg.stdin.write(png)) {
      await new Promise((done) => ffmpeg.stdin.once("drain", done));
    }
    if (i % (fps * 10) === 0) {
      console.log(`  ${(from + i / fps).toFixed(0)} / ${to.toFixed(0)} s`);
    }
  }
  ffmpeg.stdin.end();
  await new Promise((done) => ffmpeg.on("close", done));
  await browser.close();
  if (errors.length > 0) {
    throw new Error(`The page reported errors while rendering: ${errors.slice(0, 3).join(" | ")}`);
  }
  console.log(`Rendered ${file} (${(to - from).toFixed(1)} s, ${fps} fps)`);
}

async function scratchVoice(): Promise<void> {
  const video = await load();
  const lang = requireArg("lang");
  const voice = SCRATCH_VOICES[lang];
  if (!voice) {
    throw new Error(`No system voice is set for "${lang}". Known: ${Object.keys(SCRATCH_VOICES).join(", ")}.`);
  }
  const dir = join(root, "narration", `${lang}-scratch`);
  mkdirSync(dir, { recursive: true });
  for (const beat of video.beats) {
    const text = video.narration[lang][beat.id];
    if (text) {
      execFileSync("say", ["-v", voice, "-o", join(dir, `${beat.id}.aiff`), text]);
    }
  }
  console.log(`Placeholder narration (${voice}) written to ${dir}`);
}

function writeTiming(profile: string, durations: Record<string, number>): void {
  writeFileSync(join(root, `src/timing.${profile}.js`), [
    `// Beat durations (seconds) of the "${profile}" profile. Written by \`node tools/video.ts fit\`.`,
    `(typeof window !== "undefined" ? window : globalThis).UNTYPE_VIDEO.timing["${profile}"] = ${JSON.stringify(durations, null, 2)};`,
    ""
  ].join("\n"));
}

async function fit(): Promise<void> {
  const video = await load();
  if (flag("neutral")) {
    const durations: Record<string, number> = {};
    for (const beat of video.beats) {
      durations[beat.id] = Math.max(beat.min, video.timing.el[beat.id] ?? 0, video.timing.en[beat.id] ?? 0);
    }
    writeTiming("neutral", durations);
    console.log("src/timing.neutral.js: the longer of the el and en durations per beat.");
    return;
  }
  const lang = requireArg("lang");
  const dir = voiceDir(lang);
  const durations: Record<string, number> = {};
  const missing: string[] = [];
  for (const beat of video.beats) {
    if (!video.narration[lang][beat.id]) {
      continue;
    }
    const clip = clipOf(dir, beat.id);
    if (!clip) {
      missing.push(beat.id);
      continue;
    }
    durations[beat.id] = Math.max(beat.min, Math.ceil((LEAD + seconds(clip) + TAIL) * 10) / 10);
  }
  if (missing.length > 0) {
    throw new Error(`No narration clip in ${dir} for: ${missing.join(", ")}.`);
  }
  writeTiming(lang, durations);
  const total = Object.values(durations).reduce((a, b) => a + b, 0);
  console.log(`src/timing.${lang}.js fitted to ${dir} (${total.toFixed(1)} s in total).`);
}

async function mux(): Promise<void> {
  const video = await load();
  const lang = requireArg("lang");
  const profile = arg("timing") ?? lang;
  const dir = voiceDir(lang);
  const picture = arg("video") ?? join(out, `untype-demo-${lang}-${profile}.mp4`);
  if (!existsSync(picture)) {
    throw new Error(`${picture} does not exist. Render it first: node tools/video.ts render --lang ${lang} --timing ${profile}`);
  }
  const beats = timed(video, profile);
  const inputs: string[] = [];
  const filters: string[] = [];
  let n = 0;
  for (const beat of beats) {
    const clip = clipOf(dir, beat.id);
    if (!clip) {
      continue;
    }
    const room = beat.dur - LEAD;
    const length = seconds(clip);
    if (length > room + 0.05) {
      throw new Error(`${clip} lasts ${length.toFixed(1)} s but beat "${beat.id}" has ${room.toFixed(1)} s in profile "${profile}". Run: node tools/video.ts fit --lang ${lang}`);
    }
    inputs.push("-i", clip);
    n += 1;
    const delay = Math.round((beat.t0 + LEAD) * 1000);
    filters.push(`[${n}:a]aresample=48000,aformat=channel_layouts=stereo,adelay=${delay}|${delay}[a${n}]`);
  }
  if (n === 0) {
    throw new Error(`No narration clips found in ${dir}.`);
  }
  const mix = `${Array.from({ length: n }, (_, i) => `[a${i + 1}]`).join("")}amix=inputs=${n}:normalize=0[voice]`;
  const file = join(out, `untype-demo-${lang}-voiced.mp4`);
  execFileSync("ffmpeg", ["-y", "-loglevel", "error", "-i", picture, ...inputs, "-filter_complex", [...filters, mix].join(";"),
    "-map", "0:v", "-map", "[voice]", "-c:v", "copy", "-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart", file], { stdio: "inherit" });
  console.log(`Voiced video: ${file}`);
}

const commands: Record<string, () => Promise<void>> = { sheets, render, "scratch-voice": scratchVoice, fit, mux };
const command = commands[process.argv[2] ?? ""];
if (!command) {
  console.error(`Usage: node tools/video.ts <${Object.keys(commands).join("|")}> [options]`);
  process.exit(2);
}
command().catch((error: Error) => {
  console.error(error.message);
  process.exit(1);
});
