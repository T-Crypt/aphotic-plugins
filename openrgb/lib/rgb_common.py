#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
# SPDX-FileCopyrightText: Aphotic-Hypr contributors
"""Device/effect layer for the OpenRGB Sync plugin.

Ported from a standalone Windows OpenRGB automation project whose whole
value was the two things it got empirically right against a real mixed
rig (GPU over I2C, motherboard, HID case/fan/PSU-cable controllers, DRAM
over SMBus) after a long series of "the SDK reported success and the
hardware stayed dark" bugs. Both are reproduced here verbatim in
behaviour, and neither is obvious enough to rediscover cheaply:

  1. **Per-device isolated writes.** The original looped over every
     device with no per-device error handling, so one transient write
     failure -- HID controllers are the ones prone to it, unlike the
     I2C-attached GPU/DRAM -- raised out of the loop and silently
     skipped every device after it. Every device's mode+color write is
     therefore wrapped in its own try/except here, and the per-device
     outcome is *returned* rather than swallowed, because the second
     half of that same bug was that the results existed and nothing ever
     surfaced them.

  2. **color_mode-aware application.** Every OpenRGB mode declares a
     color_mode of NONE, PER_LED or MODE_SPECIFIC, and they are not
     interchangeable -- see push_color() below. Writing raw LED bytes
     unconditionally (the naive approach, and what a `--mode Static
     --color` CLI call effectively assumes) fights self-driven effects
     and silently misses the baked mode color on MODE_SPECIFIC devices.

What deliberately did *not* come across is every hardcoded device name.
The original was one-PC-specific: a DEVICE_KEYS list and an
effect->per-device-mode-name table, both naming that machine's exact
hardware ("Strimer", "SL Infinity", "O11 Dynamic", "RTX 4090"). Here the
same decisions are made at runtime against whatever openrgb-python
reports, so an arbitrary motherboard/GPU/RAM/case/fan combination works
with zero per-device config -- see resolve_mode(), which turns that
hand-built table into a preference list filtered by what each mode can
actually accept.
"""
import colorsys
import os
import time

from openrgb import OpenRGBClient
from openrgb.utils import RGBColor, ModeColors

SDK_HOST = os.environ.get("OPENRGB_SDK_HOST", "127.0.0.1")
SDK_PORT = int(os.environ.get("OPENRGB_SDK_PORT", "6742"))

# A mode can only take a color if it declares one of these; ModeColors.NONE
# (Rainbow/Spectrum Cycle and friends) is hardware-driven and takes no color
# input at all, and RANDOM picks its own.
COLORABLE = (ModeColors.PER_LED, ModeColors.MODE_SPECIFIC)

# Logical effect -> candidate real mode names, best first, matched
# case-insensitively (vendors disagree on capitalization: "Rainbow Wave" vs
# "Rainbow wave" showed up on one rig).
#
# This replaces the original's hand-built effect x device-name table. Every
# entry below is a mode name that table actually resolved to on real hardware,
# just generalized into "try these in order" instead of "this device gets
# this mode". Direct leads the static list because it is the host-driven,
# no-firmware-effect mode and the most universally present; Custom trails it
# as the per-LED fallback for hub-style controllers whose Static is a
# single-color-for-the-whole-device mode packet.
EFFECT_MODES = {
    "static": ["Direct", "Static", "Custom", "Fixed", "Solid"],
    "breathing": ["Breathing", "Breath", "Color Pulse", "Pulse", "Color Shift", "Fade"],
}
EFFECTS = tuple(EFFECT_MODES)


def connect(name="Aphotic-OpenRGB"):
    """Open an SDK connection. Raises if the server isn't reachable -- callers
    decide whether that's fatal (setup/status) or a silent no-op (hooks)."""
    return OpenRGBClient(address=SDK_HOST, port=SDK_PORT, name=name)


def parse_hex(value):
    """'#rrggbb' / 'rrggbb' / '#rgb' -> RGBColor. Returns None if unparseable."""
    if not value:
        return None
    text = str(value).strip().lstrip("#")
    if len(text) == 3:
        text = "".join(c * 2 for c in text)
    if len(text) != 6:
        return None
    try:
        return RGBColor(int(text[0:2], 16), int(text[2:4], 16), int(text[4:6], 16))
    except ValueError:
        return None


def to_hex(color):
    return "#%02x%02x%02x" % (color.red, color.green, color.blue)


def saturate(color, saturation_floor=1.0, value_floor=1.0):
    """Push a color toward full saturation/brightness without changing its hue.

    Used for the Gaming profile's "same accent, louder" state. Floors rather
    than multipliers: a theme accent that is already vivid stays where it is,
    and a muted one is lifted to the floor, so the result is predictable
    across wildly different palettes instead of scaling off an arbitrary base.
    """
    h, s, v = colorsys.rgb_to_hsv(color.red / 255.0, color.green / 255.0, color.blue / 255.0)
    r, g, b = colorsys.hsv_to_rgb(h, max(s, saturation_floor), max(v, value_floor))
    return RGBColor(int(round(r * 255)), int(round(g * 255)), int(round(b * 255)))


def _populated_zones(dev):
    return [z for z in dev.zones if len(z.leds) > 0]


def resolve_mode(dev, effect):
    """Pick the real mode name on `dev` that best expresses a logical effect.

    The filter on COLORABLE is the whole point, and is the generalized form of
    a lesson the original learned the hard way per-device: a mode whose name
    reads right can still be the wrong choice, because a NONE-color_mode mode
    ignores the color entirely. A device with no colorable breathing-style
    mode therefore falls through to its static resolution -- which is exactly
    the outcome the original hardcoded for its fan hub (both static and
    breathing pinned to that device's "Custom" mode), derived at runtime here
    instead of being written down for one specific controller.

    On a device with more than one populated zone, PER_LED modes are tried
    ahead of the name order. This is the other half of that same fan-hub
    lesson: its "Static" is MODE_SPECIFIC, meaning the firmware bakes ONE
    color into ONE mode packet for the whole device, and live testing showed
    it could not reach every channel reliably -- only "Custom", its sole
    PER_LED mode, addressed each channel correctly. Name order alone would
    pick Static there and reintroduce exactly the bug this port exists to
    carry the fix for. On a single-zone device the distinction is moot, so
    the preference only applies where it was actually earned.
    """
    by_name = {m.name.lower(): m for m in dev.modes}
    candidates = EFFECT_MODES.get(effect, [])

    passes = [COLORABLE]
    if len(_populated_zones(dev)) > 1:
        passes = [(ModeColors.PER_LED,), COLORABLE]

    for accepted in passes:
        for candidate in candidates:
            mode = by_name.get(candidate.lower())
            if mode is not None and mode.color_mode in accepted:
                return mode.name

    if effect != "static":
        return resolve_mode(dev, "static")
    for mode in dev.modes:
        if mode.color_mode in COLORABLE:
            return mode.name
    return None


def push_color(dev, color):
    """Set a color on a device, respecting the ACTIVE mode's color_mode.

    Found by reading openrgb-python's orgb.py, after a run of bugs where the
    SDK reported success and the hardware disagreed. The three cases:
      - MODE_SPECIFIC: the firmware reads its color from the *mode packet*
        (mode.colors), not from the zone's LED buffer. dev.set_color() bakes
        the color into the mode and resends it -- the only mechanism that
        reaches these devices.
      - PER_LED: the zone LED buffer is the right target, and zone-by-zone is
        needed over dev.set_color() for devices with several populated zones
        (an 8-channel fan hub) since the flat device-wide write does not
        reliably reach every zone.
      - NONE / RANDOM: self-driven effect, takes no color. Writing raw LED
        bytes on top of one fights the running effect (this was the cause of
        a Rainbow effect getting stuck lighting ~3 LEDs). Do nothing.

    fast=True skips openrgb-python's automatic full-device resync after every
    single write; the read-back isn't needed here and that resync-per-write
    was the dominant cost of an apply (seconds -> ~0.3s on an 8-device rig).
    """
    active_mode = dev.modes[dev.active_mode]
    if active_mode.color_mode == ModeColors.MODE_SPECIFIC:
        dev.set_color(color)
    elif active_mode.color_mode == ModeColors.PER_LED:
        for zone in _populated_zones(dev):
            zone.set_colors([color] * len(zone.leds), fast=True)


def _apply_mode(dev, mode_name):
    """Switch modes only if actually changing -- set_mode() forces a full
    client resync internally, so a no-op re-set of the current mode is an
    expensive round trip for nothing on every color-only reapply."""
    if dev.modes[dev.active_mode].name != mode_name:
        dev.set_mode(mode_name)


def _off_mode_for(dev):
    names = [m.name for m in dev.modes]
    for preferred in ("Direct", "Custom", "Static"):
        if preferred in names:
            return preferred
    return names[0] if names else None


def apply_zone_sizes(client, overrides):
    """Reassert every configured zone LED count. Cheap no-op once a zone
    already matches, so it is safe to call on every hook run.

    Controller-style hubs (fan hubs, lighting nodes) report 0 LEDs until told
    how many are wired to each channel -- OpenRGB genuinely cannot autodetect
    that -- and silently ignore color writes until they are sized. The
    original hardcoded the sizes for one rig; here they come from the user's
    zones.conf, written by scripts/setup.sh.

    `overrides` is a list of (device-name-substring, zone-index, led-count).
    The comparison is `!=`, not `== 0`: a stale nonzero size (what an OpenRGB
    restart leaves behind) is exactly the case a zero-check silently skips,
    which left channels underfed and lighting partial/wrong-hued.
    """
    results = []
    for name_part, zone_idx, count in overrides:
        for dev in client.devices:
            if name_part.lower() not in dev.name.lower():
                continue
            if zone_idx >= len(dev.zones):
                results.append((dev.name, "SKIP", "no zone %d" % zone_idx))
                continue
            zone = dev.zones[zone_idx]
            if len(zone.leds) == count:
                continue
            try:
                zone.resize(count)
                results.append((dev.name, "OK", "zone %d (%s) -> %d LEDs" % (zone_idx, zone.name, count)))
            except Exception as exc:
                # Some zones are a fixed single-LED type and genuinely cannot
                # be resized -- a hardware/protocol limit, not a failure worth
                # aborting the run over.
                results.append((dev.name, "ERROR", "zone %d resize: %s" % (zone_idx, exc)))
    return results


def apply_effect_color(client, effect, color, exclude=None):
    """Apply one logical effect + one color to every detected device.

    Returns a list of (device_name, "OK"/"SKIP"/"ERROR", detail). Every
    device's write is isolated: one throwing must not stop the devices after
    it, which is the single most important behaviour in this file.
    """
    results = []
    for dev in client.devices:
        if exclude and any(pat.lower() in dev.name.lower() for pat in exclude if pat):
            results.append((dev.name, "SKIP", "excluded by settings"))
            continue

        mode_name = resolve_mode(dev, effect)
        if mode_name is None:
            results.append((dev.name, "SKIP", "no color-capable mode for '%s'" % effect))
            continue
        try:
            _apply_mode(dev, mode_name)
            push_color(dev, color)
            results.append((dev.name, "OK", "%s / %s" % (mode_name, to_hex(color))))
        except Exception as exc:
            results.append((dev.name, "ERROR", str(exc)))
    return results


def force_apply_effect_color(client, effect, color, exclude=None, flash_seconds=0.3):
    """Like apply_effect_color, but forces a brief black transition first.

    Some devices silently ignore a resend of the exact same mode+color -- the
    write is treated as a no-op and never reaches the hardware. That matters
    here for reverts (leaving the Gaming profile, or an agent session going
    idle) where the target state can be byte-identical to what OpenRGB already
    believes is applied while the physical LEDs have drifted.
    """
    black = RGBColor(0, 0, 0)
    for dev in client.devices:
        if exclude and any(pat.lower() in dev.name.lower() for pat in exclude if pat):
            continue
        try:
            off_mode = _off_mode_for(dev)
            if off_mode:
                dev.set_mode(off_mode)
            push_color(dev, black)
        except Exception:
            pass  # best-effort flash; the real apply below reports real errors
    time.sleep(flash_seconds)
    return apply_effect_color(client, effect, color, exclude=exclude)


def _effect_for_mode(dev, mode_name):
    """Reverse-lookup: which logical effect(s) does this real mode express.
    More than one can match (a hub whose only per-LED mode serves as both
    static and breathing), so report all of them rather than silently picking
    one -- that ambiguity is what made state hard to read in the first place.
    """
    matches = [effect for effect in EFFECTS if resolve_mode(dev, effect) == mode_name]
    return "/".join(matches)


def read_current_state(client):
    """Read back what is ACTUALLY applied on every device right now.

    The plugin's own state file records what was last *requested*; if a
    device's write failed partway through a batch the hardware can be
    somewhere else entirely. This asks OpenRGB instead.
    """
    rows = []
    for dev in client.devices:
        mode = dev.modes[dev.active_mode]
        if mode.color_mode == ModeColors.MODE_SPECIFIC and mode.colors:
            rgb = to_hex(mode.colors[0])
        elif mode.color_mode == ModeColors.PER_LED:
            lit = [z for z in dev.zones if len(z.leds) > 0]
            rgb = to_hex(lit[0].colors[0]) if lit and lit[0].colors else None
        else:
            rgb = None
        rows.append({
            "device": dev.name,
            "mode": mode.name,
            "effect": _effect_for_mode(dev, mode.name) or "-",
            "leds": len(dev.leds),
            "color": rgb or "n/a (self-driven effect)",
        })
    return rows
