#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
# SPDX-FileCopyrightText: Aphotic-Hypr contributors
"""Entry point for every OpenRGB Sync hook.

The hook scripts in ../hooks/ are thin shims: they load the user's
settings.conf and exec this with one subcommand. Everything that decides
*what* the lighting should be lives here; everything that decides *how* to
put it on a device lives in ../lib/rgb_common.py (ported, see its docstring).

Three inputs, one resolved output
---------------------------------
Three unrelated events can each want the lighting to say something:

    theme change   -> the accent color everything else is derived from
    Gaming profile -> same accent, louder (saturated, static)
    agent session  -> same accent, breathing while a session is live

Applying each one directly as it arrives would make the result depend on
arrival order -- a theme change during a game would quietly undo the game's
state, and an agent going idle would clobber it too. So each event only
records a fact in state.json, and the lighting is always the *resolution* of
all three facts (profile > agent > idle theme). That is the same "one
resolved state, not a race of writers" shape ProfileEngine itself uses for
claims, and it costs one small JSON file.

Failure posture
---------------
Every hook path fails closed: if the SDK server isn't reachable, nothing
lights up and nothing breaks. It does not fail *silently* -- the reason goes
to sync.log, and the one first-run cause a user cannot guess (missing udev
rules, which presents as a successful connection with zero devices, or as
every device erroring on write) raises a desktop notification once, pointing
at scripts/setup.sh. The previous shell hook ended every write with `|| true`
and that is precisely what hid a real connection failure during testing.
"""
import json
import os
import subprocess
import sys
import time

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))

CONFIG_DIR = os.environ.get(
    "OPENRGB_PLUGIN_CONFIG_DIR",
    os.path.join(os.environ.get("XDG_CONFIG_HOME", os.path.expanduser("~/.config")), "aphotic-plugins", "openrgb"))
STATE_DIR = os.environ.get(
    "OPENRGB_PLUGIN_STATE_DIR",
    os.path.join(os.environ.get("XDG_STATE_HOME", os.path.expanduser("~/.local/state")), "aphotic-plugins", "openrgb"))
STATE_FILE = os.path.join(STATE_DIR, "state.json")
LOG_FILE = os.path.join(STATE_DIR, "sync.log")
ZONES_FILE = os.path.join(CONFIG_DIR, "zones.conf")

LOG_MAX_BYTES = 256 * 1024
LOG_KEEP_LINES = 400

# An agent session that never sent its stop/session_end (a harness killed
# mid-run) must not breathe forever.
AGENT_SESSION_TTL = 6 * 60 * 60

# Events that mean "this session is doing something"; anything not listed
# here as an end event keeps the session live. subagent_stop is deliberately
# absent from both lists -- a subagent finishing says nothing about whether
# the session it belongs to is still working.
AGENT_END_EVENTS = ("stop", "session_end")
AGENT_START_EVENTS = ("session_start", "pre_tool_use", "post_tool_use",
                      "post_tool_use_failure", "notification")

UDEV_RULE_CANDIDATES = [
    "/usr/lib/udev/rules.d/60-openrgb.rules",
    "/lib/udev/rules.d/60-openrgb.rules",
    "/etc/udev/rules.d/60-openrgb.rules",
]


def setting(name, default=""):
    value = os.environ.get(name)
    return default if value is None or value == "" else value


def setting_float(name, default):
    try:
        return float(setting(name, str(default)))
    except ValueError:
        return default


def setting_list(name):
    return [part.strip() for part in setting(name).split(",") if part.strip()]


def log(message):
    try:
        os.makedirs(STATE_DIR, exist_ok=True)
        with open(LOG_FILE, "a") as fh:
            fh.write("[%s] %s\n" % (time.strftime("%Y-%m-%d %H:%M:%S"), message))
        if os.path.getsize(LOG_FILE) > LOG_MAX_BYTES:
            with open(LOG_FILE) as fh:
                tail = fh.readlines()[-LOG_KEEP_LINES:]
            tmp = LOG_FILE + ".tmp"
            with open(tmp, "w") as fh:
                fh.writelines(tail)
            os.replace(tmp, LOG_FILE)
    except OSError:
        pass


def notify_once(key, body):
    """Desktop-notify at most once per distinct message, so a first-run
    problem is visible without becoming something to dismiss on every
    wallpaper switch."""
    marker = os.path.join(STATE_DIR, "notified-%s" % key)
    try:
        if os.path.exists(marker) and open(marker).read() == body:
            return
        os.makedirs(STATE_DIR, exist_ok=True)
        with open(marker, "w") as fh:
            fh.write(body)
    except OSError:
        pass
    try:
        subprocess.Popen(["notify-send", "OpenRGB Sync", body],
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except (OSError, ValueError):
        pass  # no notify-send on this system; the log line above still stands


def udev_rules_present():
    for path in UDEV_RULE_CANDIDATES:
        if os.path.exists(path):
            return True
    for directory in ("/usr/lib/udev/rules.d", "/lib/udev/rules.d", "/etc/udev/rules.d"):
        try:
            if any("openrgb" in name.lower() for name in os.listdir(directory)):
                return True
        except OSError:
            continue
    return False


def load_state():
    try:
        with open(STATE_FILE) as fh:
            state = json.load(fh)
    except (OSError, ValueError):
        state = {}
    state.setdefault("theme", "")
    state.setdefault("profiles", [])
    state.setdefault("agents", {})
    state.setdefault("applied", "")
    now = time.time()
    state["agents"] = {sid: ts for sid, ts in state["agents"].items()
                       if isinstance(ts, (int, float)) and now - ts < AGENT_SESSION_TTL}
    return state


def save_state(state):
    try:
        os.makedirs(STATE_DIR, exist_ok=True)
        tmp = STATE_FILE + ".tmp"
        with open(tmp, "w") as fh:
            json.dump(state, fh)
        os.replace(tmp, STATE_FILE)
    except OSError as exc:
        log("could not persist state: %s" % exc)


def load_zone_overrides():
    """zones.conf: <device-name-substring>:<zone index>:<led count> per line."""
    overrides = []
    try:
        with open(ZONES_FILE) as fh:
            lines = fh.readlines()
    except OSError:
        return overrides
    for line in lines:
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split(":")
        if len(parts) != 3:
            continue
        name_part, zone_idx, count = (p.strip() for p in parts)
        if not name_part or not zone_idx.isdigit() or not count.isdigit():
            continue
        overrides.append((name_part, int(zone_idx), int(count)))
    return overrides


def resolve(state, rgb, color):
    """The whole precedence rule, in one place.

    Gaming outranks an agent session outranks the plain theme: a game is an
    explicit, foregrounded thing the user is doing right now, and an agent
    session is background work -- an indicator, not the main event.
    """
    if state["profiles"]:
        boosted = rgb.saturate(color,
                               setting_float("GAMING_SATURATION", 1.0),
                               setting_float("GAMING_VALUE", 1.0))
        return setting("GAMING_EFFECT", "static"), boosted
    if state["agents"]:
        return setting("AGENT_EFFECT", "breathing"), color
    return setting("IDLE_EFFECT", "static"), color


def apply_state(state, force=False, reason="", skip_if_unchanged=False):
    """Connect, reassert zone sizes, apply the resolved effect+color.

    `force` routes through the black-flash path, used on every *revert*
    (leaving Gaming, last agent session going idle) because the target state
    there is often byte-identical to what OpenRGB already thinks is applied,
    and several controllers no-op an identical resend -- see
    force_apply_effect_color()'s docstring.

    `skip_if_unchanged` drops a batch that would resolve to what was last
    applied anyway. It is set for the profile/agent edges only, where an
    event genuinely changes nothing visible (an agent session starting while
    Gaming already owns the lighting). A theme change and a manual apply
    always write, since those are also the ways to reassert state after
    something outside this plugin -- an OpenRGB restart -- desynced it.
    """
    try:
        import rgb_common as rgb
    except ImportError as exc:
        log("openrgb-python is not installed (%s) -- run scripts/setup.sh" % exc)
        notify_once("no-module",
                    "The Python 'openrgb' module is missing, so lighting can't be synced. "
                    "Run the OpenRGB Sync plugin's scripts/setup.sh once.")
        return False

    accent = rgb.parse_hex(state.get("theme"))
    if accent is None:
        log("no usable accent color in state (%r) -- nothing to apply" % state.get("theme"))
        return False

    try:
        client = rgb.connect()
    except ConnectionRefusedError:
        log("SDK server refused the connection on %s:%d -- is OpenRGB running with its "
            "SDK server enabled ('openrgb --server')? Nothing applied." % (rgb.SDK_HOST, rgb.SDK_PORT))
        return False
    except Exception as exc:
        log("could not reach the SDK server on %s:%d: %s" % (rgb.SDK_HOST, rgb.SDK_PORT, exc))
        return False

    if not client.devices:
        # A successful connection reporting zero devices is the exact shape a
        # missing udev rules file takes on Linux: the server starts fine, then
        # gets EACCES on every hidraw/i2c node and enumerates nothing. That is
        # a one-time setup problem, not a transient failure, so it gets said
        # out loud instead of logged into a file nobody opens.
        log("connected, but OpenRGB reports zero devices")
        if not udev_rules_present():
            notify_once("udev",
                        "OpenRGB sees no RGB devices and no 60-openrgb.rules udev file is "
                        "installed -- device access is being denied. Run the OpenRGB Sync "
                        "plugin's scripts/setup.sh once to fix this.")
        else:
            notify_once("no-devices",
                        "OpenRGB is running but reports no devices. Check OpenRGB's own "
                        "detection (openrgb -vv) -- nothing to sync.")
        return False

    effect, color = resolve(state, rgb, accent)
    resolved = "%s %s" % (effect, rgb.to_hex(color))
    if skip_if_unchanged and not force and state.get("applied") == resolved:
        log("%s: already %s, nothing to do" % (reason or "apply", resolved))
        return True
    exclude = setting_list("EXCLUDE_DEVICES")

    for name, status, detail in rgb.apply_zone_sizes(client, load_zone_overrides()):
        if status != "OK":
            log("zone resize %s - %s: %s" % (status, name, detail))

    apply_fn = rgb.force_apply_effect_color if force else rgb.apply_effect_color
    results = apply_fn(client, effect, color, exclude=exclude)

    failed = [r for r in results if r[1] == "ERROR"]
    skipped = [r for r in results if r[1] == "SKIP"]
    state["applied"] = resolved
    save_state(state)
    log("%s: %s -> %d/%d devices OK%s" % (
        reason or "apply", resolved,
        len(results) - len(failed) - len(skipped), len(results),
        " (forced)" if force else ""))
    for name, status, detail in failed + skipped:
        log("    %-5s - %s: %s" % (status, name, detail))

    if results and len(failed) == len(results) and not udev_rules_present():
        notify_once("udev-writes",
                    "Every OpenRGB device rejected a write and no 60-openrgb.rules udev file "
                    "is installed. Run the OpenRGB Sync plugin's scripts/setup.sh once.")
    return not failed


def cmd_theme(_args):
    try:
        palette = json.load(sys.stdin)
    except ValueError as exc:
        log("theme hook got unparseable palette JSON on stdin: %s" % exc)
        return 0

    accent = setting("ACCENT_OVERRIDE")
    if not accent:
        # color4 is this project's established accent slot -- the same slot
        # the shell's own wallust template maps to its m3primary role.
        # PLUGIN_SYSTEM.md flags "which slot is the accent" as still open;
        # this follows the shell rather than deciding it.
        accent = (palette.get("colors", {}) or {}).get("color4") or palette.get("foreground") or ""
    if not accent:
        log("palette had neither colors.color4 nor foreground -- nothing to apply")
        return 0
    if not accent.startswith("#"):
        accent = "#" + accent

    state = load_state()
    state["theme"] = accent
    save_state(state)
    apply_state(state, reason="theme")
    return 0


def cmd_profile(args):
    """Gaming ProfileEngine consumer: activate/deactivate for one profile id."""
    if len(args) < 2:
        return 0
    action, profile_id = args[0], args[1]

    watched = setting_list("PROFILE_IDS") or ["gaming"]
    if profile_id not in watched:
        return 0

    state = load_state()
    profiles = [p for p in state["profiles"] if p != profile_id]
    if action == "activate":
        profiles.append(profile_id)
    state["profiles"] = profiles
    save_state(state)
    # A deactivate is a revert to a possibly-identical color; force it.
    apply_state(state, force=(action != "activate"), skip_if_unchanged=True,
                reason="profile %s %s" % (profile_id, action))
    return 0


def cmd_agent_event(_args):
    """Agent-event consumer -- same wire format Agent Graph and the bar's Live
    Agent Activity read (agent_hook.py's record shape).

    Tracked per session id rather than as one global flag: two concurrent
    sessions must not have the first one to finish turn the breathing off
    while the other is still working.
    """
    try:
        event = json.load(sys.stdin)
    except ValueError as exc:
        log("agent hook got unparseable event JSON on stdin: %s" % exc)
        return 0

    name = event.get("event") or ""
    session_id = event.get("sessionId") or ""
    if not session_id:
        return 0

    harnesses = setting_list("AGENT_HARNESSES")
    if harnesses and (event.get("harness") or "claude") not in harnesses:
        return 0

    state = load_state()
    was_active = bool(state["agents"])
    if name in AGENT_END_EVENTS:
        state["agents"].pop(session_id, None)
    elif name in AGENT_START_EVENTS:
        state["agents"][session_id] = time.time()
    else:
        return 0
    is_active = bool(state["agents"])
    save_state(state)

    # Only the edges matter. Reapplying the same effect on every single
    # tool-call event would put a full device batch in the path of every tool
    # Claude Code runs, for no visible change.
    if was_active != is_active:
        apply_state(state, force=not is_active, skip_if_unchanged=True,
                    reason="agent %s" % ("active" if is_active else "idle"))
    return 0


def cmd_apply(_args):
    state = load_state()
    return 0 if apply_state(state, force=True, reason="manual apply") else 1


def cmd_status(_args):
    import rgb_common as rgb
    state = load_state()
    print("Theme accent : %s" % (state["theme"] or "(none recorded yet)"))
    print("Profiles     : %s" % (", ".join(state["profiles"]) or "(none active)"))
    print("Agents       : %s" % (", ".join(state["agents"]) or "(none active)"))
    accent = rgb.parse_hex(state["theme"])
    if accent is not None:
        effect, color = resolve(state, rgb, accent)
        print("Resolves to  : %s %s" % (effect, rgb.to_hex(color)))
    print()

    try:
        client = rgb.connect("Aphotic-OpenRGB-Status")
    except Exception as exc:
        print("Cannot reach the OpenRGB SDK server on %s:%d: %s" % (rgb.SDK_HOST, rgb.SDK_PORT, exc))
        return 1

    rows = rgb.read_current_state(client)
    if not rows:
        print("OpenRGB reports no devices.")
        return 1
    width = max(len(r["device"]) for r in rows + [{"device": "Device"}])
    mode_width = max(len(r["mode"]) for r in rows + [{"mode": "Mode"}])
    effect_width = max(len(r["effect"]) for r in rows + [{"effect": "Effect"}])
    print("%-*s  %-*s  %-*s  %-5s  %s" % (width, "Device", mode_width, "Mode",
                                          effect_width, "Effect", "LEDs", "Color"))
    for row in rows:
        print("%-*s  %-*s  %-*s  %-5d  %s" % (width, row["device"], mode_width, row["mode"],
                                              effect_width, row["effect"], row["leds"], row["color"]))
    return 0


def cmd_devices(args):
    """Raw inventory, and the source of truth scripts/setup.sh walks for zone
    sizing -- OpenRGB's own zone LED counts, not a parse of CLI output."""
    import rgb_common as rgb
    try:
        client = rgb.connect("Aphotic-OpenRGB-Inventory")
    except Exception as exc:
        if "--json" in args:
            print(json.dumps({"error": str(exc), "devices": []}))
        else:
            print("Cannot reach the OpenRGB SDK server on %s:%d: %s" % (rgb.SDK_HOST, rgb.SDK_PORT, exc))
        return 1

    inventory = [{
        "index": index,
        "name": dev.name,
        "leds": len(dev.leds),
        "modes": [m.name for m in dev.modes],
        "static_mode": rgb.resolve_mode(dev, "static"),
        "breathing_mode": rgb.resolve_mode(dev, "breathing"),
        "zones": [{"index": z_index, "name": zone.name, "leds": len(zone.leds)}
                  for z_index, zone in enumerate(dev.zones)],
    } for index, dev in enumerate(client.devices)]

    if "--json" in args:
        print(json.dumps({"devices": inventory}))
        return 0

    for dev in inventory:
        print("[%d] %s -- %d LEDs" % (dev["index"], dev["name"], dev["leds"]))
        print("    static -> %s, breathing -> %s" % (dev["static_mode"], dev["breathing_mode"]))
        print("    modes: %s" % ", ".join(dev["modes"]))
        for zone in dev["zones"]:
            print("    zone %d (%s): %d LEDs" % (zone["index"], zone["name"], zone["leds"]))
    return 0


COMMANDS = {
    "theme": cmd_theme,
    "profile": cmd_profile,
    "agent-event": cmd_agent_event,
    "apply": cmd_apply,
    "status": cmd_status,
    "devices": cmd_devices,
}


def main():
    args = sys.argv[1:]
    if not args or args[0] not in COMMANDS:
        print("Usage: rgb_sync.py {%s} [args]" % "|".join(COMMANDS), file=sys.stderr)
        return 2
    try:
        return COMMANDS[args[0]](args[1:])
    except Exception as exc:
        # A hook must never take down the thing that fired it. Everything
        # unexpected lands in the log with its type, not on the caller.
        log("unhandled %s in '%s': %s" % (type(exc).__name__, args[0], exc))
        return 0


if __name__ == "__main__":
    sys.exit(main())
