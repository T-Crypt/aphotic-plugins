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
  const child = spawn("python3", [HOOK_PATH], { stdio: ["pipe", "ignore", "ignore"] });
  child.on("error", () => {});
  child.stdin.on("error", () => {});
  child.stdin.write(JSON.stringify({ harness: "opencode", ...payload }));
  child.stdin.end();
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
          send({
            session_id: info.id,
            hook_event_name: "SessionStart",
            cwd: info.directory || directory,
            model: models.get(info.id) || "",
          });
          break;
        }
        case "session.idle": {
          const id = event.properties.sessionID;
          if (!known.has(id))
            break;
          send({ session_id: id, hook_event_name: "Stop" });
          break;
        }
        case "session.deleted": {
          const id = event.properties.info.id;
          if (!known.has(id))
            break;
          send({ session_id: id, hook_event_name: "SessionEnd" });
          known.delete(id);
          models.delete(id);
          break;
        }
      }
    },
    "chat.params": async input => {
      if (!input.sessionID || !input.model)
        return;
      const resolved = `${input.model.providerID}/${input.model.id}`;
      const isNew = models.get(input.sessionID) !== resolved;
      models.set(input.sessionID, resolved);
      // session.created fires before the first chat.params call, so the
      // model is always unknown at that point -- send a follow-up
      // SessionStart-shaped update the first time it resolves (or changes
      // mid-session) so the graph label picks it up instead of staying on
      // the session id fallback.
      if (isNew && known.has(input.sessionID))
        send({ session_id: input.sessionID, hook_event_name: "SessionStart", model: resolved });
    },
    "tool.execute.before": async input => {
      toolStarts.set(input.callID, Date.now());
      send({
        session_id: input.sessionID,
        hook_event_name: "PreToolUse",
        tool_name: normalizeTool(input.tool),
        tool_use_id: input.callID,
      });
    },
    "tool.execute.after": async input => {
      const startedAt = toolStarts.get(input.callID);
      toolStarts.delete(input.callID);
      send({
        session_id: input.sessionID,
        hook_event_name: "PostToolUse",
        tool_name: normalizeTool(input.tool),
        tool_use_id: input.callID,
        duration_ms: startedAt ? Date.now() - startedAt : undefined,
      });
    },
    dispose: async () => {
      for (const id of known)
        send({ session_id: id, hook_event_name: "SessionEnd" });
      known.clear();
      models.clear();
      toolStarts.clear();
    },
  };
};
