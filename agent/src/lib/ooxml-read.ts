import { readFileSync } from "node:fs";
import { extname, posix } from "node:path";
import { ZipArchive } from "./zip.js";

/** Text out of Word, Excel and PowerPoint files (.docx, .xlsx, .pptx), read straight from their XML parts. */

export function decodeXml(s: string): string {
  return s
    .replace(/&#x([0-9a-fA-F]+);/g, (_, h: string) => String.fromCodePoint(parseInt(h, 16)))
    .replace(/&#(\d+);/g, (_, d: string) => String.fromCodePoint(Number(d)))
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&apos;/g, "'")
    .replace(/&amp;/g, "&");
}

function attrOf(tag: string, name: string): string | undefined {
  const m = new RegExp(`(?:^|\\s)${name}="([^"]*)"`).exec(tag);
  return m ? decodeXml(m[1]!) : undefined;
}

/** Relationship id → target path, resolved against the part that owns the .rels file. */
function relationships(zip: ZipArchive, part: string): Map<string, { target: string; type: string }> {
  const rels = posix.join(posix.dirname(part), "_rels", `${posix.basename(part)}.rels`);
  const out = new Map<string, { target: string; type: string }>();
  if (!zip.has(rels)) return out;
  for (const m of zip.text(rels).matchAll(/<Relationship\s[^>]*>/g)) {
    const id = attrOf(m[0], "Id");
    const target = attrOf(m[0], "Target");
    if (!id || !target || attrOf(m[0], "TargetMode") === "External") continue;
    const resolved = target.startsWith("/") ? target.slice(1) : posix.normalize(posix.join(posix.dirname(part), target));
    out.set(id, { target: resolved, type: attrOf(m[0], "Type") ?? "" });
  }
  return out;
}

/* ---------- Word ---------- */

function wordParagraph(xml: string): string {
  let text = "";
  for (const m of xml.matchAll(/<w:t(?:\s[^>]*)?>([^<]*)<\/w:t>|<w:tab\/>|<w:br(?:\s[^>]*)?\/>|<w:cr\/>/g)) {
    if (m[1] !== undefined) text += decodeXml(m[1]);
    else text += m[0].startsWith("<w:tab") ? "\t" : "\n";
  }
  return text;
}

/** Style id → heading level. Style ids are localised ("berschrift1", "1"); the style's name is always "heading N". */
function headingStyles(zip: ZipArchive): Map<string, number> {
  const out = new Map<string, number>();
  if (!zip.has("word/styles.xml")) return out;
  for (const m of zip.text("word/styles.xml").matchAll(/<w:style\s[^>]*>[\s\S]*?<\/w:style>/g)) {
    const id = /w:styleId="([^"]+)"/.exec(m[0])?.[1];
    const name = /<w:name\s+w:val="([^"]+)"/.exec(m[0])?.[1]?.toLowerCase() ?? "";
    const level = /^heading ([1-6])$/.exec(name)?.[1];
    if (id && level) out.set(id, Number(level));
    else if (id && name === "title") out.set(id, 1);
  }
  return out;
}

function wordBlock(xml: string, headings: ReadonlyMap<string, number>): string {
  const text = wordParagraph(xml).trim();
  if (text === "") return "";
  const style = /<w:pStyle\s+w:val="([^"]+)"/.exec(xml)?.[1] ?? "";
  const level = headings.get(style);
  if (level !== undefined) return `${"#".repeat(level)} ${text}`;
  if (/<w:numPr>/.test(xml)) return `- ${text}`;
  return text;
}

export function readDocx(zip: ZipArchive): string {
  const xml = zip.text("word/document.xml");
  const body = /<w:body>([\s\S]*)<\/w:body>/.exec(xml)?.[1] ?? xml;
  const headings = headingStyles(zip);
  const out: string[] = [];
  // Top-level blocks in order: tables (rendered as rows of cells) and paragraphs.
  for (const m of body.matchAll(/<w:tbl>[\s\S]*?<\/w:tbl>|<w:p(?:\s[^>]*)?>[\s\S]*?<\/w:p>/g)) {
    const block = m[0];
    if (block.startsWith("<w:tbl>")) {
      for (const row of block.matchAll(/<w:tr(?:\s[^>]*)?>[\s\S]*?<\/w:tr>/g)) {
        const cells = [...row[0].matchAll(/<w:tc>[\s\S]*?<\/w:tc>/g)].map((c) =>
          [...c[0].matchAll(/<w:p(?:\s[^>]*)?>[\s\S]*?<\/w:p>/g)].map((p) => wordParagraph(p[0]).trim()).filter(Boolean).join(" / "),
        );
        out.push(`| ${cells.join(" | ")} |`);
      }
      out.push("");
    } else {
      const line = wordBlock(block, headings);
      if (line !== "") out.push(line);
    }
  }
  return out.join("\n").replace(/\n{3,}/g, "\n\n").trim();
}

/* ---------- Excel ---------- */

function columnNumber(ref: string): number {
  let n = 0;
  for (const ch of /^[A-Z]+/.exec(ref)?.[0] ?? "A") n = n * 26 + (ch.charCodeAt(0) - 64);
  return n;
}

/** Which cell styles (cellXfs positions) show a date or time. */
function dateStyles(zip: ZipArchive): Set<number> {
  const out = new Set<number>();
  if (!zip.has("xl/styles.xml")) return out;
  const xml = sheetXml(zip, "xl/styles.xml");
  const custom = new Map<number, string>();
  for (const m of xml.matchAll(/<numFmt\s[^>]*>/g)) custom.set(Number(attrOf(m[0], "numFmtId")), attrOf(m[0], "formatCode") ?? "");
  const xfs = /<cellXfs[^>]*>([\s\S]*?)<\/cellXfs>/.exec(xml)?.[1] ?? "";
  let i = 0;
  for (const m of xfs.matchAll(/<xf\s[^>]*>/g)) {
    const id = Number(attrOf(m[0], "numFmtId") ?? "0");
    const code = custom.get(id);
    const builtinDate = (id >= 14 && id <= 22) || (id >= 45 && id <= 47);
    const customDate = code !== undefined && /[dmyhs]/i.test(code.replace(/"[^"]*"|\[[^\]]*\]|\\./g, ""));
    if (builtinDate || customDate) out.add(i);
    i++;
  }
  return out;
}

/** An Excel serial day number as an ISO date (with the time when it has one). */
export function excelDate(serial: number): string {
  const ms = Math.round((serial - 25569) * 86400 * 1000);
  const iso = new Date(ms).toISOString();
  return serial % 1 === 0 ? iso.slice(0, 10) : iso.slice(0, 19).replace("T", " ");
}

export interface SheetText {
  readonly name: string;
  readonly rows: number;
  readonly text: string;
}

/**
 * A SpreadsheetML part with element prefixes removed. Excel writes the main namespace unprefixed, but the Open XML
 * SDK and many reporting tools write `<x:row>`, `<x:c>`; without this such a workbook would read as empty.
 */
function sheetXml(zip: ZipArchive, part: string): string {
  return zip.text(part).replace(/<(\/?)[A-Za-z][A-Za-z0-9]*:(?=[A-Za-z])/g, "<$1");
}

export function readXlsx(zip: ZipArchive, maxRowsPerSheet: number): SheetText[] {
  const shared: string[] = [];
  if (zip.has("xl/sharedStrings.xml")) {
    for (const si of sheetXml(zip, "xl/sharedStrings.xml").matchAll(/<si>([\s\S]*?)<\/si>|<si\/>/g)) {
      const inner = (si[1] ?? "").replace(/<rPh[\s\S]*?<\/rPh>/g, "");
      shared.push([...inner.matchAll(/<t(?:\s[^>]*)?>([^<]*)<\/t>/g)].map((t) => decodeXml(t[1]!)).join(""));
    }
  }
  const dates = dateStyles(zip);
  const rels = relationships(zip, "xl/workbook.xml");
  const sheets: SheetText[] = [];
  for (const m of sheetXml(zip, "xl/workbook.xml").matchAll(/<sheet\s[^>]*>/g)) {
    const name = attrOf(m[0], "name") ?? "";
    const target = rels.get(attrOf(m[0], "r:id") ?? "")?.target;
    if (!target || !zip.has(target)) continue;
    const xml = sheetXml(zip, target);
    const lines: string[] = [];
    let rowCount = 0;
    for (const row of xml.matchAll(/<row(?:\s[^>]*)?>([\s\S]*?)<\/row>/g)) {
      rowCount++;
      if (lines.length >= maxRowsPerSheet) continue;
      const cells: string[] = [];
      for (const c of row[1]!.matchAll(/<c(\s[^>]*?)?(?:\/>|>([\s\S]*?)<\/c>)/g)) {
        const tag = c[1] ?? "";
        const inner = c[2] ?? "";
        const col = columnNumber(attrOf(tag, "r") ?? "");
        const type = attrOf(tag, "t");
        const v = /<v(?:\s[^>]*)?>([^<]*)<\/v>/.exec(inner)?.[1];
        let value = "";
        if (type === "s") value = shared[Number(v)] ?? "";
        else if (type === "inlineStr") value = [...inner.matchAll(/<t(?:\s[^>]*)?>([^<]*)<\/t>/g)].map((t) => decodeXml(t[1]!)).join("");
        else if (type === "b") value = v === "1" ? "TRUE" : "FALSE";
        else if (v === undefined) {
          // A formula that was never calculated (the file was written by a tool, not saved by Excel): show the formula.
          const f = /<f(?:\s[^>]*)?>([^<]*)<\/f>/.exec(inner)?.[1];
          if (f !== undefined && f !== "") value = `=${decodeXml(f)}`;
        } else {
          value = decodeXml(v);
          if (type === undefined && dates.has(Number(attrOf(tag, "s") ?? "-1")) && /^\d+(\.\d+)?$/.test(value)) value = excelDate(Number(value));
        }
        while (cells.length < col - 1) cells.push("");
        cells[col - 1] = value.replace(/[\t\r\n]+/g, " ");
      }
      const rowNumber = /\sr="(\d+)"/.exec(row[0])?.[1] ?? String(rowCount);
      lines.push(`${rowNumber}\t${cells.join("\t").trimEnd()}`);
    }
    const note = rowCount > lines.length ? `\n[${rowCount - lines.length} more row(s) not shown]` : "";
    sheets.push({ name, rows: rowCount, text: lines.join("\n") + note });
  }
  return sheets;
}

/* ---------- PowerPoint ---------- */

function drawingParagraphs(xml: string): string[] {
  const out: string[] = [];
  for (const p of xml.matchAll(/<a:p>([\s\S]*?)<\/a:p>/g)) {
    let text = "";
    for (const m of p[1]!.matchAll(/<a:t>([^<]*)<\/a:t>|<a:br(?:\s[^>]*)?\/>/g)) text += m[1] !== undefined ? decodeXml(m[1]) : "\n";
    if (text.trim() !== "") out.push(text.trim());
  }
  return out;
}

export interface SlideText {
  readonly index: number;
  readonly text: string;
  readonly notes: string;
}

export function readPptx(zip: ZipArchive): SlideText[] {
  const rels = relationships(zip, "ppt/presentation.xml");
  const slides: SlideText[] = [];
  const list = /<p:sldIdLst>([\s\S]*?)<\/p:sldIdLst>/.exec(zip.text("ppt/presentation.xml"))?.[1] ?? "";
  for (const m of list.matchAll(/<p:sldId\s[^>]*>/g)) {
    const target = rels.get(attrOf(m[0], "r:id") ?? "")?.target;
    if (!target || !zip.has(target)) continue;
    const notesPart = [...relationships(zip, target).values()].find((r) => r.type.endsWith("/notesSlide"))?.target;
    let notes = "";
    if (notesPart && zip.has(notesPart)) {
      // The notes page repeats the slide number in a field placeholder; drop the shape that holds it.
      const xml = zip.text(notesPart).replace(/<p:sp>(?:(?!<\/p:sp>)[\s\S])*?<p:ph\s[^>]*type="sldNum"[\s\S]*?<\/p:sp>/g, "");
      notes = drawingParagraphs(xml).join("\n");
    }
    slides.push({ index: slides.length + 1, text: drawingParagraphs(zip.text(target)).join("\n"), notes });
  }
  return slides;
}

/* ---------- one entry point ---------- */

export type OfficeKind = "docx" | "xlsx" | "pptx";

export function officeKind(path: string): OfficeKind {
  const ext = extname(path).toLowerCase();
  if (ext === ".docx" || ext === ".dotx") return "docx";
  if (ext === ".xlsx" || ext === ".xlsm") return "xlsx";
  if (ext === ".pptx" || ext === ".potx") return "pptx";
  throw new Error(`unsupported Office file type "${ext}": .docx, .xlsx and .pptx are supported (the old binary .doc/.xls/.ppt formats are not)`);
}

export function readOffice(path: string, options: { readonly maxRowsPerSheet: number; readonly sheet?: string }): string {
  const kind = officeKind(path);
  const zip = new ZipArchive(readFileSync(path));
  if (kind === "docx") return readDocx(zip);
  if (kind === "xlsx") {
    const sheets = readXlsx(zip, options.maxRowsPerSheet);
    const wanted = options.sheet === undefined ? sheets : sheets.filter((s) => s.name === options.sheet);
    if (options.sheet !== undefined && wanted.length === 0) throw new Error(`no sheet "${options.sheet}"; the workbook has: ${sheets.map((s) => s.name).join(", ")}`);
    return wanted.map((s) => `## Sheet "${s.name}" (${s.rows} row(s); first column is the row number, cells are tab-separated)\n${s.text}`).join("\n\n");
  }
  return readPptx(zip)
    .map((s) => `## Slide ${s.index}\n${s.text || "(no text)"}${s.notes ? `\n\nNotes:\n${s.notes}` : ""}`)
    .join("\n\n");
}
