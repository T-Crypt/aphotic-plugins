import { spawn } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

// wire.sh writes this alongside the symlinked plugin file with the
// absolute path to core's agent_hook.py (this plugin package lives under
// ~/.local/share/aphotic/plugins/opencode-hooks/, decoupled from wherever
// the Aphotic-Hypr checkout itself is, so this script can't derive that
// path from its own location the way codex_hook.py can from an argv
// passed through hooks.json -- OpenCode's plugin loader takes no
// arguments). Falls back to the pre-plugin-architecture assumption (a
// checkout at ~/Aphotic-Hypr) only if that file is missing, e.g. a
// hand-symlinked local-dev setup.
function resolveHookPath() {
  const configPath = path.join(path.dirname(new URL(import.meta.url).pathname), ".aphotic-hook-config.json");
  try {
    const config = JSON.parse(fs.readFileSync(configPath, "utf8"));
    if (config.agentHookPy)
      return config.agentHookPy;
  } catch (e) {
    // missing/invalid -- fall through to the default below
  }
  return path.join(os.homedir(), "Aphotic-Hypr", "Configs", ".local", "lib", "aphotic", "agent_hook.py");
}

const HOOK_PATH = resolveHookPath();

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
};

function normalizeTool(name) {
  if (!name)
    return name;
  const lower = name.toLowerCase();
  if (TOOL_NAMES[lower])
    return TOOL_NAMES[lower];
  return name.charAt(0).toUpperCase() + name.slice(1);
}

function send(payload) {
  try {
    const t = Date.now();
    const child = spawn("python3", [HOOK_PATH], { stdio: ["pipe", "ignore", "ignore"] });
    child.on("error", () => {});
    child.stdin.on("error", () => {});
    child.stdin.write(JSON.stringify({
      v: 2,
      harness: "opencode",
      ...payload,
      t,
      ts: new Date(t).toISOString(),
    }));
    child.stdin.end();
  } catch (e) {}
}

function usageFields(info) {
  const tokens = info?.tokens;
  if (!tokens || typeof tokens !== "object")
    return null;
  const values = {
    inputTokens: tokens.input,
    outputTokens: tokens.output,
    cacheReadTokens: tokens.cache?.read,
    cacheWriteTokens: tokens.cache?.write,
  };
  const fields = {};
  for (const [key, value] of Object.entries(values)) {
    if (Number.isFinite(value))
      fields[key] = value;
  }
  return Object.keys(fields).length > 0 ? fields : null;
}

export const AphoticAgentTracking = async ({ directory }) => {
  const models = new Map();
  const toolStarts = new Map();
  const known = new Set();

  return {
    event: async ({ event }) => {
      switch (event.type) {
        case "session.created": {
          const info = event.properties.info;
          known.add(info.id);
          const identity = models.get(info.id) || {};
          send({
            sessionId: info.id,
            event: "session_start",
            status: "running",
            cwd: info.directory || directory,
            ...identity,
          });
          break;
        }
        case "session.idle": {
          const id = event.properties.sessionID;
          if (!known.has(id))
            break;
          send({ sessionId: id, event: "turn", status: "idle" });
          break;
        }
        case "session.deleted": {
          const id = event.properties.info.id;
          if (!known.has(id))
            break;
          send({ sessionId: id, event: "session_end", status: "ended" });
          known.delete(id);
          models.delete(id);
          break;
        }
        case "message.updated": {
          const info = event.properties?.info;
          const id = info?.sessionID || event.properties?.sessionID;
          const usage = info?.role === "assistant" ? usageFields(info) : null;
          if (id && known.has(id) && usage)
            send({ sessionId: id, event: "usage", status: "running", ...usage });
          break;
        }
      }
    },
    "chat.params": async input => {
      if (!input.sessionID || !input.model)
        return;
      const provider = input.model.providerID || "";
      const model = provider && input.model.id ? `${provider}/${input.model.id}` : (input.model.id || provider);
      if (!model)
        return;
      const current = models.get(input.sessionID);
      const isNew = current?.model !== model || current?.provider !== provider;
      const identity = { model };
      if (provider)
        identity.provider = provider;
      models.set(input.sessionID, identity);
      // session.created fires before the first chat.params call, so the
      // model is always unknown at that point -- send a follow-up
      // SessionStart-shaped update the first time it resolves (or changes
      // mid-session) so the graph label picks it up instead of staying on
      // the session id fallback.
      if (isNew && known.has(input.sessionID))
        send({ sessionId: input.sessionID, event: "session_start", status: "running", ...identity });
    },
    "tool.execute.before": async input => {
      toolStarts.set(input.callID, Date.now());
      send({
        sessionId: input.sessionID,
        event: "tool_call",
        status: "running",
        tool: normalizeTool(input.tool),
        toolId: input.callID,
        toolStatus: "running",
      });
    },
    "tool.execute.after": async input => {
      const startedAt = toolStarts.get(input.callID);
      toolStarts.delete(input.callID);
      send({
        sessionId: input.sessionID,
        event: "tool_call",
        status: "running",
        tool: normalizeTool(input.tool),
        toolId: input.callID,
        toolStatus: "completed",
        durationMs: startedAt !== undefined ? Date.now() - startedAt : undefined,
      });
    },
    dispose: async () => {
      for (const id of known)
        send({ sessionId: id, event: "session_end", status: "ended" });
      known.clear();
      models.clear();
      toolStarts.clear();
    },
  };
};
