import { spawn, spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

// wire.sh records the absolute path to core's agent_hook.py in the shell's
// own state dir. It cannot live beside this file: wire.sh symlinks the
// adapter into the harness discovery dirs, and both runtimes resolve the
// module's own location to the link's *realpath*, which is this repo. A
// config written next to the link was never found (the OpenCode hook hit
// exactly this); the state dir is where the shell keeps every other
// agent-hook artefact and is derivable from the environment alone.
function hookConfigPath() {
  const stateHome = process.env.XDG_STATE_HOME || path.join(os.homedir(), ".local", "state");
  return path.join(stateHome, "aphotic", "pi-hook.json");
}

function resolveHookPath() {
  // Missing or invalid is fatal for this plugin, not for the harness: the
  // factory reports it once and goes quiet rather than spawning a
  // nonexistent interpreter path per event.
  let config;
  try {
    config = JSON.parse(fs.readFileSync(hookConfigPath(), "utf8"));
  } catch (e) {
    throw new Error(
      "aphotic pi hooks: " + hookConfigPath() +
      " not found or unreadable. Run 'aphotic plugin enable pi-hooks'."
    );
  }
  if (!config || typeof config.agentHookPy !== "string" || !config.agentHookPy)
    throw new Error(
      "aphotic pi hooks: " + hookConfigPath() +
      " has no agentHookPy path. Run 'aphotic plugin enable pi-hooks'."
    );
  return config.agentHookPy;
}

// One adapter file serves both harnesses: Pi and Oh My Pi (OMP) are the
// same pi-mono lineage and share the `pi.on(...)` extension API, but a
// record's `harness` field must name which runtime actually ran the
// session, so the tile's per-harness usage and quota never mix.
//
// OMP is a native binary that loads extensions in an embedded Bun:
// argv is `["bun", "/$bunfs/root/omp-linux-x64", ...]` and execPath is
// the omp binary itself. Pi is a plain Node process whose argv[1] is the
// pi cli, and it exports PI_CODING_AGENT=true (OMP does not).
function detectHarness() {
  const argv = Array.isArray(process.argv) ? process.argv.join(" ") : "";
  const exe = process.execPath || "";
  if (/oh-my-pi|omp-linux|bunfs/.test(argv) || /(^|\/)omp$/.test(exe))
    return "omp";
  if (
    process.env.PI_CODING_AGENT === "true" ||
    /@earendil-works|pi-coding-agent/.test(argv) ||
    /(^|\/)pi$/.test(exe)
  )
    return "pi";
  // Neither marker matched. Everything this file can run under is a pi
  // runtime; OMP always presents one of the markers above.
  return "pi";
}

// bun:sqlite is OMP's runtime (embedded Bun); Pi runs on Node, where the
// module does not exist. Load it eagerly and forget failures: a static
// import would make the module un-loadable on Node, and providerWindows
// below simply finds nothing when it never resolved.
let sqliteModule = null;
try {
  import("bun:sqlite").then((m) => {
    sqliteModule = m;
  }).catch(() => {});
} catch (e) {}

// window_label (or limit_id) -> the canonical quota key readers render.
// "5 Hour"/"7 Day" are the Anthropic windows OMP's usage report carries;
// anything else keeps a slug so a reader that knows the name can still
// use it. Unknown windows are never mapped to a known key: a wrong key
// would draw a bar labelled with someone else's number.
function windowKey(label) {
  const raw = String(label || "").trim().toLowerCase();
  if (raw === "5 hour" || raw === "5h" || raw === "five_hour")
    return "fiveHour";
  if (raw === "7 day" || raw === "7d" || raw === "seven_day")
    return "sevenDay";
  return raw.replace(/[^a-z0-9]+/g, "").slice(0, 24);
}

// OMP caches provider usage reports (window label, used fraction, reset)
// in agent.db's usage_history table, refreshed by the runtime's own
// probes. Reading it here is a synchronous best-effort: no module, no
// row, no window, no error. Pi has no equivalent, so provider windows
// exist only for OMP sessions; the context window covers both.
function providerWindows(harness, provider) {
  if (harness !== "omp" || !provider || !sqliteModule)
    return {};
  try {
    const base = process.env.PI_CODING_AGENT_DIR
      || path.join(process.env.PI_CONFIG_DIR || path.join(os.homedir(), ".omp"), "agent");
    const dbPath = path.join(base, "agent.db");
    const db = new sqliteModule.Database(dbPath, { readonly: true, create: false });
    try {
      const rows = db.query(
        "SELECT provider, window_label, limit_id, used_fraction, resets_at, recorded_at " +
        "FROM usage_history WHERE provider = ? ORDER BY recorded_at DESC"
      ).all(provider);
      const cutoff = Date.now() - 60 * 60 * 1000;
      const windows = {};
      for (const row of rows) {
        if (!row || typeof row.used_fraction !== "number" || row.used_fraction < 0)
          continue;
        if (typeof row.recorded_at !== "number" || row.recorded_at < cutoff)
          break; // rows are newest first: everything older is stale too
        const key = windowKey(row.window_label || row.limit_id);
        if (!key || windows[key])
          continue;
        const resets = typeof row.resets_at === "number" ? Math.round(row.resets_at / 1000) : 0;
        windows[key] = {
          usedPercent: Math.round(row.used_fraction * 1000) / 10,
          resetsAt: resets,
        };
      }
      return windows;
    } finally {
      db.close();
    }
  } catch (e) {
    return {};
  }
}

function finite(v) {
  return typeof v === "number" && Number.isFinite(v);
}

export default function (pi) {
  // A wiring problem is reported, not thrown: both runtimes load
  // extensions at startup, and taking a harness down over a one-line
  // config is worse than saying so once.
  let hookPath;
  try {
    hookPath = resolveHookPath();
  } catch (e) {
    console.error("[aphotic pi hooks] " + e.message);
    return;
  }
  const harness = detectHarness();

  // OMP fires both assistant_message and message_end for one response;
  // pi fires message_end only. Exactly one usage source per harness, or
  // OMP would count every response twice.
  const usageEvent = harness === "omp" ? "assistant_message" : "message_end";

  let sessionId = null;
  let cwd = null;
  let cwdSent = false;
  let model = null;
  let provider = null;
  let emittedModel = null;
  let closed = false;

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
        harness: harness,
        t: now,
        ts: new Date(now).toISOString(),
        ...record,
      }));
      child.stdin.end();
    } catch (e) {}
  }

  // A CLI one-shot (`pi -p` / `omp -p`) exits within milliseconds of its
  // last event, too fast for an async spawn to land, so the shutdown
  // path writes synchronously.
  function sendSync(record, atMs = null) {
    const now = atMs || Date.now();
    try {
      spawnSync("python3", [hookPath], {
        input: JSON.stringify({
          v: 2,
          harness: harness,
          t: now,
          ts: new Date(now).toISOString(),
          ...record,
        }),
        stdio: ["pipe", "ignore", "ignore"],
      });
    } catch (e) {}
  }

  function baseRecord(ctx, event, status) {
    // OMP's session_stop arrives with a context that names no session, so
    // the last id any event carried stands in for it.
    const sid = (ctx && ctx.sessionManager && typeof ctx.sessionManager.getSessionId === "function"
      && ctx.sessionManager.getSessionId()) || sessionId;
    if (sid)
      sessionId = sid;
    if (!sid)
      return null;
    const record = { sessionId: sid, event: event, status: status };
    const agent = ctx && ctx.agent;
    // The factory is rebound to every subagent session; ctx.agent names
    // it. Pi has no subagent surface, so its records never carry this.
    if (agent && agent.kind === "sub") {
      record.agentId = String(agent.id || "");
      if (agent.name)
        record.agentType = String(agent.name);
    }
    if (cwd && !cwdSent) {
      record.cwd = cwd;
      cwdSent = true;
    }
    const m = ctx && ctx.model;
    if (m && typeof m === "object") {
      if (m.id)
        model = String(m.id);
      if (m.provider)
        provider = String(m.provider);
    }
    // The model rides a record when new or changed, never every line;
    // the provider that serves it rides along with it.
    if (model && model !== emittedModel) {
      record.model = model;
      if (provider)
        record.provider = provider;
      emittedModel = model;
    }
    return record;
  }

  function emitTurn(ctx, status) {
    const record = baseRecord(ctx, "turn", status);
    if (record)
      send(record);
  }

  function emitQuota(ctx) {
    const record = baseRecord(ctx, "quota", "running");
    if (!record)
      return;
    const windows = providerWindows(harness, provider);
    try {
      const cu = ctx && typeof ctx.getContextUsage === "function" ? ctx.getContextUsage() : null;
      if (cu && finite(cu.percent))
        windows.context = { usedPercent: Math.round(cu.percent * 10) / 10, resetsAt: 0 };
    } catch (e) {}
    if (Object.keys(windows).length === 0)
      return;
    record.quota = windows;
    send(record);
  }

  function emitUsage(ctx, message) {
    const u = message && message.usage;
    if (!u || typeof u !== "object")
      return;
    const record = baseRecord(ctx, "usage", "running");
    if (!record)
      return;
    let found = false;
    if (finite(u.input)) { record.inputTokens = u.input; found = true; }
    if (finite(u.output)) { record.outputTokens = u.output; found = true; }
    if (finite(u.reasoningTokens)) { record.reasoningTokens = u.reasoningTokens; found = true; }
    if (finite(u.cacheRead)) { record.cacheReadTokens = u.cacheRead; found = true; }
    if (finite(u.cacheWrite)) { record.cacheWriteTokens = u.cacheWrite; found = true; }
    if (!found)
      return;
    // Per-response cost; local and unpriced providers report zero, which
    // is "no price", not "free" -- emit only a positive figure.
    const total = u.cost && finite(u.cost.total) ? u.cost.total : 0;
    if (total > 0)
      record.cost = { amount: total, currency: "USD" };
    // The response's own attribution beats the session's current model:
    // a mid-session model switch shows on the line that used it.
    if (message.model)
      record.model = String(message.model);
    if (message.provider)
      record.provider = String(message.provider);
    send(record);
  }

  function onTurnEvent(event, status) {
    pi.on(event, (e, ctx) => {
      try {
        emitTurn(ctx, status);
      } catch (err) {}
    });
  }

  pi.on("session_start", (e, ctx) => {
    try {
      const record = baseRecord(ctx, "session_start", "running");
      if (record) {
        if (ctx && ctx.cwd)
          record.cwd = String(ctx.cwd);
        send(record);
        emitQuota(ctx);
      }
    } catch (err) {}
  });

  onTurnEvent("before_agent_start", "running");
  onTurnEvent("turn_start", "running");

  pi.on("tool_call", (e, ctx) => {
    try {
      const record = baseRecord(ctx, "tool_call", "running");
      if (!record)
        return;
      if (e && e.toolName)
        record.tool = String(e.toolName);
      if (e && e.toolCallId)
        record.toolId = String(e.toolCallId);
      record.toolStatus = "running";
      send(record);
    } catch (err) {}
  });

  pi.on("tool_result", (e, ctx) => {
    try {
      const record = baseRecord(ctx, "tool_call", "running");
      if (!record)
        return;
      if (e && e.toolName)
        record.tool = String(e.toolName);
      if (e && e.toolCallId)
        record.toolId = String(e.toolCallId);
      record.toolStatus = e && e.isError ? "errored" : "completed";
      send(record);
    } catch (err) {}
  });

  pi.on(usageEvent, (e, ctx) => {
    try {
      const message = e && e.message;
      if (!message || message.role !== "assistant")
        return;
      emitUsage(ctx, message);
    } catch (err) {}
  });

  // The harness is asking the user for a decision: that is the waiting
  // state the tile badges. OMP emits it when a tool needs approval and a
  // handler is in the loop; pi exposes the same boundary.
  onTurnEvent("tool_approval_requested", "waiting");

  // Run finished, harness idle: OMP's main-session stop hook, pi's
  // "will not continue automatically" boundary. One of the two exists
  // per runtime; registering the other is harmless.
  const idleEvent = harness === "omp" ? "session_stop" : "agent_settled";
  pi.on(idleEvent, (e, ctx) => {
    try {
      emitTurn(ctx, "idle");
      emitQuota(ctx);
    } catch (err) {}
  });

  onTurnEvent("auto_compaction_start", "compacting");
  onTurnEvent("auto_compaction_end", "running");

  pi.on("turn_end", (e, ctx) => {
    try {
      emitQuota(ctx);
    } catch (err) {}
  });

  pi.on("session_shutdown", (e, ctx) => {
    closed = true;
    try {
      const record = baseRecord(ctx, "session_end", "ended");
      if (record) {
        record.endReason = "shutdown";
        sendSync(record);
      }
    } catch (err) {}
  });
}
