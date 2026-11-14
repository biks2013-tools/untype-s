// Measures how well simple filters would keep one person's dictation and
// drop the people talking around them.
//
//   node test_scripts/voice-filter/probe.ts <audio file> [--script <text file>] [--speed 2] [--out <dir>]
//
// The audio (any format ffmpeg reads; a meeting's `.mic.m4a` works) is sent
// to Soniox realtime with speaker diarization. For every recognised word the
// tool notes its speaker label and its loudness in the audio. With --script
// (the text the user read aloud), words found in the script count as the
// user's and all others as someone else's, and each filter is scored.
//
// Printed: numbers only. The words go to <out>/words.tsv for the user to read.
// Needs ffmpeg and SONIOX_API_KEY (shell environment, else ~/.tool-agents/untype/.env).
import { execFileSync } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { basename, join, resolve } from "node:path";

type Word = { text: string; startMs: number; endMs: number; speaker: string; db: number; mine?: boolean };

function arg(name: string): string | undefined {
  const i = process.argv.indexOf(`--${name}`);
  return i >= 0 ? process.argv[i + 1] : undefined;
}

function sonioxKey(): string {
  if (process.env.SONIOX_API_KEY) {
    return process.env.SONIOX_API_KEY;
  }
  const file = join(homedir(), ".tool-agents/untype/.env");
  if (existsSync(file)) {
    for (const line of readFileSync(file, "utf8").split("\n")) {
      const match = line.match(/^SONIOX_API_KEY=(.+)$/);
      if (match) {
        return match[1].trim().replace(/^"(.*)"$/, "$1");
      }
    }
  }
  throw new Error("SONIOX_API_KEY is not set (shell environment or ~/.tool-agents/untype/.env).");
}

const RATE = 16000;

function decode(file: string): Int16Array {
  const raw = execFileSync("ffmpeg", ["-v", "error", "-i", file, "-f", "s16le", "-ac", "1", "-ar", String(RATE), "-"], { maxBuffer: 1 << 30 });
  return new Int16Array(raw.buffer, raw.byteOffset, raw.byteLength / 2);
}

function db(pcm: Int16Array, startMs: number, endMs: number): number {
  const a = Math.max(0, Math.floor(startMs * RATE / 1000));
  const b = Math.min(pcm.length, Math.ceil(endMs * RATE / 1000));
  if (b <= a) {
    return -120;
  }
  let sum = 0;
  for (let i = a; i < b; i++) {
    sum += pcm[i] * pcm[i];
  }
  return 10 * Math.log10(sum / (b - a) / (32768 * 32768) + 1e-12);
}

async function transcribe(pcm: Int16Array, speed: number): Promise<Word[]> {
  const socket = new WebSocket("wss://stt-rt.soniox.com/transcribe-websocket");
  socket.binaryType = "arraybuffer";
  type Token = { text: string; start_ms?: number; end_ms?: number; speaker?: string; is_final?: boolean };
  const tokens: Token[] = [];
  let failure: string | undefined;
  const done = new Promise<void>((resolveDone) => {
    socket.onmessage = (event) => {
      const message = JSON.parse(String(event.data));
      if (message.error_code || message.error_message) {
        failure = `${message.error_code}: ${message.error_message}`;
      }
      for (const token of (message.tokens ?? []) as Token[]) {
        if (token.is_final && token.text !== "<end>" && token.text !== "<fin>") {
          tokens.push(token);
        }
      }
      if (message.finished) {
        resolveDone();
      }
    };
    socket.onclose = () => resolveDone();
    socket.onerror = () => { failure = failure ?? "WebSocket error"; resolveDone(); };
  });
  await new Promise<void>((open, fail) => { socket.onopen = () => open(); setTimeout(() => fail(new Error("Soniox did not answer.")), 15000); });
  socket.send(JSON.stringify({
    api_key: sonioxKey(), model: "stt-rt-v6", audio_format: "pcm_s16le", sample_rate: RATE, num_channels: 1,
    language_hints: ["el", "en"], enable_endpoint_detection: true, enable_speaker_diarization: true
  }));
  const chunk = RATE / 10;
  for (let i = 0; i < pcm.length; i += chunk) {
    const piece = pcm.subarray(i, Math.min(pcm.length, i + chunk));
    socket.send(piece.buffer.slice(piece.byteOffset, piece.byteOffset + piece.byteLength));
    await new Promise((r) => setTimeout(r, 100 / speed));
  }
  socket.send("");
  await done;
  if (failure) {
    throw new Error(`Soniox: ${failure}`);
  }
  // Tokens are pieces of words; a piece that starts with a space starts a word.
  const words: Word[] = [];
  for (const token of tokens) {
    const startsWord = /^\s/.test(token.text) || words.length === 0 || token.speaker !== tokens[tokens.indexOf(token) - 1]?.speaker;
    const text = token.text.trim();
    if (!text) {
      continue;
    }
    const last = words[words.length - 1];
    if (!startsWord && last) {
      last.text += text;
      last.endMs = token.end_ms ?? last.endMs;
    } else {
      words.push({ text, startMs: token.start_ms ?? 0, endMs: token.end_ms ?? 0, speaker: token.speaker ?? "?", db: 0 });
    }
  }
  for (const word of words) {
    word.db = db(pcm, word.startMs, word.endMs);
  }
  return words;
}

const norm = (s: string) => s.toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "").replace(/[^\p{L}\p{N}]/gu, "");

/** Marks the words that follow the script (longest common subsequence). */
function markScript(words: Word[], script: string): void {
  const a = words.map((w) => norm(w.text));
  const b = script.split(/\s+/).map(norm).filter(Boolean);
  const table = Array.from({ length: a.length + 1 }, () => new Uint16Array(b.length + 1));
  for (let i = a.length - 1; i >= 0; i--) {
    for (let j = b.length - 1; j >= 0; j--) {
      table[i][j] = a[i] && a[i] === b[j] ? table[i + 1][j + 1] + 1 : Math.max(table[i + 1][j], table[i][j + 1]);
    }
  }
  let i = 0, j = 0;
  while (i < a.length && j < b.length) {
    if (a[i] && a[i] === b[j]) { words[i].mine = true; i++; j++; }
    else if (table[i + 1][j] >= table[i][j + 1]) { words[i].mine = false; i++; }
    else { j++; }
  }
  for (const word of words) {
    word.mine = word.mine ?? false;
  }
}

const median = (values: number[]) => { const s = [...values].sort((x, y) => x - y); return s.length ? s[Math.floor(s.length / 2)] : -120; };

async function main(): Promise<void> {
  const file = process.argv[2];
  if (!file || file.startsWith("--")) {
    throw new Error("Usage: node test_scripts/voice-filter/probe.ts <audio file> [--script <text file>] [--speed 2] [--out <dir>]");
  }
  const speed = Number(arg("speed") ?? 2);
  const out = resolve(arg("out") ?? join("test_scripts/voice-filter/out", basename(file).replace(/\.[^.]+$/, "")));
  mkdirSync(out, { recursive: true });
  const pcm = decode(file);
  const seconds = pcm.length / RATE;
  const frames: number[] = [];
  for (let ms = 0; ms + 50 <= seconds * 1000; ms += 50) {
    frames.push(db(pcm, ms, ms + 50));
  }
  frames.sort((x, y) => x - y);
  console.log(`audio: ${seconds.toFixed(1)} s, quietest tenth ${frames[Math.floor(frames.length * 0.1)].toFixed(0)} dBFS, loudest tenth ${frames[Math.floor(frames.length * 0.9)].toFixed(0)} dBFS`);

  const words = await transcribe(pcm, speed);
  const scriptFile = arg("script");
  if (scriptFile) {
    markScript(words, readFileSync(scriptFile, "utf8"));
  }
  writeFileSync(join(out, "words.tsv"), ["start_s\tend_s\tspeaker\tdBFS\tfrom_script\tword",
    ...words.map((w) => `${(w.startMs / 1000).toFixed(2)}\t${(w.endMs / 1000).toFixed(2)}\t${w.speaker}\t${w.db.toFixed(1)}\t${w.mine === undefined ? "" : w.mine ? "yes" : "no"}\t${w.text}`)].join("\n") + "\n");

  const speakers = [...new Set(words.map((w) => w.speaker))];
  console.log(`words: ${words.length}, speakers: ${speakers.length}`);
  const level: Record<string, number> = {};
  for (const speaker of speakers) {
    const own = words.filter((w) => w.speaker === speaker);
    level[speaker] = median(own.map((w) => w.db));
    const scripted = scriptFile ? `, ${own.filter((w) => w.mine).length} from the script` : "";
    console.log(`  speaker ${speaker}: ${own.length} words${scripted}, median ${level[speaker].toFixed(1)} dBFS, first word at ${(own[0].startMs / 1000).toFixed(1)} s`);
  }
  if (!scriptFile) {
    console.log(`words written to ${join(out, "words.tsv")}`);
    return;
  }
  const mine = words.filter((w) => w.mine), other = words.filter((w) => !w.mine);
  console.log(`from the script (the user): ${mine.length}; everything else: ${other.length}`);
  const first = words[0]?.speaker;
  const loudest = speakers.reduce((a, b) => (level[a] >= level[b] ? a : b), speakers[0]);
  const top = level[loudest];
  const filters: [string, (w: Word) => boolean][] = [
    ["no filter", () => true],
    [`first speaker (${first})`, (w) => w.speaker === first],
    [`loudest speaker (${loudest})`, (w) => w.speaker === loudest],
    ...[6, 9, 12, 15].map((d): [string, (w: Word) => boolean] => [`level within ${d} dB of the loudest speaker`, (w) => w.db >= top - d]),
    ...[9, 12].map((d): [string, (w: Word) => boolean] => [`loudest speaker, or level within ${d} dB`, (w) => w.speaker === loudest || w.db >= top - d]),
    ...[9, 12].map((d): [string, (w: Word) => boolean] => [`loudest speaker and level within ${d} dB`, (w) => w.speaker === loudest && w.db >= top - d])
  ];
  console.log("filter                                             user's words kept    other words let through");
  for (const [name, keep] of filters) {
    const kept = mine.filter(keep).length, leaked = other.filter(keep).length;
    const pct = (n: number, d: number) => (d ? `${String(n).padStart(3)}/${String(d).padEnd(3)} ${(100 * n / d).toFixed(0).padStart(3)}%` : "  -");
    console.log(`  ${name.padEnd(48)} ${pct(kept, mine.length)}          ${pct(leaked, other.length)}`);
  }
  console.log(`words written to ${join(out, "words.tsv")}`);
}

main().catch((error: Error) => { console.error(error.message); process.exit(1); });
