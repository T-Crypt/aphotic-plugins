"""Minimal stand-in for openrgb-python, shaped like the parts rgb_common.py uses.

The interesting half is _devices(): five controllers modelled on the real
hardware shapes that produced every bug the ported logic exists to fix -- a
GPU whose only colorable mode is Direct and whose single zone is a fixed
1-LED type, a motherboard with a real PER_LED Breathing, a fan hub whose
Static is MODE_SPECIFIC and whose only PER_LED mode is Custom, DRAM whose
breathing is a MODE_SPECIFIC Color Pulse, and one controller that throws on
every write. FAKE_REFUSE and FAKE_NO_DEVICES cover the two connection
failure shapes (server down, and the udev-denied "connected with zero
devices" case).
"""
import os
from .utils import RGBColor, ModeColors

TRACE = []

class Mode:
    def __init__(self, name, color_mode):
        self.name, self.color_mode, self.colors = name, color_mode, []

class Zone:
    def __init__(self, name, count, fixed=False, flaky=False):
        self.name, self.leds, self.colors, self.fixed = name, [0] * count, [RGBColor(0, 0, 0)] * count, fixed
        self.flaky = flaky
    def set_colors(self, colors, fast=False):
        if self.flaky:
            raise RuntimeError("HID write failed (simulated transient)")
        self.colors = colors
        TRACE.append(("zone_set", self.name, colors[0], fast))
    def resize(self, n):
        if self.fixed:
            raise RuntimeError("zone is a fixed single-LED type")
        self.leds, self.colors = [0] * n, [RGBColor(0, 0, 0)] * n
        TRACE.append(("resize", self.name, n))

class Device:
    def __init__(self, name, modes, zones, flaky=False):
        self.name, self.modes, self.zones, self.flaky = name, modes, zones, flaky
        self.active_mode = 0
        self.leds = [l for z in zones for l in z.leds]
    def set_mode(self, name):
        if self.flaky:
            raise RuntimeError("HID write failed (simulated transient)")
        self.active_mode = [m.name for m in self.modes].index(name)
        TRACE.append(("set_mode", self.name, name))
    def set_color(self, color):
        self.modes[self.active_mode].colors = [color]
        TRACE.append(("dev_set_color", self.name, color))

def _devices():
    if os.environ.get("FAKE_NO_DEVICES"):
        return []
    return [
        # GPU over I2C: Direct only, per-LED, one fixed single-LED zone.
        Device("NVIDIA RTX 4090", [Mode("Direct", ModeColors.PER_LED),
                                   Mode("Rainbow Wave", ModeColors.NONE)],
               [Zone("GPU", 1, fixed=True)]),
        # Motherboard: has Static and a real Breathing.
        Device("MSI Z790 Motherboard", [Mode("Static", ModeColors.PER_LED),
                                        Mode("Breathing", ModeColors.PER_LED),
                                        Mode("Rainbow wave", ModeColors.NONE)],
               [Zone("JRGB1", 1), Zone("JRAINBOW1", 0)]),
        # Fan hub: Static is MODE_SPECIFIC (one color for the whole device),
        # its only PER_LED mode is Custom, and it has no colorable breathing.
        Device("Lian Li SL Infinity", [Mode("Custom", ModeColors.PER_LED),
                                       Mode("Static", ModeColors.MODE_SPECIFIC),
                                       Mode("Breathing", ModeColors.NONE)],
               [Zone("Channel 1", 32), Zone("Channel 2", 32), Zone("Channel 3", 0)]),
        # DRAM over SMBus: MODE_SPECIFIC Color Pulse as its breathing.
        Device("Corsair Vengeance", [Mode("Direct", ModeColors.PER_LED),
                                     Mode("Color Pulse", ModeColors.MODE_SPECIFIC)],
               [Zone("DIMM 1", 10)]),
        # A device that throws on every write, sitting mid-list.
        Device("Flaky HID Controller", [Mode("Direct", ModeColors.PER_LED)],
               [Zone("Cable", 20, flaky=True)], flaky=True),
    ]

class OpenRGBClient:
    def __init__(self, address="127.0.0.1", port=6742, name=""):
        if os.environ.get("FAKE_REFUSE"):
            raise ConnectionRefusedError("[Errno 111] Connection refused")
        self.devices = _devices()
        TRACE.append(("connect", name))
