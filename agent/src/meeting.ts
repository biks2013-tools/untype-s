import { existsSync, readdirSync, readFileSync, statSync } from "node:fs";
import { extname, join } from "node:path";

/** One line of `<stem>.segments.jsonl`, as untype writes it. */
export interface Segment {
  readonly startMs: number;
  readonly endMs: number;
  readonly side: "you" | "call";
  readonly speaker?: string;
  readonly language?: string;
  readonly text: string;
  readonly english?: string;
}

/** One entry of `<stem>.attachments.json`. */
export interface Attachment {
  readonly id: number;
  readonly clip: number;
  readonly offsetMs: number;
  readonly time: string;
  readonly attachedAt: string;
  readonly kind: "text" | "image" | "file" | "folder";
  readonly file: string;
  readonly bytes?: number;
  readonly originalName?: string;
  readonly characters?: number;
  readonly width?: number;
  readonly height?: number;
}

function fileWithSuffix(folder: string, suffix: string): string | undefined {
  if (!existsSync(folder)) return undefined;
  const name = readdirSync(folder)
    .filter((n) => n.startsWith("recording-") && n.endsWith(suffix))
    .sort()[0];
  return name === undefined ? undefined : join(folder, name);
}

/** The transcript so far, in time order. Lines being written while this reads are skipped until they are whole. */
export function readSegments(folder: string): Segment[] {
  const file = fileWithSuffix(folder, ".segments.jsonl");
  if (file === undefined) return [];
  const segments: Segment[] = [];
  for (const line of readFileSync(file, "utf8").split("\n")) {
    if (line.trim() === "") continue;
    try {
      const s = JSON.parse(line) as Segment;
      if (typeof s.startMs === "number" && typeof s.text === "string") segments.push(s);
    } catch {
      // a line still being written
    }
  }
  return segments.sort((a, b) => a.startMs - b.startMs);
}

export function readAttachments(folder: string): Attachment[] {
  const file = fileWithSuffix(folder, ".attachments.json");
  if (file === undefined) return [];
  try {
    const index = JSON.parse(readFileSync(file, "utf8")) as { attachments?: Attachment[] };
    return Array.isArray(index.attachments) ? index.attachments : [];
  } catch {
    return [];
  }
}

/** `00:12:34` */
export function clock(ms: number): string {
  const s = Math.max(0, Math.floor(ms / 1000));
  const two = (n: number) => String(n).padStart(2, "0");
  return `${two(Math.floor(s / 3600))}:${two(Math.floor(s / 60) % 60)}:${two(s % 60)}`;
}

/** `12:34`, `00:12:34` or a number of seconds, as milliseconds; undefined when it is none of them. */
export function parseClock(value: string): number | undefined {
  const text = value.trim();
  if (/^\d+(\.\d+)?$/.test(text)) return Math.round(Number(text) * 1000);
  const parts = text.split(":").map((p) => Number(p));
  if (parts.length < 2 || parts.length > 3 || parts.some((p) => !Number.isFinite(p) || p < 0)) return undefined;
  const [h, m, s] = parts.length === 3 ? (parts as [number, number, number]) : [0, parts[0] as number, parts[1] as number];
  return ((h * 60 + m) * 60 + s) * 1000;
}

export function speaker(segment: Segment): string {
  if (segment.side === "you") return segment.speaker === undefined ? "You" : `Person ${segment.speaker}`;
  return segment.speaker === undefined ? "Call" : `Speaker ${segment.speaker}`;
}

/** `[00:12:15] Speaker 3: text` (with the English text after it when the meeting has one). */
export function line(segment: Segment): string {
  const english = segment.english !== undefined && segment.english !== segment.text ? `  (English: ${segment.english})` : "";
  return `[${clock(segment.startMs)}] ${speaker(segment)}: ${segment.text}${english}`;
}

export interface TranscriptRange {
  readonly fromMs?: number;
  readonly toMs?: number;
  readonly lastMinutes?: number;
}

export function segmentsIn(segments: readonly Segment[], range: TranscriptRange): Segment[] {
  let from = range.fromMs ?? 0;
  const to = range.toMs ?? Number.POSITIVE_INFINITY;
  if (range.lastMinutes !== undefined) {
    const end = segments.at(-1)?.endMs ?? 0;
    from = Math.max(from, end - range.lastMinutes * 60_000);
  }
  return segments.filter((s) => s.endMs >= from && s.startMs <= to);
}

export function describeAttachment(a: Attachment): string {
  const what =
    a.kind === "image" ? `picture ${a.width ?? "?"}×${a.height ?? "?"}`
    : a.kind === "text" ? `text, ${a.characters ?? "?"} characters`
    : a.kind === "folder" ? `folder "${a.originalName ?? ""}"`
    : `file "${a.originalName ?? ""}"${a.bytes === undefined ? "" : `, ${a.bytes} bytes`}`;
  return `#${a.id} at ${a.time}: ${what}`;
}

/** The transcript with each attachment mentioned at its moment. */
export function transcriptText(segments: readonly Segment[], attachments: readonly Attachment[]): string {
  const rows: { at: number; text: string }[] = [
    ...segments.map((s) => ({ at: s.startMs, text: line(s) })),
    ...attachments.map((a) => ({ at: a.offsetMs, text: `[${a.time}] (attachment ${describeAttachment(a)})` })),
  ];
  return rows.sort((a, b) => a.at - b.at).map((r) => r.text).join("\n");
}

export interface SearchHit {
  readonly index: number;
  readonly text: string;
}

/** Lines that contain every word of `query` (case and accents ignored), each with the line before and after. */
export function search(segments: readonly Segment[], query: string, maxResults: number): string[] {
  const fold = (t: string) => t.normalize("NFD").replace(/\p{M}/gu, "").toLowerCase();
  const words = fold(query).split(/\s+/).filter((w) => w !== "");
  if (words.length === 0) return [];
  const blocks: string[] = [];
  for (let i = 0; i < segments.length && blocks.length < maxResults; i++) {
    const s = segments[i] as Segment;
    const text = fold(`${s.text} ${s.english ?? ""}`);
    if (!words.every((w) => text.includes(w))) continue;
    blocks.push(segments.slice(Math.max(0, i - 1), i + 2).map(line).join("\n"));
  }
  return blocks;
}

const TEXT_EXTENSIONS = new Set([".txt", ".md", ".csv", ".tsv", ".json", ".jsonl", ".xml", ".html", ".htm", ".yaml", ".yml", ".log", ".swift", ".ts", ".js", ".py", ".sql", ".sh", ".css", ".ini", ".toml"]);
const IMAGE_TYPES: Record<string, string> = { ".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".gif": "image/gif", ".webp": "image/webp", ".bmp": "image/bmp" };
/** Word, Excel and PowerPoint files, read here from their XML parts. */
const OFFICE_EXTENSIONS = new Set([".docx", ".dotx", ".xlsx", ".xlsm", ".pptx", ".potx"]);
/** Read by untype itself (PDFKit, and the system's reader of old Word and rich text files). */
const HOST_EXTENSIONS = new Set([".pdf", ".doc", ".rtf"]);

export type AttachmentContent =
  | { readonly type: "text"; readonly text: string }
  | { readonly type: "image"; readonly bytes: Uint8Array; readonly mimeType: string }
  /** A Word, Excel or PowerPoint file: `readOffice(path)` gives its text. */
  | { readonly type: "office"; readonly path: string }
  /** A PDF, old Word or rich text file: untype gives its text. */
  | { readonly type: "host"; readonly path: string }
  | { readonly type: "unreadable"; readonly reason: string };

export const MAX_TEXT_CHARS = 40_000;

/** `MAX_TEXT_CHARS` of `text` from `offset`, saying how to read on when there is more. */
export function textPage(text: string, offset: number): string {
  if (offset >= text.length && text.length > 0) return `[nothing from character ${offset}: the text has ${text.length} characters]`;
  const end = Math.min(text.length, offset + MAX_TEXT_CHARS);
  const more = end < text.length ? `\n\n[characters ${offset}–${end} of ${text.length}: read on with offset ${end}]` : "";
  return text.slice(offset, end) + more;
}

/** What an attachment holds, as far as this agent can read it. The file must be inside the meeting folder. */
export function attachmentContent(folder: string, a: Attachment): AttachmentContent {
  const path = join(folder, a.file);
  if (a.file.includes("..") || !existsSync(path)) return { type: "unreadable", reason: "its file is no longer in the meeting folder" };
  if (a.kind === "folder" || statSync(path).isDirectory()) {
    return { type: "text", text: `A folder with: ${readdirSync(path).slice(0, 200).join(", ")}` };
  }
  const ext = extname(path).toLowerCase();
  const imageType = IMAGE_TYPES[ext];
  if (a.kind === "image" || imageType !== undefined) return { type: "image", bytes: readFileSync(path), mimeType: imageType ?? "image/png" };
  if (a.kind === "text" || TEXT_EXTENSIONS.has(ext)) return { type: "text", text: readFileSync(path, "utf8") };
  if (OFFICE_EXTENSIONS.has(ext)) return { type: "office", path };
  if (HOST_EXTENSIONS.has(ext)) return { type: "host", path };
  return { type: "unreadable", reason: `files of type ${ext || "(none)"} cannot be read by the assistant (it reads pictures, text files, PDF, Word, Excel and PowerPoint)` };
}
