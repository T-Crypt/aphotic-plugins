import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { fileURLToPath, pathToFileURL } from "node:url";


// A push channel standing in for ctx.event.subscribe(): the plugin
// consumes it with for-await, the test pushes OpenCode-shaped events in
// any order, and return() ends the loop the way the loader's cleanup
// would.
function eventChannel() {
  const queue = [];
  let wake = null;
  let done = false;
  const iterator = {
    async next() {
      while (!done) {
        if (queue.length)
          return { value: queue.shift(), done: false };
        await new Promise((resolve) => { wake = resolve; });
      }
      return { value: undefined, done: true };
    },
    async return() {
      done = true;
      if (wake) {
        const resolve = wake;
        wake = null;
        resolve();
      }
      return { value: undefined, done: true };
    },
    [Symbol.asyncIterator]() { return iterator; },
  };
  return {
    push(event) {
      queue.push(event);
      if (wake) {
        const resolve = wake;
        wake = null;
        resolve();
      }
    },
    subscribe: () => iterator,
  };
}


function envelope(type, data, created) {
  return { id: "evt_test", created: created ?? Date.now(), type, data };
}


async function waitForRecords(capturePath, count) {
  const deadline = Date.now() + 8000;
  let records = [];
  while (Date.now() < deadline) {
    if (fs.existsSync(capturePath)) {
      records = fs.readFileSync(capturePath, "utf8").trim().split("\n")
        .filter(Boolean).map(JSON.parse);
      if (records.length >= count)
        return records;
    }
    await new Promise((resolve) => setTimeout(resolve, 25));
  }
  return fs.existsSync(capturePath)
    ? fs.readFileSync(capturePath, "utf8").trim().split("\n").filter(Boolean).map(JSON.parse)
    : [];
}


function mockCtx(channel, version) {
  const handlers = {};
  return {
    app: { version: version ?? "2.0.14" },
    event: { subscribe: () => channel.subscribe() },
    tool: {
      hook: (name, fn) => { handlers[name] = fn; },
    },
    session: {
      get: ({ sessionID }) => Promise.resolve({ sessionID, directory: "/tmp/project" }),
    },
    handlers,
  };
}


async function loadHook(dir, tag) {
  const source = fileURLToPath(new URL("../hook/opencode_hook.js", import.meta.url));
  const modulePath = path.join(dir, `opencode_hook_${tag}.mjs`);
  fs.copyFileSync(source, modulePath);
  return import(`${pathToFileURL(modulePath).href}?${tag}`);
}


const STUB_WRITER = [
  "import os, pathlib, sys",
  "pathlib.Path(os.environ['CAPTURE_PATH']).open('a').write(sys.stdin.read() + '\\n')",
  "",
].join("\n");


test("maps the opencode v2 event stream onto contract records", async () => {
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), "opencode-hook-v2-"));
  const capturePath = path.join(temp, "capture.jsonl");
  fs.writeFileSync(path.join(temp, ".aphotic-hook-config.json"),
    JSON.stringify({ agentHookPy: path.join(temp, "agent_hook.py") }));
  fs.writeFileSync(path.join(temp, "agent_hook.py"), STUB_WRITER);
  process.env.CAPTURE_PATH = capturePath;

  const channel = eventChannel();
  const plugin = await loadHook(temp, "main");
  const ctx = mockCtx(channel);
  const cleanup = plugin.default.setup(ctx);

  // Lifecycle, model, cwd.
  channel.push(envelope("session.created", {
    sessionID: "ses_main",
    location: { directory: "/tmp/project" },
    model: { id: "agent", providerID: "local" },
  }));
  // Tool calls through the tool hooks.
  ctx.handlers["execute.before"]({ tool: "bash", sessionID: "ses_main", id: "t1", input: {} });
  ctx.handlers["execute.after"]({ tool: "bash", sessionID: "ses_main", id: "t1", status: "completed" });
  ctx.handlers["execute.after"]({
    tool: "subagent", sessionID: "ses_main", id: "t2", status: "completed",
    result: { output: { sessionID: "ses_spawned" } },
  });
  ctx.handlers["execute.after"]({
    tool: "bash", sessionID: "ses_main", id: "t3", status: "error", error: { message: "boom" },
  });
  // Tool outcome falling back to the bus, where the tool name is unknown.
  channel.push(envelope("session.tool.called", { sessionID: "ses_main", id: "t9" }));
  channel.push(envelope("session.tool.success", { sessionID: "ses_main", id: "t9" }, Date.now() + 40));
  // Turns and per-step usage.
  channel.push(envelope("session.step.started", { sessionID: "ses_main" }));
  channel.push(envelope("session.model.selected", {
    sessionID: "ses_main", model: { id: "glm", providerID: "z" },
  }));
  channel.push(envelope("session.step.started", { sessionID: "ses_main" }));
  channel.push(envelope("session.step.ended", {
    sessionID: "ses_main",
    cost: 0.014,
    tokens: { input: 100, output: 20, reasoning: 5, cache: { read: 30, write: 4 } },
  }));
  // Waiting, compaction, errors.
  channel.push(envelope("permission.asked", { sessionID: "ses_main" }));
  channel.push(envelope("permission.replied", { sessionID: "ses_main" }));
  channel.push(envelope("session.compaction.started", { sessionID: "ses_main" }));
  channel.push(envelope("session.compaction.ended", { sessionID: "ses_main" }));
  channel.push(envelope("session.error", {
    sessionID: "ses_main", error: { type: "api", message: "429 rate limited" },
  }));
  // A nested session carries its own identity.
  channel.push(envelope("session.created", {
    sessionID: "ses_kid",
    parentID: "ses_main",
    agent: "fast",
    location: { directory: "/tmp/project" },
    model: { id: "fast", providerID: "local" },
  }));
  channel.push(envelope("session.step.ended", {
    sessionID: "ses_kid",
    cost: 0,
    tokens: { input: 10, output: 2, reasoning: 0, cache: { read: 0, write: 0 } },
  }));
  channel.push(envelope("session.deleted", { sessionID: "ses_main" }));
  // Noise the plugin must ignore: streaming parts, app-level chatter,
  // event kinds from a future version.
  channel.push(envelope("session.text.delta", { sessionID: "ses_main", delta: "x" }));
  channel.push(envelope("session.reasoning.delta", { sessionID: "ses_main" }));
  channel.push(envelope("session.step.streamed", { sessionID: "ses_main" }));
  channel.push(envelope("provider.updated", {}));
  channel.push(envelope("message.part.updated", { sessionID: "ses_main" }));
  channel.push(envelope("session.future.event", { sessionID: "ses_main" }));

  const records = await waitForRecords(capturePath, 19);
  await new Promise((resolve) => setTimeout(resolve, 150));
  const all = fs.existsSync(capturePath)
    ? fs.readFileSync(capturePath, "utf8").trim().split("\n").filter(Boolean).map(JSON.parse)
    : [];

  assert.equal(all.length, 19, `expected 19 records, got ${all.length}: ${JSON.stringify(all, null, 1)}`);

  // Contract invariants on every record.
  const kinds = new Set();
  for (const record of all) {
    assert.equal(record.v, 2);
    assert.equal(record.harness, "opencode");
    assert.match(record.sessionId, /^ses_/);
    assert.equal(typeof record.t, "number");
    assert.match(record.ts, /Z$/);
    assert.ok(["session_start", "session_end", "turn", "tool_call", "usage", "error"].includes(record.event),
      `unexpected kind ${record.event}`);
    kinds.add(record.event);
  }
  assert.deepEqual([...kinds].sort(),
    ["error", "session_end", "session_start", "tool_call", "turn", "usage"]);

  const find = (fn) => all.find(fn);
  const ofKind = (event) => all.filter((r) => r.event === event);

  // Session start: cwd, model once, provider alongside it.
  const start = find((r) => r.event === "session_start" && r.sessionId === "ses_main");
  assert.equal(start.status, "running");
  assert.equal(start.cwd, "/tmp/project");
  assert.equal(start.model, "local/agent");
  assert.equal(start.provider, "local");
  assert.equal(all.filter((r) => r.model === "local/agent").length, 1, "model emitted once, not every line");

  // Tool records.
  const t1run = find((r) => r.toolId === "t1" && r.toolStatus === "running");
  assert.equal(t1run.tool, "Bash");
  assert.equal(t1run.durationMs, 0);
  const t1done = find((r) => r.toolId === "t1" && r.toolStatus === "completed");
  assert.ok(t1done.durationMs >= 0);
  const t2 = find((r) => r.toolId === "t2");
  assert.equal(t2.tool, "Subagent");
  assert.equal(t2.spawnedAgentId, "ses_spawned");
  const t3 = find((r) => r.toolId === "t3");
  assert.equal(t3.toolStatus, "errored");
  const t9 = find((r) => r.toolId === "t9");
  assert.equal(t9.toolStatus, "completed");
  assert.equal(t9.tool, undefined, "bus fallback has no tool name and must not invent one");
  assert.ok(t9.durationMs >= 0);

  // Turns: model rides the first record after the change, not every turn.
  const turns = ofKind("turn");
  assert.equal(turns.filter((r) => r.sessionId === "ses_main").length, 7);
  assert.ok(turns.some((r) => r.status === "running" && r.model === "z/glm" && r.provider === "z"));
  assert.equal(turns.filter((r) => r.model === "z/glm").length, 1);
  assert.ok(turns.some((r) => r.status === "waiting"));
  assert.ok(turns.some((r) => r.status === "compacting"));

  // Usage: per-step delta with the cost object.
  const usage = ofKind("usage");
  assert.equal(usage.length, 2);
  const mainUsage = usage.find((r) => r.sessionId === "ses_main");
  assert.equal(mainUsage.inputTokens, 100);
  assert.equal(mainUsage.outputTokens, 20);
  assert.equal(mainUsage.reasoningTokens, 5);
  assert.equal(mainUsage.cacheReadTokens, 30);
  assert.equal(mainUsage.cacheWriteTokens, 4);
  assert.deepEqual(mainUsage.cost, { amount: 0.014, currency: "USD" });

  // Error record.
  const error = find((r) => r.event === "error");
  assert.deepEqual(error.error, { kind: "api", message: "429 rate limited" });

  // Nested session: identity on every record, closed by its idle turn.
  const kidStart = find((r) => r.event === "session_start" && r.sessionId === "ses_kid");
  assert.equal(kidStart.agentId, "ses_kid");
  assert.equal(kidStart.agentType, "fast");
  const kidTurn = find((r) => r.event === "turn" && r.sessionId === "ses_kid");
  assert.equal(kidTurn.agentId, "ses_kid");
  const kidUsage = usage.find((r) => r.sessionId === "ses_kid");
  assert.equal(kidUsage.agentId, "ses_kid");

  // Session end.
  const end = find((r) => r.event === "session_end" && r.sessionId === "ses_main");
  assert.equal(end.status, "ended");
  assert.equal(end.endReason, "deleted");

  // A session the plugin never saw created (a CLI one-shot) starts lazily
  // on its first record-producing event, then enriches cwd via the
  // session API.
  channel.push(envelope("session.step.started", {
    sessionID: "ses_late", model: { id: "m2", providerID: "p2" },
  }));
  await new Promise((resolve) => setTimeout(resolve, 30));
  channel.push(envelope("session.step.ended", {
    sessionID: "ses_late", cost: 0.002,
    tokens: { input: 7, output: 3, reasoning: 0, cache: { read: 0, write: 0 } },
  }, 1790637329165));
  channel.push(envelope("location.shutdown", {}));
  await waitForRecords(capturePath, 27);
  await new Promise((resolve) => setTimeout(resolve, 150));
  const late = fs.readFileSync(capturePath, "utf8").trim().split("\n").filter(Boolean).map(JSON.parse);
  assert.equal(late.length, 27, `expected 27 records, got ${late.length}`);
  assert.ok(late.some((r) => r.event === "session_start" && r.sessionId === "ses_late"),
    "lazy session_start emitted");
  assert.ok(late.some((r) => r.sessionId === "ses_late" && r.cwd === "/tmp/project"),
    "enriched cwd rides a later record");
  const lateUsage = late.filter((r) => r.event === "usage" && r.sessionId === "ses_late");
  assert.equal(lateUsage.length, 2, "async usage plus the shutdown flush");
  assert.equal(lateUsage[0].t, lateUsage[1].t, "flush reproduces the same line, same t");
  assert.equal(lateUsage[0].inputTokens, 7);
  assert.equal(late.filter((r) => r.event === "turn" && r.sessionId === "ses_kid" && r.status === "idle").length, 2,
    "the kid session gets its shutdown flush too");

  cleanup();
  await new Promise((resolve) => setTimeout(resolve, 150));
  const final = fs.readFileSync(capturePath, "utf8").trim().split("\n").filter(Boolean).map(JSON.parse);
  assert.equal(final.length, 29, `expected 29 after cleanup, got ${final.length}`);
  const lateEnd = final.find((r) => r.event === "session_end" && r.sessionId === "ses_late");
  assert.equal(lateEnd.endReason, "exit");
  const kidEnd = final.find((r) => r.event === "session_end" && r.sessionId === "ses_kid");
  assert.equal(kidEnd.endReason, "exit");
});


test("stays silent below the version floor", async () => {
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), "opencode-hook-old-"));
  const capturePath = path.join(temp, "capture.jsonl");
  fs.writeFileSync(path.join(temp, ".aphotic-hook-config.json"),
    JSON.stringify({ agentHookPy: path.join(temp, "agent_hook.py") }));
  fs.writeFileSync(path.join(temp, "agent_hook.py"), STUB_WRITER);
  process.env.CAPTURE_PATH = capturePath;

  const channel = eventChannel();
  const plugin = await loadHook(temp, "old");
  const ctx = mockCtx(channel, "2.0.13");
  const cleanup = plugin.default.setup(ctx);
  channel.push(envelope("session.created", { sessionID: "ses_x", model: { id: "m", providerID: "p" } }));
  ctx.handlers["execute.before"]?.({ tool: "bash", sessionID: "ses_x", id: "t1" });

  await new Promise((resolve) => setTimeout(resolve, 300));
  assert.equal(fs.existsSync(capturePath), false, "no records below the floor");
  cleanup();
});
