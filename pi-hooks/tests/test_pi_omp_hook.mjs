import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { fileURLToPath, pathToFileURL } from "node:url";

// Drives the real pi_omp_hook.js against a mock `pi.on(...)` API and a
// stub standing in for core's agent_hook.py: the stub appends every
// record it receives on stdin to a capture file, exactly like the
// writer's three-sink shape reduced to one sink. Runtime payloads are
// the field shapes Pi 1.0.0 and OMP 18.5.1 actually emit (recorded
// with a probe extension on this machine).
//
// Run with `node --test pi-hooks/tests/test_pi_omp_hook.mjs` or plain
// `node pi-hooks/tests/test_pi_omp_hook.mjs`.

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ADAPTER = path.resolve(HERE, "..", "hook", "pi_omp_hook.js");

const SID = "01test-sid-0000-0000-000000000000";

const STUB_WRITER = `
import json, os, sys
data = sys.stdin.read()
record = json.loads(data)
with open(os.environ["STUB_CAPTURE"], "a") as fh:
    fh.write(json.dumps(record) + "\\n")
`;

function makeEnv() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "pi-hooks-test-"));
  const capture = path.join(dir, "records.jsonl");
  const stub = path.join(dir, "stub_writer.py");
  fs.writeFileSync(stub, STUB_WRITER);
  // The adapter reads $XDG_STATE_HOME/aphotic/pi-hook.json, the same
  // layout wire.sh writes (and the same reason the config lives in the
  // shell's state dir rather than beside the symlinked adapter).
  const state = path.join(dir, "state", "aphotic");
  fs.mkdirSync(state, { recursive: true });
  fs.writeFileSync(path.join(state, "pi-hook.json"),
    JSON.stringify({ agentHookPy: stub }));
  process.env.XDG_STATE_HOME = path.join(dir, "state");
  process.env.STUB_CAPTURE = capture;
  delete process.env.PI_CODING_AGENT;
  return { dir, capture, stub };
}

function mockPi() {
  const handlers = {};
  const api = {
    on(event, fn) {
      handlers[event] = handlers[event] || [];
      handlers[event].push(fn);
      return () => {};
    },
  };
  return {
    api,
    handlers,
    fire(event, payload, ctx) {
      for (const fn of handlers[event] || [])
        fn(payload, ctx);
    },
  };
}

function makeCtx(overrides = {}) {
  return {
    cwd: "/tmp/proj",
    mode: "tui",
    model: { id: "NInfer-Test-1B", provider: "llama-swap" },
    agent: null,
    sessionManager: { getSessionId: () => SID },
    getContextUsage: () => ({ tokens: 1000, contextWindow: 100000, percent: 1.0 }),
    ...overrides,
  };
}

async function waitForRecords(capture, count) {
  const deadline = Date.now() + 8000;
  let records = [];
  while (Date.now() < deadline) {
    if (fs.existsSync(capture)) {
      records = fs.readFileSync(capture, "utf8").trim().split("\n")
        .filter(Boolean).map(JSON.parse);
      if (records.length >= count)
        return records;
    }
    await new Promise((resolve) => setTimeout(resolve, 25));
  }
  return fs.existsSync(capture)
    ? fs.readFileSync(capture, "utf8").trim().split("\n").filter(Boolean).map(JSON.parse)
    : [];
}

function byEvent(records, event) {
  return records.filter((r) => r.event === event);
}

test("pi: full lifecycle, one usage source, no double count", async () => {
  const env = makeEnv();
  const adapter = await import(fileURLToPath(pathToFileURL(ADAPTER)) + "?pi");
  const pi = mockPi();
  adapter.default(pi.api);

  assert.ok(pi.handlers.session_start, "session_start registered");
  assert.ok(pi.handlers.message_end, "pi reads usage off message_end");
  assert.ok(!pi.handlers.assistant_message, "pi does not double-read assistant_message");
  assert.ok(pi.handlers.agent_settled, "pi takes idle from agent_settled");

  const ctx = makeCtx();
  pi.fire("session_start", {}, ctx);
  pi.fire("before_agent_start", {}, ctx);
  pi.fire("turn_start", {}, ctx);
  pi.fire("tool_call", { toolName: "bash", toolCallId: "call_1" }, ctx);
  pi.fire("tool_result", { toolName: "bash", toolCallId: "call_1", isError: false }, ctx);
  // A non-assistant message_end must not produce a usage record.
  pi.fire("message_end", { message: { role: "toolResult", usage: { input: 9, output: 9 } } }, ctx);
  pi.fire("message_end", {
    message: {
      role: "assistant",
      model: "NInfer-Test-1B",
      provider: "llama-swap",
      usage: { input: 100, output: 10, cacheRead: 5, cacheWrite: 2, totalTokens: 117,
               cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 } },
    },
  }, ctx);
  pi.fire("turn_end", {}, ctx);
  pi.fire("agent_settled", {}, ctx);
  pi.fire("session_shutdown", {}, ctx);

  // session_start, its quota, two turn-running, two tool, one usage,
  // turn_end quota, idle, idle quota, session_end.
  const records = await waitForRecords(env.capture, 10);
  for (const r of records) {
    assert.equal(r.v, 2);
    assert.equal(r.harness, "pi");
    assert.equal(r.sessionId, SID);
    assert.ok(typeof r.t === "number");
  }

  const starts = byEvent(records, "session_start");
  assert.equal(starts.length, 1);
  assert.equal(starts[0].status, "running");
  assert.equal(starts[0].cwd, "/tmp/proj");
  assert.equal(starts[0].model, "NInfer-Test-1B");
  assert.equal(starts[0].provider, "llama-swap");

  const turns = byEvent(records, "turn");
  assert.ok(turns.filter((r) => r.status === "running").length >= 2,
            "prompt and turn start both report running");
  assert.ok(turns.some((r) => r.status === "idle"), "agent_settled folds to turn idle");

  const tools = byEvent(records, "tool_call");
  assert.equal(tools.length, 2);
  // Arrivals are async; the pair is one start and one finish.
  assert.deepEqual(tools.map((r) => r.toolStatus).sort(), ["completed", "running"]);
  assert.ok(tools.every((r) => r.tool === "bash" && r.toolId === "call_1"));

  const usage = byEvent(records, "usage");
  assert.equal(usage.length, 1, "exactly one usage record per assistant response");
  assert.equal(usage[0].inputTokens, 100);
  assert.equal(usage[0].outputTokens, 10);
  assert.equal(usage[0].cacheReadTokens, 5);
  assert.equal(usage[0].cacheWriteTokens, 2);
  assert.equal(usage[0].cost, undefined, "zero cost is no price, not free");
  assert.equal(usage[0].model, "NInfer-Test-1B");
  assert.equal(usage[0].provider, "llama-swap");

  const quota = byEvent(records, "quota");
  assert.ok(quota.length >= 1);
  assert.ok(quota[0].quota.context, "context window present on both runtimes");
  assert.equal(quota[0].quota.context.usedPercent, 1);
  assert.equal(quota[0].quota.context.resetsAt, 0);

  const ends = byEvent(records, "session_end");
  assert.equal(ends.length, 1);
  assert.equal(ends[0].status, "ended");
  assert.equal(ends[0].endReason, "shutdown");
});

test("omp: assistant_message is the single usage source; session_stop idle off the remembered id", async () => {
  const env = makeEnv();
  const adapter = await import(fileURLToPath(pathToFileURL(ADAPTER)) + "?omp");
  const pi = mockPi();
  // Harness detection happens in the factory, so the OMP argv marker
  // must be in place for the factory call, not just the import.
  const savedArgv1 = process.argv[1];
  process.argv[1] = "omp-linux-x64";
  try {
    adapter.default(pi.api);

    assert.ok(pi.handlers.assistant_message, "omp reads usage off assistant_message");
    assert.ok(pi.handlers.session_stop, "omp takes idle from session_stop");

  const ctx = makeCtx({ model: { id: "omp-model", provider: "anthropic" } });
  pi.fire("session_start", {}, ctx);
  pi.fire("assistant_message", {
    message: {
      role: "assistant",
      model: "omp-model",
      provider: "anthropic",
      usage: { input: 500, output: 50, reasoningTokens: 8, cacheRead: 0, cacheWrite: 0,
               totalTokens: 558, cost: { input: 0.004, output: 0.001, cacheRead: 0, cacheWrite: 0, total: 0.005 } },
    },
  }, ctx);
  // The same response also fires message_end on OMP: no second count.
  pi.fire("message_end", {
    message: {
      role: "assistant",
      model: "omp-model",
      provider: "anthropic",
      usage: { input: 500, output: 50, reasoningTokens: 8, totalTokens: 558 },
    },
  }, ctx);
  // session_stop arrives with a bare context: no sessionManager at all.
  pi.fire("session_stop", {}, {});

  // session_start, its quota, one usage, idle, idle quota.
  const records = await waitForRecords(env.capture, 5);
  for (const r of records)
    assert.equal(r.harness, "omp");

  const usage = records.filter((r) => r.event === "usage");
  assert.equal(usage.length, 1, "message_end for the same response does not double count");
  assert.equal(usage[0].reasoningTokens, 8);
  assert.deepEqual(usage[0].cost, { amount: 0.005, currency: "USD" });

  const idle = records.filter((r) => r.event === "turn" && r.status === "idle");
  assert.equal(idle.length, 1, "session_stop folds to turn idle");
  assert.equal(idle[0].sessionId, SID, "the remembered session id stands in for the bare context");
  } finally {
    process.argv[1] = savedArgv1;
  }
});

test("subagent records carry agentId and agentType", async () => {
  const env = makeEnv();
  const adapter = await import(fileURLToPath(pathToFileURL(ADAPTER)) + "?sub");
  const pi = mockPi();
  adapter.default(pi.api);

  const ctx = makeCtx({ agent: { kind: "sub", id: "worker-1", name: "explore", depth: 1 } });
  pi.fire("session_start", {}, ctx);
  pi.fire("tool_call", { toolName: "read", toolCallId: "call_s" }, ctx);

  const records = await waitForRecords(env.capture, 2);
  for (const r of records) {
    assert.equal(r.agentId, "worker-1");
    assert.equal(r.agentType, "explore");
  }
});

test("main-session records never carry subagent identity", async () => {
  const env = makeEnv();
  const adapter = await import(fileURLToPath(pathToFileURL(ADAPTER)) + "?main");
  const pi = mockPi();
  adapter.default(pi.api);

  const ctx = makeCtx({ agent: { kind: "main", id: "Main", name: "main", depth: 0 } });
  pi.fire("session_start", {}, ctx);
  const records = await waitForRecords(env.capture, 1);
  assert.equal(records[0].agentId, undefined);
});

test("missing config: reports once, registers nothing, never throws", async () => {
  const env = makeEnv();
  fs.rmSync(path.join(env.dir, "state", "aphotic", "pi-hook.json"));
  const adapter = await import(fileURLToPath(pathToFileURL(ADAPTER)) + "?nocfg");
  const pi = mockPi();
  let error = null;
  try {
    adapter.default(pi.api);
  } catch (e) {
    error = e;
  }
  assert.equal(error, null, "a wiring problem must not throw from the factory");
  assert.equal(Object.keys(pi.handlers).length, 0, "no handlers without a writer path");
});

test("events without any session id produce no records", async () => {
  const env = makeEnv();
  const adapter = await import(fileURLToPath(pathToFileURL(ADAPTER)) + "?nosid");
  const pi = mockPi();
  adapter.default(pi.api);

  const ctx = makeCtx({ sessionManager: { getSessionId: () => null } });
  pi.fire("tool_call", { toolName: "bash", toolCallId: "call_x" }, ctx);
  await new Promise((resolve) => setTimeout(resolve, 150));
  assert.ok(!fs.existsSync(env.capture), "sessionId is required; nothing is written");
});

test("model change rides the next record once", async () => {
  const env = makeEnv();
  const adapter = await import(fileURLToPath(pathToFileURL(ADAPTER)) + "?model");
  const pi = mockPi();
  adapter.default(pi.api);

  const ctx = makeCtx();
  pi.fire("session_start", {}, ctx);
  pi.fire("turn_start", {}, ctx);
  const records = await waitForRecords(env.capture, 3);
  const start = records.find((r) => r.event === "session_start");
  assert.equal(start.model, "NInfer-Test-1B");
  assert.ok(!records.filter((r) => r.event === "turn").some((r) => r.model),
            "unchanged model is not re-sent");

  const switched = makeCtx({ model: { id: "other-model", provider: "llama-swap" } });
  pi.fire("turn_start", {}, switched);
  pi.fire("turn_start", {}, switched);
  const records2 = await waitForRecords(env.capture, 5);
  const turns = records2.filter((r) => r.event === "turn");
  // The spawns land asynchronously, so index nothing: across the three
  // turn records the changed model rides exactly one line, and the old
  // model is never re-sent after it.
  assert.equal(turns.filter((r) => r.model === "other-model").length, 1,
               "the change rides exactly one record");
  assert.ok(!turns.some((r) => r.model === "NInfer-Test-1B"), "the old model is not re-sent");
});

test("windowKey maps canonical provider windows and slugs the rest", () => {
  // The tile renders fiveHour/sevenDay/context and nothing else, so a
  // wrong mapping draws a bar with the wrong label; pin the table.
  const source = fs.readFileSync(ADAPTER, "utf8");
  const start = source.indexOf("function windowKey");
  const end = source.indexOf("\n}", start) + 2;
  const windowKey = new Function(`${source.slice(start, end)}; return windowKey;`)();
  assert.equal(windowKey("5 Hour"), "fiveHour");
  assert.equal(windowKey("7 Day"), "sevenDay");
  assert.equal(windowKey("5h"), "fiveHour");
  assert.equal(windowKey("Kimi 1h Plan"), "kimi1hplan");
  assert.equal(windowKey(""), "");
});
