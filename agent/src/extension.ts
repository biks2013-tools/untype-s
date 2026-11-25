import { int, obj, opt, str } from "@earendil-works/pi-schema";
import { defineExtension, defineTool, section, type Extension } from "@earendil-works/pi-durable";
import { DEFAULT_IMAGE_LIMITS, type ImageProcessor } from "@earendil-works/pi-durable/tools";
import { readOffice } from "./lib/ooxml-read.js";
import { attachmentContent, textPage, clock, describeAttachment, parseClock, readAttachments, readSegments, search, segmentsIn, speaker, transcriptText } from "./meeting.js";

/** The meeting the assistant is looking at: set by untype, read by every tool call. */
export interface MeetingState {
  folder: string;
  recording: boolean;
}

/** Reads documents this process cannot: untype does it (PDF with PDFKit, old Word and rich text files). */
export interface DocumentHost {
  extract(path: string): Promise<string>;
}

const MAX_OUTPUT_CHARS = 30_000;
/** Rows read of each sheet of a workbook. */
const MAX_SHEET_ROWS = 500;

const INSTRUCTIONS = `You are the meeting assistant of untype, an application that records and transcribes meetings on the user's Mac.
The user is in a meeting that is being recorded (or looks at one that ended) and asks you about it.

What you can see, through your tools: the transcript so far (it grows while the meeting goes on) and what the user attached to moments of it (screenshots, text, files).
- "You" in the transcript is the user (their microphone). "Speaker 1", "Speaker 2", … are the other people in the call; their names are not known unless someone says them.
- Times are hours:minutes:seconds since the recording started.
- Every question comes with the last minutes of the transcript in a <meeting-now> block. For anything earlier, or when you need more, read or search the transcript with your tools before answering. Look at an attachment before you say what it shows.
- The transcript is made by speech recognition: names and terms can be written wrongly. Say so when an answer depends on a doubtful word.

How to answer: in the language of the question, short and direct, the answer first. Quote the time ([00:12:34]) of what you rely on. When the meeting does not hold the answer, say that plainly; you may add what you know yourself, marked as your own knowledge. You only read: you cannot change the recording, its files, or anything else.`;

function text(value: string) {
  return { output: [{ type: "text" as const, text: value.length > MAX_OUTPUT_CHARS ? `${value.slice(0, MAX_OUTPUT_CHARS)}\n\n[cut: ${value.length} characters in all; ask for a narrower range]` : value }] };
}

/** The last `minutes` of the transcript, sent along with every question. */
export function meetingNow(state: MeetingState, minutes: number): string {
  const segments = readSegments(state.folder);
  const attachments = readAttachments(state.folder);
  const end = segments.at(-1)?.endMs ?? 0;
  const recent = segmentsIn(segments, { lastMinutes: minutes });
  const from = recent[0]?.startMs ?? end;
  return [
    `${state.recording ? "The meeting is being recorded" : "The recording has ended"}. Transcript so far: ${segments.length} lines, up to ${clock(end)}. Attachments: ${attachments.length}.`,
    recent.length === 0 ? "Nothing has been said yet." : `The last ${minutes} minutes:`,
    transcriptText(recent, attachments.filter((a) => a.offsetMs >= from)),
  ].join("\n");
}

export function meetingExtension(state: MeetingState, images: ImageProcessor, host: DocumentHost): Extension {
  const overview = defineTool({
    name: "meeting_overview",
    description: "How long the meeting is so far, how many lines its transcript has, who speaks, and the list of attachments.",
    parameters: obj({}),
    replay: "safe",
    async execute() {
      const segments = readSegments(state.folder);
      const attachments = readAttachments(state.folder);
      const speakers = new Map<string, number>();
      for (const s of segments) {
        const name = speaker(s);
        speakers.set(name, (speakers.get(name) ?? 0) + 1);
      }
      return text(
        [
          state.recording ? "The meeting is being recorded now." : "The recording has ended.",
          `Transcript: ${segments.length} lines, from ${clock(segments[0]?.startMs ?? 0)} to ${clock(segments.at(-1)?.endMs ?? 0)}.`,
          `Lines per speaker: ${[...speakers].map(([n, c]) => `${n} ${c}`).join(", ") || "none yet"}.`,
          attachments.length === 0 ? "No attachments." : `Attachments:\n${attachments.map(describeAttachment).join("\n")}`,
        ].join("\n"),
      );
    },
  });

  const read = defineTool({
    name: "read_transcript",
    description: "Read the transcript of the meeting, whole or a part of it by time. Attachments are mentioned at their moments. Long answers are cut: read a narrower range then.",
    parameters: obj({
      from: opt(str({ description: "Start, as HH:MM:SS, MM:SS or seconds since the recording started. The beginning when omitted." })),
      to: opt(str({ description: "End, in the same form. The latest line when omitted." })),
      last_minutes: opt(int({ minimum: 1, maximum: 600, description: "Only the last N minutes of what has been said so far." })),
    }),
    replay: "safe",
    async execute(args) {
      const fromMs = args.from === undefined ? undefined : parseClock(args.from);
      const toMs = args.to === undefined ? undefined : parseClock(args.to);
      if (args.from !== undefined && fromMs === undefined) throw new Error(`"${args.from}" is not a time: use HH:MM:SS, MM:SS or seconds`);
      if (args.to !== undefined && toMs === undefined) throw new Error(`"${args.to}" is not a time: use HH:MM:SS, MM:SS or seconds`);
      const segments = segmentsIn(readSegments(state.folder), { fromMs, toMs, lastMinutes: args.last_minutes });
      if (segments.length === 0) return text("Nothing was said in that part of the meeting.");
      const first = segments[0]?.startMs ?? 0;
      const last = segments.at(-1)?.endMs ?? 0;
      const attachments = readAttachments(state.folder).filter((a) => a.offsetMs >= first && a.offsetMs <= last);
      return text(transcriptText(segments, attachments));
    },
  });

  const find = defineTool({
    name: "search_transcript",
    description: "Find the lines of the transcript that contain all the given words (case and accents ignored), each with the line before and after it. Try the word as speech recognition may have written it, in Greek and in English.",
    parameters: obj({
      query: str({ description: "One or more words" }),
      max_results: opt(int({ minimum: 1, maximum: 50, description: "15 when omitted" })),
    }),
    replay: "safe",
    async execute(args) {
      const blocks = search(readSegments(state.folder), args.query, args.max_results ?? 15);
      return text(blocks.length === 0 ? `No line contains "${args.query}".` : blocks.join("\n--\n"));
    },
  });

  const attachment = defineTool({
    name: "read_attachment",
    description:
      "Look at one attachment of the meeting by its number (from meeting_overview or the transcript): a picture is shown to you; text, text files, PDF, Word (.docx, .doc, .rtf), Excel (.xlsx) and PowerPoint (.pptx) files are returned as text. " +
      "A long document comes in parts of 40 000 characters: read on with offset. A PDF of scanned pages has no text to return.",
    parameters: obj({
      id: int({ minimum: 1, description: "The attachment's number" }),
      offset: opt(int({ minimum: 0, description: "Where to read on in a long document, in characters (given at the end of the previous part)" })),
    }),
    replay: "safe",
    async execute(args) {
      const found = readAttachments(state.folder).find((a) => a.id === args.id);
      if (found === undefined) throw new Error(`there is no attachment #${args.id}`);
      const content = attachmentContent(state.folder, found);
      if (content.type === "unreadable") return text(`Attachment ${describeAttachment(found)} — ${content.reason}.`);
      if (content.type !== "image") {
        const whole =
          content.type === "text" ? content.text
          : content.type === "office" ? readOffice(content.path, { maxRowsPerSheet: MAX_SHEET_ROWS })
          : await host.extract(content.path);
        if (whole.trim() === "") return { output: [{ type: "text" as const, text: `Attachment ${describeAttachment(found)} has no text that can be read (a PDF of scanned pages, or an empty document).` }] };
        // Parts of MAX_TEXT_CHARS, not cut again by the general limit.
        return { output: [{ type: "text" as const, text: `Attachment ${describeAttachment(found)}:\n\n${textPage(whole, args.offset ?? 0)}` }] };
      }
      const prepared = await images.prepare(content.bytes, content.mimeType, DEFAULT_IMAGE_LIMITS);
      const image = prepared ?? { data: Buffer.from(content.bytes).toString("base64"), mimeType: content.mimeType };
      return {
        output: [
          { type: "text" as const, text: `Attachment ${describeAttachment(found)}:` },
          { type: "image" as const, data: image.data, mimeType: image.mimeType },
        ],
      };
    },
  });

  return defineExtension({
    name: "meeting",
    sections: [section("instructions-file", () => INSTRUCTIONS, { tag: false })],
    tools: [overview, read, find, attachment],
  });
}
