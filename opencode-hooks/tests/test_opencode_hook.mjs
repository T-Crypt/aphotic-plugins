import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { fileURLToPath, pathToFileURL } from "node:url";


async function waitForRecords(capturePath, count) {
  const deadline = Date.now() + 3000;
  let records = [];
  while (Date.now() < deadline) {
    if (fs.existsSync(capturePath)) {
      records = fs.readFileSync(capturePath, "utf8").trim().split("\n").filter(Boolean).map(JSON.parse);
      if (records.length >= count)
        return records;
    }
    await new Promise(resolve => setTimeout(resolve, 20));
  }
  return records;
}


test("emits lifecycle, tool, model, and usage records as v2", async () => {
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), "opencode-hook-test-"));
  const capturePath = path.join(temp, "capture.jsonl");
  const writerPath = path.join(temp, "agent_hook.py");
  const modulePath = path.join(temp, "opencode_hook.mjs");
  const sourcePath = fileURLToPath(new URL("../hook/opencode_hook.js", import.meta.url));
  fs.copyFileSync(sourcePath, modulePath);
  fs.writeFileSync(writerPath,
    "import os, pathlib, sys\n" +
    "pathlib.Path(os.environ['CAPTURE_PATH']).open('a').write(sys.stdin.read() + '\\n')\n");
  fs.writeFileSync(path.join(temp, ".aphotic-hook-config.json"), JSON.stringify({ agentHookPy: writerPath }));
  process.env.CAPTURE_PATH = capturePath;

  const { AphoticAgentTracking } = await import(`${pathToFileURL(modulePath).href}?test=${Date.now()}`);
  const hooks = await AphoticAgentTracking({ directory: "/tmp/project" });
  await hooks.event({ event: { type: "session.created", properties: { info: { id: "s1", directory: "/tmp/project" } } } });
  await hooks["chat.params"]({ sessionID: "s1", model: { providerID: "anthropic", id: "claude-sonnet" } });
  await hooks["tool.execute.before"]({ sessionID: "s1", callID: "t1", tool: "bash" });
  await hooks["tool.execute.after"]({ sessionID: "s1", callID: "t1", tool: "bash" });
  await hooks.event({ event: { type: "message.updated", properties: { info: {
    role: "assistant",
    sessionID: "s1",
    tokens: { input: 120, output: 45, cache: { read: 80, write: 10 } },
  } } } });
  await hooks.event({ event: { type: "message.updated", properties: { info: { role: "user", sessionID: "s1", tokens: { input: 99 } } } } });
  await hooks.event({ event: { type: "message.updated", properties: { info: { role: "assistant", sessionID: "s1" } } } });
  await hooks.event({ event: { type: "session.idle", properties: { sessionID: "s1" } } });
  await hooks.event({ event: { type: "session.deleted", properties: { info: { id: "s1" } } } });

  const records = await waitForRecords(capturePath, 7);
  assert.equal(records.length, 7);
  for (const record of records) {
    assert.equal(record.v, 2);
    assert.equal(record.harness, "opencode");
    assert.equal(record.sessionId, "s1");
    assert.equal(typeof record.t, "number");
    assert.match(record.ts, /Z$/);
  }

  assert.ok(records.some(record => record.event === "session_start" && record.status === "running" && record.cwd === "/tmp/project"));
  assert.ok(records.some(record => record.event === "session_start" && record.model === "anthropic/claude-sonnet" && record.provider === "anthropic"));
  assert.ok(records.some(record => record.event === "tool_call" && record.toolStatus === "running" && record.tool === "Bash" && record.toolId === "t1"));
  assert.ok(records.some(record => record.event === "tool_call" && record.toolStatus === "completed" && record.durationMs >= 0));
  assert.ok(records.some(record => record.event === "turn" && record.status === "idle"));
  assert.ok(records.some(record => record.event === "session_end" && record.status === "ended"));
  assert.ok(records.some(record => record.event === "usage" && record.inputTokens === 120 && record.outputTokens === 45 && record.cacheReadTokens === 80 && record.cacheWriteTokens === 10));

  await new Promise(resolve => setTimeout(resolve, 100));
  assert.equal(fs.readFileSync(capturePath, "utf8").trim().split("\n").filter(Boolean).length, 7);
});
