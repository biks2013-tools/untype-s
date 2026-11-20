import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { meetingNow } from "../src/extension.js";
import { readOffice } from "../src/lib/ooxml-read.js";
import { writeZip } from "../src/lib/zip.js";
import { textPage, MAX_TEXT_CHARS, attachmentContent, clock, parseClock, readAttachments, readSegments, search, segmentsIn, transcriptText } from "../src/meeting.js";

function meeting(): string {
  const folder = mkdtempSync(join(tmpdir(), "untype-agent-"));
  const segments = [
    { startMs: 65_000, endMs: 70_000, side: "call", speaker: "1", language: "el", text: "Ο προϋπολογισμός είναι έτοιμος", english: "The budget is ready" },
    { startMs: 1_000, endMs: 4_000, side: "you", text: "Καλημέρα" },
    { startMs: 400_000, endMs: 405_000, side: "call", speaker: "2", text: "We ship on Friday" },
  ];
  writeFileSync(join(folder, "recording-2026-11-20-10-30.segments.jsonl"), `${segments.map((s) => JSON.stringify(s)).join("\n")}\n{"startMs": 9`);
  mkdirSync(join(folder, "attachments"));
  writeFileSync(join(folder, "attachments", "001-00-01-10-text.txt"), "the note");
  writeFileSync(join(folder, "attachments", "002-00-06-41-report.pdf"), "%PDF");
  writeFileSync(
    join(folder, "recording-2026-11-20-10-30.attachments.json"),
    JSON.stringify({
      version: 1,
      attachments: [
        { id: 1, clip: 1, offsetMs: 70_500, time: "00:01:10", attachedAt: "x", kind: "text", file: "attachments/001-00-01-10-text.txt", characters: 8 },
        { id: 2, clip: 2, offsetMs: 401_000, time: "00:06:41", attachedAt: "x", kind: "file", file: "attachments/002-00-06-41-report.pdf", originalName: "report.pdf", bytes: 4 },
      ],
    }),
  );
  return folder;
}

test("the transcript is read in time order, without the line still being written", () => {
  const folder = meeting();
  try {
    const segments = readSegments(folder);
    assert.deepEqual(segments.map((s) => s.startMs), [1_000, 65_000, 400_000]);
    const text = transcriptText(segments, readAttachments(folder));
    assert.deepEqual(text.split("\n"), [
      "[00:00:01] You: Καλημέρα",
      "[00:01:05] Speaker 1: Ο προϋπολογισμός είναι έτοιμος  (English: The budget is ready)",
      "[00:01:10] (attachment #1 at 00:01:10: text, 8 characters)",
      "[00:06:40] Speaker 2: We ship on Friday",
      '[00:06:41] (attachment #2 at 00:06:41: file "report.pdf", 4 bytes)',
    ]);
  } finally {
    rmSync(folder, { recursive: true });
  }
});

test("times, ranges and search", () => {
  const folder = meeting();
  try {
    const segments = readSegments(folder);
    assert.equal(clock(754_300), "00:12:34");
    assert.equal(parseClock("12:34"), 754_000);
    assert.equal(parseClock("01:00:00"), 3_600_000);
    assert.equal(parseClock("90"), 90_000);
    assert.equal(parseClock("soon"), undefined);
    assert.deepEqual(segmentsIn(segments, { fromMs: 60_000, toMs: 120_000 }).map((s) => s.startMs), [65_000]);
    assert.deepEqual(segmentsIn(segments, { lastMinutes: 2 }).map((s) => s.startMs), [400_000]);
    // Accents and case are ignored; the English text counts too.
    assert.equal(search(segments, "προυπολογισμος", 5).length, 1);
    assert.equal(search(segments, "BUDGET ready", 5).length, 1);
    assert.equal(search(segments, "nothing here", 5).length, 0);
  } finally {
    rmSync(folder, { recursive: true });
  }
});

test("attachments: text is read, other files say why not, nothing outside the folder", () => {
  const folder = meeting();
  try {
    const [note, pdf] = readAttachments(folder);
    assert.ok(note && pdf);
    assert.deepEqual(attachmentContent(folder, note), { type: "text", text: "the note" });
    // A PDF is read by untype; a Word file here; an unknown kind says what can be read.
    assert.deepEqual(attachmentContent(folder, pdf), { type: "host", path: join(folder, pdf.file) });
    writeFileSync(join(folder, "attachments", "003-x.docx"), "");
    writeFileSync(join(folder, "attachments", "004-x.zip"), "");
    assert.equal(attachmentContent(folder, { ...pdf, file: "attachments/003-x.docx" }).type, "office");
    const unknown = attachmentContent(folder, { ...pdf, file: "attachments/004-x.zip" });
    assert.equal(unknown.type, "unreadable");
    assert.equal(attachmentContent(folder, { ...note, file: "../secret.txt" }).type, "unreadable");
  } finally {
    rmSync(folder, { recursive: true });
  }
});

test("every question carries the last minutes of the meeting", () => {
  const folder = meeting();
  try {
    const now = meetingNow({ folder, recording: true }, 3);
    assert.match(now, /being recorded/);
    assert.match(now, /3 lines, up to 00:06:45/);
    assert.match(now, /We ship on Friday/);
    assert.match(now, /attachment #2/);
    assert.doesNotMatch(now, /Καλημέρα/);
  } finally {
    rmSync(folder, { recursive: true });
  }
});

test("Word, Excel and PowerPoint files are read as text", () => {
  const folder = mkdtempSync(join(tmpdir(), "untype-agent-office-"));
  try {
    const docx = join(folder, "a.docx");
    writeFileSync(docx, writeZip([{ name: "word/document.xml", data: '<w:document><w:body><w:p><w:r><w:t>Budget plan</w:t></w:r></w:p><w:p><w:r><w:t>Second &amp; last</w:t></w:r></w:p></w:body></w:document>' }]));
    const word = readOffice(docx, { maxRowsPerSheet: 10 });
    assert.match(word, /Budget plan/);
    assert.match(word, /Second & last/);

    const pptx = join(folder, "a.pptx");
    writeFileSync(
      pptx,
      writeZip([
        { name: "ppt/presentation.xml", data: '<p:presentation><p:sldIdLst><p:sldId id="256" r:id="rId1"/></p:sldIdLst></p:presentation>' },
        { name: "ppt/_rels/presentation.xml.rels", data: '<Relationships><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" Target="slides/slide1.xml"/></Relationships>' },
        { name: "ppt/slides/slide1.xml", data: "<p:sld><p:cSld><p:spTree><p:sp><p:txBody><a:p><a:r><a:t>Roadmap 2027</a:t></a:r></a:p></p:txBody></p:sp></p:spTree></p:cSld></p:sld>" },
      ]),
    );
    assert.match(readOffice(pptx, { maxRowsPerSheet: 10 }), /Slide 1[\s\S]*Roadmap 2027/);

    const xlsx = join(folder, "a.xlsx");
    writeFileSync(
      xlsx,
      writeZip([
        { name: "xl/workbook.xml", data: '<workbook><sheets><sheet name="Costs" sheetId="1" r:id="rId1"/></sheets></workbook>' },
        { name: "xl/_rels/workbook.xml.rels", data: '<Relationships><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/></Relationships>' },
        { name: "xl/sharedStrings.xml", data: "<sst><si><t>Item</t></si><si><t>Licences</t></si></sst>" },
        { name: "xl/worksheets/sheet1.xml", data: '<worksheet><sheetData><row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1"><v>12</v></c></row><row r="2"><c r="A2" t="s"><v>1</v></c><c r="B2"><v>3400</v></c></row></sheetData></worksheet>' },
      ]),
    );
    const sheet = readOffice(xlsx, { maxRowsPerSheet: 10 });
    assert.match(sheet, /Sheet "Costs"/);
    assert.match(sheet, /Licences\t3400/);
  } finally {
    rmSync(folder, { recursive: true });
  }
});

test("a long document is read in parts", () => {
  const text = "a".repeat(MAX_TEXT_CHARS) + "b".repeat(10);
  const first = textPage(text, 0);
  assert.ok(first.startsWith("a".repeat(100)));
  assert.match(first, new RegExp(`characters 0–${MAX_TEXT_CHARS} of ${MAX_TEXT_CHARS + 10}: read on with offset ${MAX_TEXT_CHARS}`));
  assert.equal(textPage(text, MAX_TEXT_CHARS), "b".repeat(10));
  assert.match(textPage(text, MAX_TEXT_CHARS + 500), /nothing from character/);
  assert.equal(textPage("short", 0), "short");
});
