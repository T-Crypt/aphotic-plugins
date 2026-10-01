import { spawn, spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

// wire.sh records the absolute path to core's agent_hook.py in the shell's
// own state dir. It cannot live beside this file: wire.sh symlinks the
// plugin into ~/.config/opencode/plugins/, and both Node and Bun resolve
// import.meta.url to the link's *realpath*, which is this repo. A config
// written next to the link was therefore looked for in the repo, where it
// was never written, and only a hardcoded fallback to a core checkout at
// ~/Aphotic-Hypr kept it working -- on the one machine that has one.
//
// The state dir is where the shell already keeps every other agent-hook
// artefact, so nothing new is invented and the path is derivable from the
// environment alone.
function hookConfigPath() {
  const stateHome = process.env.XDG_STATE_HOME
    || path.join(os.homedir(), ".local", "state");
  return path.join(stateHome, "aphotic", "opencode-hook.json");
}

function resolveHookPath() {
  // Missing or invalid is fatal, not a fallback. A hook that cannot find
  // agent_hook.py spawns a nonexistent interpreter path once per event and
  // reports nothing at all, which reads as "no sessions running" forever.
  let config;
  try {
    config = JSON.parse(fs.readFileSync(hookConfigPath(), "utf8"));
  } catch (e) {
    throw new Error(
      "aphotic opencode hooks: cannot read " + hookConfigPath() +
      ". Run 'aphotic plugin enable opencode-hooks' to wire it."
    );
  }
  if (!config || typeof config.agentHookPy !== "string" || !config.agentHookPy)
    throw new Error(
      "aphotic opencode hooks: " + hookConfigPath() +
      " has no agentHookPy path. Run 'aphotic plugin enable opencode-hooks'."
    );
  return config.agentHookPy;
}

// Earliest OpenCode with the v2 plugin surface this plugin needs:
// default-export plugins, ctx.event.subscribe, ctx.tool.hook, and the
// session.* event set. Pinned to a version captures were verified
// against, not to a changelog claim.
const MIN_VERSION = "2.0.14";

function versionAtLeast(found, floor) {
  const parse = (v) => String(v || "").split(".").map((n) => parseInt(n, 10) || 0);
  const a = parse(found);
  const b = parse(floor);
  for (let i = 0; i < 3; i++) {
    if ((a[i] || 0) !== (b[i] || 0))
      return (a[i] || 0) > (b[i] || 0);
  }
  return true;
}

const TOOL_NAMES = {
  bash: "Bash",
  read: "Read",
  write: "Write",
  edit: "Edit",
  grep: "Grep",
  glob: "Glob",
  webfetch: "WebFetch",
  websearch: "WebSearch",
  task: "Task",
  todowrite: "TodoWrite",
  todoread: "TodoRead",
  patch: "Edit",
  shell: "Shell",
  execute: "Execute",
  subagent: "Subagent",
  question: "Question",
  skill: "Skill",
  browser: "Browser",
};

function normalizeTool(name) {
  if (!name)
    return null;
  const lower = String(name).toLowerCase();
  if (TOOL_NAMES[lower])
    return TOOL_NAMES[lower];
  return name.charAt(0).toUpperCase() + name.slice(1);
}

function modelString(model) {
  if (!model || !model.id)
    return null;
  return model.providerID ? model.providerID + "/" + model.id : model.id;
}

function finite(v) {
  return typeof v === "number" && Number.isFinite(v);
}

export default {
  id: "aphotic-opencode-hooks",
  setup(ctx) {
    if (!versionAtLeast(ctx && ctx.app && ctx.app.version, MIN_VERSION))
      return () => {};

    // A wiring problem is reported, not thrown. OpenCode loads plugins
    // during startup, so throwing here takes the whole editor down over a
    // config file the user can fix with one command. The console line is
    // the only place this can surface, so it names the exact command.
    let hookPath;
    try {
      hookPath = resolveHookPath();
    } catch (e) {
      console.error("[aphotic opencode hooks] " + e.message);
      return () => {};
    }
    let closed = false;

    // sessionID -> { model, emittedModel, child, agentType, lastUsage }
    const sessions = new Map();
    // tool call id -> { tool, t0, sessionID, done }
    const calls = new Map();

    function send(record, atMs = null) {
      if (closed)
        return;
      const now = atMs || Date.now();
      try {
        const child = spawn("python3", [hookPath], { stdio: ["pipe", "ignore", "ignore"] });
        child.on("error", () => {});
        child.stdin.on("error", () => {});
        child.stdin.write(JSON.stringify({
          v: 2,
          harness: "opencode",
          t: now,
          ts: new Date(now).toISOString(),
          ...record,
        }));
        child.stdin.end();
      } catch (e) {}
    }

    // A CLI one-shot (`opencode run`) exits within milliseconds of its
    // last event, too fast for an async spawn to land, so the shutdown
    // path writes synchronously.
    function sendSync(record, atMs = null) {
      const now = atMs || Date.now();
      try {
        spawnSync("python3", [hookPath], {
          input: JSON.stringify({
            v: 2,
            harness: "opencode",
            t: now,
            ts: new Date(now).toISOString(),
            ...record,
          }),
          stdio: ["pipe", "ignore", "ignore"],
        });
      } catch (e) {}
    }

    // The model rides any record when new or changed, never every line.
    function modelFields(sessionID) {
      const s = sessions.get(sessionID);
      const fields = {};
      if (!s || !s.model || s.model === s.emittedModel)
        return fields;
      fields.model = s.model;
      const slash = s.model.indexOf("/");
      if (slash > 0)
        fields.provider = s.model.slice(0, slash);
      s.emittedModel = s.model;
      return fields;
    }

    // A nested session carries its own identity so the readers can show
    // it as a subagent of its parent (session.created's parentID).
    function childFields(sessionID) {
      const s = sessions.get(sessionID);
      const fields = {};
      if (s && s.child) {
        fields.agentId = sessionID;
        if (s.agentType)
          fields.agentType = s.agentType;
      }
      return fields;
    }

    // cwd reaches the map late for sessions that started before the
    // plugin subscribed; it rides the next record once, like model.
    function contextFields(sessionID) {
      const s = sessions.get(sessionID);
      const fields = {};
      if (s && s.cwd && !s.cwdSent) {
        fields.cwd = s.cwd;
        s.cwdSent = true;
      }
      return fields;
    }

    function emitTurn(sessionID, status) {
      if (!sessionID)
        return;
      send({
        ...childFields(sessionID),
        ...contextFields(sessionID),
        ...modelFields(sessionID),
        sessionId: sessionID,
        event: "turn",
        status,
      });
    }

    function pruneCalls() {
      while (calls.size > 512) {
        const oldest = calls.keys().next().value;
        calls.delete(oldest);
      }
    }

    function noteCall(id, sessionID, tool) {
      if (!id)
        return;
      const known = calls.get(id);
      if (!known)
        calls.set(id, { tool: tool || null, t0: Date.now(), sessionID, done: false });
      else if (tool && !known.tool)
        known.tool = tool;
      pruneCalls();
    }

    function emitTool(id, sessionID, toolStatus, durationMs, extra = {}) {
      const call = calls.get(id);
      const sid = sessionID || (call && call.sessionID);
      if (!sid || !id)
        return;
      const record = {
        ...childFields(sid),
        sessionId: sid,
        event: "tool_call",
        status: "running",
        toolId: id,
        toolStatus,
      };
      const tool = normalizeTool(extra.tool || (call && call.tool));
      if (tool)
        record.tool = tool;
      if (finite(durationMs))
        record.durationMs = Math.max(0, Math.round(durationMs));
      if (extra.spawnedAgentId)
        record.spawnedAgentId = extra.spawnedAgentId;
      send(record);
    }

    // Bus events are the fallback when a tool hook does not fire; the
    // done flag makes whichever path lands first win.
    function finishCall(id, sessionID, toolStatus, atMs) {
      const call = calls.get(id);
      const sid = sessionID || (call && call.sessionID);
      if (!id || !sid || (call && call.done))
        return;
      if (call)
        call.done = true;
      else
        noteCall(id, sid, null);
      const durationMs = call && call.t0 && atMs ? Math.max(0, atMs - call.t0) : undefined;
      emitTool(id, sid, toolStatus, durationMs);
    }

    function emitUsage(sessionID, data, sendFn = send, atMs = null) {
      const tokens = data && data.tokens;
      if (!sessionID || !tokens || typeof tokens !== "object")
        return;
      const record = {
        ...childFields(sessionID),
        sessionId: sessionID,
        event: "usage",
        status: "running",
      };
      let found = false;
      if (finite(tokens.input)) { record.inputTokens = tokens.input; found = true; }
      if (finite(tokens.output)) { record.outputTokens = tokens.output; found = true; }
      if (finite(tokens.reasoning)) { record.reasoningTokens = tokens.reasoning; found = true; }
      if (tokens.cache && typeof tokens.cache === "object") {
        if (finite(tokens.cache.read)) { record.cacheReadTokens = tokens.cache.read; found = true; }
        if (finite(tokens.cache.write)) { record.cacheWriteTokens = tokens.cache.write; found = true; }
      }
      if (!found)
        return;
      if (finite(data.cost))
        record.cost = { amount: data.cost, currency: "USD" };
      // A usage record keeps the event's own timestamp so the shutdown
      // flush reproduces the identical line instead of a second count.
      sendFn(record, atMs);
    }

    function emitError(sessionID, kind, message) {
      if (!sessionID || !message)
        return;
      send({
        ...childFields(sessionID),
        sessionId: sessionID,
        event: "error",
        status: "idle",
        error: { kind: String(kind || "unknown"), message: String(message) },
      });
    }

    // A CLI one-shot creates its session before plugins get to subscribe,
    // so session.created never arrives: start the session lazily on the
    // first record-producing event instead, and wait a beat for the
    // session API so cwd, model and parentage land on the session_start
    // itself rather than never.
    const LAZY_TYPES = new Set([
      "session.step.started", "session.step.ended", "session.idle",
      "permission.asked", "permission.replied", "permission.rejected",
      "session.compaction.started", "session.compaction.ended", "session.compaction.failed",
      "session.error", "session.tool.success", "session.tool.failed",
    ]);

    function enrich(sessionID, done) {
      const apply = (info) => {
        const s = closed ? null : sessions.get(sessionID);
        if (s && info) {
          const cwd = info.directory || (info.location && info.location.directory);
          if (cwd)
            s.cwd = cwd;
          if (info.parentID) {
            s.child = true;
            if (info.agent)
              s.agentType = String(info.agent);
          }
          if (!s.model && info.model)
            s.model = modelString(info.model);
        }
      };
      let settled = false;
      const finish = () => {
        if (!settled) {
          settled = true;
          if (done)
            done();
        }
      };
      try {
        ctx.session.get({ sessionID }).then((info) => {
          apply(info);
          finish();
        }).catch(() => finish());
        setTimeout(finish, 250);
      } catch (e) {
        finish();
      }
    }

    function ensureSession(sessionID, type) {
      if (!sessionID || sessions.has(sessionID) || !LAZY_TYPES.has(type))
        return;
      sessions.set(sessionID, { model: null, emittedModel: null, child: false, agentType: null });
      send({ sessionId: sessionID, event: "session_start", status: "running" });
      enrich(sessionID, null);
    }

    // Synchronous tail for a process that is about to exit: the async
    // spawns in flight get killed by teardown, so the last known state
    // is written blocking, right here.
    function flushShutdown() {
      for (const [sessionID, s] of sessions) {
        sendSync({
          ...childFields(sessionID),
          ...contextFields(sessionID),
          ...modelFields(sessionID),
          sessionId: sessionID,
          event: "turn",
          status: "idle",
        });
        if (s.lastUsage)
          emitUsage(sessionID, s.lastUsage, sendSync, s.lastUsage.atMs);
      }
    }

    function handleEvent(event) {
      const type = event && event.type;
      const data = event && event.data;
      if (!type || !data || typeof data !== "object")
        return;
      const sessionID = data.sessionID || (data.info && data.info.id);
      ensureSession(sessionID, type);

      switch (type) {
        case "session.created": {
          if (!data.sessionID)
            return;
          const child = Boolean(data.parentID);
          const prev = sessions.get(data.sessionID);
          sessions.set(data.sessionID, {
            model: modelString(data.model) || (prev && prev.model) || null,
            emittedModel: prev ? prev.emittedModel : null,
            child,
            agentType: child ? String(data.agent || "subagent") : (prev ? prev.agentType : null),
            cwd: (data.location && data.location.directory)
              || (event.location && event.location.directory),
            cwdSent: true,
          });
          const record = {
            ...childFields(data.sessionID),
            ...modelFields(data.sessionID),
            sessionId: data.sessionID,
            event: "session_start",
            status: "running",
          };
          if (sessions.get(data.sessionID).cwd)
            record.cwd = sessions.get(data.sessionID).cwd;
          send(record);
          return;
        }

        case "session.model.selected": {
          const s = sessions.get(sessionID);
          if (s)
            s.model = modelString(data.model);
          return;
        }

        case "session.step.started": {
          const s = sessions.get(sessionID);
          if (s && !s.model && data.model)
            s.model = modelString(data.model);
          emitTurn(sessionID, "running");
          return;
        }

        // step.ended carries this step's own token delta and cost; the
        // last one is cached for the shutdown flush.
        case "session.step.ended": {
          const s = sessions.get(sessionID);
          if (s && data.tokens) {
            s.lastUsage = { cost: data.cost, tokens: data.tokens, atMs: event.created || null };
            emitUsage(sessionID, data, send, event.created || null);
          }
          emitTurn(sessionID, "idle");
          return;
        }

        case "session.idle":
          emitTurn(sessionID, "idle");
          return;

        case "permission.asked":
          if (sessionID)
            emitTurn(sessionID, "waiting");
          return;

        case "permission.replied":
        case "permission.rejected":
          if (sessionID)
            emitTurn(sessionID, "running");
          return;

        case "session.compaction.started":
          if (sessionID)
            emitTurn(sessionID, "compacting");
          return;

        case "session.compaction.ended":
          if (sessionID)
            emitTurn(sessionID, "running");
          return;

        case "session.compaction.failed":
          if (sessionID)
            emitTurn(sessionID, "running");
          emitError(sessionID, "compaction", data.error && data.error.message);
          return;

        case "session.error":
          emitError(sessionID, data.error && data.error.type, data.error && data.error.message);
          return;

        case "session.tool.called":
          noteCall(data.id, sessionID, null);
          return;

        case "session.tool.success":
          finishCall(data.id, sessionID, "completed", event.created);
          return;

        case "session.tool.failed":
          finishCall(data.id, sessionID, "errored", event.created);
          return;

        case "session.deleted":
          if (!sessionID)
            return;
          send({
            ...childFields(sessionID),
            sessionId: sessionID,
            event: "session_end",
            status: "ended",
            endReason: "deleted",
          });
          sessions.delete(sessionID);
          return;

        case "location.shutdown":
          flushShutdown();
          return;
      }
    }

    const events = ctx.event && ctx.event.subscribe ? ctx.event.subscribe() : null;
    if (events) {
      (async () => {
        try {
          for await (const event of events) {
            if (closed)
              break;
            handleEvent(event);
          }
        } catch (e) {}
      })();
    }

    try {
      ctx.tool.hook("execute.before", (input) => {
        if (!input || !input.id || !input.sessionID)
          return;
        noteCall(input.id, input.sessionID, input.tool);
        emitTool(input.id, input.sessionID, "running", 0, { tool: input.tool });
      });
    } catch (e) {}

    try {
      ctx.tool.hook("execute.after", (input) => {
        if (!input || !input.id || !input.sessionID)
          return;
        const failed = (input.status && input.status !== "completed") || input.error;
        const call = calls.get(input.id);
        const durationMs = call ? Math.max(0, Date.now() - call.t0) : 0;
        if (call)
          call.done = true;
        else
          noteCall(input.id, input.sessionID, input.tool);
        // The graph derives parentage from the spawn tool's own result,
        // which carries the child session id.
        const spawnedAgentId = !failed && input.tool === "subagent"
          && input.result && input.result.output ? input.result.output.sessionID : null;
        emitTool(input.id, input.sessionID, failed ? "errored" : "completed", durationMs, {
          tool: input.tool,
          spawnedAgentId,
        });
      });
    } catch (e) {}

    return () => {
      closed = true;
      try {
        if (events && typeof events.return === "function")
          events.return();
      } catch (e) {}
      // Whatever the plugin was still tracking when the process exits
      // gets a synchronous session_end; a hot reload self-heals the next
      // time any of those sessions emits.
      for (const sessionID of sessions.keys()) {
        sendSync({
          ...childFields(sessionID),
          ...contextFields(sessionID),
          ...modelFields(sessionID),
          sessionId: sessionID,
          event: "session_end",
          status: "ended",
          endReason: "exit",
        });
      }
      sessions.clear();
      calls.clear();
    };
  },
};
