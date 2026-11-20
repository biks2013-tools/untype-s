#!/usr/bin/env node
import { mkdirSync } from "node:fs";
import { basename, join } from "node:path";
import { createInterface } from "node:readline";
import { BACKGROUND_CONTEXT } from "@earendil-works/chord/context";
import { builtinModels } from "@earendil-works/pi-ai/providers/all";
import { createRegistry, defineDoc, Harness, LiveDoc, type Conversation, type ConversationId, type ConversationView, type EntryRecord, type LiveState } from "@earendil-works/pi-durable";
import { createNodePhotonImages } from "@earendil-works/pi-durable/images/node";
import { openNodeSqliteStorage } from "@earendil-works/pi-durable/storage/sqlite/node";
import { meetingExtension, meetingNow, type DocumentHost, type MeetingState } from "./extension.js";

/**
 * untype's meeting assistant, run by untype.app as a helper process.
 *
 *   main.js catalog   prints the model providers and their models as JSON, and exits
 *   main.js serve     JSON lines on stdin (requests) and stdout (events); logs on stderr
 *                     (one event asks untype for something: `extract {id, path}`, answered by the request
 *                     `extracted {id, text}` or `extracted {id, error}`)
 *
 * Settings come from the environment untype gives it, none has a default:
 *   UNTYPE_AGENT_HOME          where the conversations are kept (SQLite)
 *   UNTYPE_AGENT_LLM_PROVIDER  a provider of the pi-ai catalog (azure, openai, anthropic, google, deepseek, …)
 *   UNTYPE_AGENT_LLM_MODEL     a model of that provider
 * and the provider's own variables (its API key and, for Azure, AZURE_OPENAI_BASE_URL or AZURE_OPENAI_RESOURCE_NAME).
 */

const ctx = BACKGROUND_CONTEXT;
/** How many minutes of transcript go along with every question. */
const RECENT_MINUTES = 3;
/** How long untype may take to read a document for the assistant. */
const EXTRACT_TIMEOUT_MS = 60_000;

/** Which conversation belongs to which recording (its stem, `recording-yyyy-MM-dd-HH-mm`, and folder date). */
const MeetingsDoc = defineDoc<{ meetings: { [key: string]: number } }>({
  kind: "app.meetings",
  version: 1,
  scope: "session",
  initial: () => ({ meetings: {} }),
  checkpointWhen: (_v, _ops, info) => info.deltasSinceBase >= 100,
});

function emit(event: Record<string, unknown>): void {
  process.stdout.write(`${JSON.stringify(event)}\n`);
}

function log(message: string): void {
  process.stderr.write(`${new Date().toISOString()} ${message}\n`);
}

function required(name: string): string {
  const value = process.env[name];
  if (value === undefined || value.trim() === "") throw new Error(`${name} is not set`);
  return value.trim();
}

/** untype's own variables, in the form pi-ai's providers read them. */
function adaptEnvironment(): void {
  // untype keeps the Google key as GOOGLE_API_KEY; pi-ai's google provider reads GEMINI_API_KEY.
  if (process.env.GOOGLE_API_KEY && !process.env.GEMINI_API_KEY) process.env.GEMINI_API_KEY = process.env.GOOGLE_API_KEY;
  // untype's AZURE_OPENAI_API_VERSION is a dated version of the Chat Completions API. pi-ai calls the Responses
  // API of the same resource, whose version is "v1": the dated one is refused there ("API version not supported").
  delete process.env.AZURE_OPENAI_API_VERSION;
}

async function catalog(): Promise<void> {
  adaptEnvironment();
  const models = builtinModels();
  const providers = await Promise.all(
    models.getProviders().map(async (p) => ({
      id: p.id,
      name: p.name,
      configured: await models.checkAuth(p.id).then(Boolean, () => false),
      models: models.getModels(p.id).map((m) => ({ id: m.id, name: m.name })),
    })),
  );
  process.stdout.write(`${JSON.stringify({ providers: providers.filter((p) => p.models.length > 0) })}\n`);
}

function messageText(message: unknown): string {
  const content = (message as { content?: unknown } | undefined)?.content;
  if (!Array.isArray(content)) return "";
  let text = "";
  for (const block of content) {
    if (block && typeof block === "object" && (block as { type?: unknown }).type === "text") {
      const t = (block as { text?: unknown }).text;
      if (typeof t === "string") text += t;
    }
  }
  return text;
}

interface HistoryItem {
  readonly role: "user" | "assistant";
  readonly text: string;
}

function historyFrom(entries: readonly EntryRecord[]): HistoryItem[] {
  const items: HistoryItem[] = [];
  for (const e of entries) {
    if (e.kind === "app.question") {
      const data = (e.data ?? {}) as { text?: unknown };
      items.push({ role: "user", text: typeof data.text === "string" ? data.text : "" });
    } else if (e.kind === "pi.assistant") {
      const text = messageText(e.model?.[0]);
      if (text.trim() !== "") items.push({ role: "assistant", text });
    }
  }
  return items;
}

/** Turns successive views of the conversation into events: the run starting, tools, answer text, the run ending. */
class LiveTracker {
  private running = false;
  private readonly seenCalls = new Set<string>();
  private streamed = "";

  update(view: ConversationView): void {
    const live = view.docs[LiveDoc.definition.kind] as LiveState | undefined;
    const running = live?.run !== undefined;
    if (running && !this.running) {
      this.seenCalls.clear();
      emit({ type: "run_start" });
    }
    for (const slot of live?.tools ?? []) {
      if (slot.status === "pending" || this.seenCalls.has(slot.callId)) continue;
      this.seenCalls.add(slot.callId);
      emit({ type: "tool", name: slot.name });
    }
    const current = messageText(live?.generation?.message);
    if (current !== this.streamed) {
      // A new model turn starts its text again: the window then replaces what it showed.
      if (current.startsWith(this.streamed)) emit({ type: "text", delta: current.slice(this.streamed.length) });
      else if (current !== "") emit({ type: "text", reset: true, delta: current });
      this.streamed = current;
    }
    if (!running && this.running) {
      this.streamed = "";
      const failure = live?.runFailure;
      emit({ type: "run_end", ...(failure ? { failure: `${failure.reason.replace(/_/g, " ")}${failure.detail ? `: ${failure.detail}` : ""}` } : {}) });
    }
    this.running = running;
  }
}

async function serve(): Promise<void> {
  const home = required("UNTYPE_AGENT_HOME");
  const provider = required("UNTYPE_AGENT_LLM_PROVIDER");
  const modelId = required("UNTYPE_AGENT_LLM_MODEL");
  adaptEnvironment();
  const models = builtinModels();
  if (!models.getModel(provider, modelId)) throw new Error(`the assistant's model ${provider}/${modelId} is not one the assistant knows (Settings → Assistant)`);
  if (!(await models.checkAuth(provider))) throw new Error(`there is no API key for the assistant's provider "${provider}" (Settings → API keys)`);

  mkdirSync(home, { recursive: true, mode: 0o700 });
  const state: MeetingState = { folder: "", recording: false };
  // Documents untype reads for the assistant: asked with an `extract` event, answered with an `extracted` request.
  const extractions = new Map<string, { resolve(text: string): void; reject(error: Error): void; timer: NodeJS.Timeout }>();
  let extractionNumber = 0;
  const host: DocumentHost = {
    extract: (path) =>
      new Promise<string>((resolve, reject) => {
        const id = `x${++extractionNumber}`;
        const timer = setTimeout(() => {
          extractions.delete(id);
          reject(new Error("untype did not read the document in time"));
        }, EXTRACT_TIMEOUT_MS);
        extractions.set(id, { resolve, reject, timer });
        emit({ type: "extract", id, path });
      }),
  };
  const registry = createRegistry();
  registry.install(meetingExtension(state, await createNodePhotonImages(), host));
  const storage = await openNodeSqliteStorage(join(home, "state.sqlite"));
  const harness = await Harness.open(
    storage,
    {
      models,
      registry,
      settings: { toolExecution: "parallel" },
      onReport: (report) => log(`harness report: ${report.kind}${"error" in report ? ` ${String(report.error)}` : ""}`),
    },
    ctx,
  );

  let conversation: Conversation | undefined;
  let stopWatch: (() => Promise<void>) | undefined;

  async function open(folder: string, key: string, recording: boolean): Promise<void> {
    if (conversation !== undefined) await conversation.abort(ctx).catch(() => undefined);
    await stopWatch?.();
    state.folder = folder;
    state.recording = recording;
    const known = (await harness.snapshot(MeetingsDoc, ctx))?.meetings[key];
    let found = known === undefined ? undefined : await harness.conversation(known as ConversationId, ctx);
    if (found === undefined) {
      found = await harness.createConversation({ ownership: { kind: "ownerless" }, agent: { model: { provider, modelId } } }, ctx);
      const id = found.id;
      await harness.commit(async (tx) => {
        (await tx.doc(MeetingsDoc)).meetings[key] = id;
      }, ctx);
    } else {
      // The model chosen in Settings now, also for a meeting first asked about with another one.
      await found.configure({ model: { provider, modelId } }, ctx);
    }
    conversation = found;
    const tracker = new LiveTracker();
    const watch = await found.watch(ctx, { min: 1 });
    watch.start(async (call) => {
      if (call.kind === "value") tracker.update(call.value);
    });
    stopWatch = async () => {
      await watch.stop();
    };
    const page = await found.entries({ order: "descending" }, 300, undefined, ctx);
    emit({ type: "opened", key, name: basename(folder), history: historyFrom([...page.items].reverse()) });
  }

  async function handle(request: Record<string, unknown>): Promise<void> {
    switch (request.type) {
      case "open": {
        if (typeof request.folder !== "string" || typeof request.key !== "string") throw new Error("open needs folder and key");
        await open(request.folder, request.key, request.recording === true);
        return;
      }
      case "meeting": {
        // The folder was renamed, or the recording ended.
        if (typeof request.folder === "string") state.folder = request.folder;
        if (typeof request.recording === "boolean") state.recording = request.recording;
        return;
      }
      case "ask": {
        if (conversation === undefined) throw new Error("no meeting is open");
        const text = typeof request.text === "string" ? request.text.trim() : "";
        if (text === "") throw new Error("the question is empty");
        const id = typeof request.id === "string" ? request.id : `${Date.now()}`;
        await conversation.submit(
          {
            type: "input",
            content: `${text}\n\n<meeting-now>\n${meetingNow(state, RECENT_MINUTES)}\n</meeting-now>`,
            requestId: `untype:${id}`,
            whenBusy: "steer",
            entry: { kind: "app.question", data: { text } },
          },
          ctx,
        );
        return;
      }
      case "extracted": {
        const waiting = typeof request.id === "string" ? extractions.get(request.id) : undefined;
        if (waiting === undefined) return;
        extractions.delete(request.id as string);
        clearTimeout(waiting.timer);
        if (typeof request.error === "string") waiting.reject(new Error(request.error));
        else waiting.resolve(typeof request.text === "string" ? request.text : "");
        return;
      }
      case "abort": {
        await conversation?.abort(ctx);
        return;
      }
      default:
        throw new Error(`unknown request: ${String(request.type)}`);
    }
  }

  void harness.closed.then((end) => {
    log(`harness closed: ${end.kind}`);
    process.exit(end.kind === "closed" ? 0 : 1);
  });

  emit({ type: "ready", provider, model: modelId });
  // One request at a time, in the order they came.
  let queue: Promise<void> = Promise.resolve();
  const lines = createInterface({ input: process.stdin });
  lines.on("line", (line) => {
    if (line.trim() === "") return;
    queue = queue.then(async () => {
      try {
        await handle(JSON.parse(line) as Record<string, unknown>);
      } catch (error) {
        emit({ type: "error", message: error instanceof Error ? error.message : String(error) });
      }
    });
  });
  lines.on("close", () => {
    // untype closed the pipe (it quit, or restarts the assistant): unfinished work stays stored.
    void queue.then(() => harness.close(ctx)).finally(() => process.exit(0));
  });
}

const command = process.argv[2];
(command === "catalog" ? catalog() : command === "serve" ? serve() : Promise.reject(new Error("usage: main.js catalog | serve"))).catch((error: unknown) => {
  emit({ type: "fatal", message: error instanceof Error ? error.message : String(error) });
  process.exitCode = 1;
});
