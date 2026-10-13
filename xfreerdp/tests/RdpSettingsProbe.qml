import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.plugins.xfreerdp

// Drives RdpSettings headlessly and prints one PASS or FAIL line per claim,
// which tests/test_rdp_settings.sh greps. Offscreen and windowless: this
// only ever instantiates the plugin's own state holder, never the pane, so
// nothing here needs the shell's service graph or a compositor.
//
// Three cases, chosen by XFREERDP_TEST_CASE:
//   defaults  no settings file at all: the shipped defaults are the answer
//   merge     a partial file merges over them key by key, and an edit is
//             written back as a whole document
//   status    the status read, once with a stub `aphotic` on PATH and once
//             with none (XFREERDP_TEST_EXPECT=running|unknown)
ShellRoot {
    id: root

    readonly property string testCase: Quickshell.env("XFREERDP_TEST_CASE") ?? "defaults"
    readonly property string expectation: Quickshell.env("XFREERDP_TEST_EXPECT") ?? "running"

    property bool started: false
    property int ticks: 0

    function check(ok: bool, label: string): void {
        if (ok) {
            console.log(`PASS: ${label}`);
            return;
        }
        console.error(`FAIL: ${label}`);
    }

    function checkDefaults(): void {
        const defaults = RdpSettings.defaultSettings;
        root.check(RdpSettings._settled, "the settings read resolved");
        root.check(defaults.window.class === "work-rdp", "the default window class is work-rdp");
        root.check(defaults.sec === "nla", "the default security is NLA");
        root.check(defaults.cert === "ignore", "the default certificate handling is ignore");
        root.check(defaults.resolution.mode === "dynamic", "the default resolution mode is dynamic");
        root.check(defaults.resolution.width === 1920 && defaults.resolution.height === 1080, "the default size is 1920x1080");
        root.check(defaults.mic.enabled === true && defaults.camera.enabled === true, "microphone and camera default on");
        root.check(defaults.window.workspace === "none" && defaults.window.fullscreen === false, "no workspace pin and no fullscreen by default");
        root.check(defaults.keybind === undefined, "the settings schema carries no keybind key");
        root.check(!("keybind" in RdpSettings.settings), "no keybind key is resolved into the settings");
        Qt.quit();
    }

    function checkMerge(): void {
        const settings = RdpSettings.settings;
        root.check(RdpSettings._settled, "the settings read resolved");
        root.check(settings.host === "192.0.2.10", "the profile's host is read");
        root.check(settings.user === "EXAMPLE\\user", "the profile's user is read as typed");
        root.check(settings.window.workspace === "3", "the profile's workspace pin is read");
        // The partial file named one window key; every other default in
        // that same nested object has to survive it.
        root.check(settings.window.class === "work-rdp", "a partial window block keeps the default class");
        root.check(settings.window.gfx === "AVC420", "a partial window block keeps the default gfx");
        root.check(settings.window.grab_keyboard === true, "a partial window block keeps the default keyboard grab");
        root.check(settings.resolution.mode === "dynamic" && settings.resolution.width === 1920, "an absent resolution block keeps its defaults");
        root.check(settings.port === 3389, "an absent port keeps the default");
        root.check(settings.sec === "nla" && settings.cert === "ignore", "absent security keys keep their defaults");
        root.check(settings.speaker.device === "", "an absent speaker device stays empty");

        RdpSettings.set("host", "192.0.2.20");
        root.check(RdpSettings.settings.host === "192.0.2.20", "set() updates the host in memory");
        writeDelay.start();
    }

    function checkWritten(text: string): void {
        let data = null;
        try {
            data = JSON.parse(text);
        } catch (e) {
            data = null;
        }
        root.check(data !== null, "the settings file round-trips through JSON");
        if (data === null) {
            Qt.quit();
            return;
        }
        root.check(data.host === "192.0.2.20", "the host edit reached the file");
        root.check(data.window.workspace === "3", "the write kept the value the file already had");
        root.check(data.window.class === "work-rdp", "the write kept the defaults");
        root.check(data.resolution.width === 1920 && data.resolution.height === 1080, "the write kept the default size");
        root.check(!("keybind" in data), "the write introduced no keybind key");
        Qt.quit();
    }

    function checkStatus(): void {
        const known = RdpSettings.statusKnown;
        const running = RdpSettings.sessionRunning;
        if (root.expectation === "running") {
            root.check(known, "the status read answered");
            root.check(running, "a running session is reported as running");
        } else {
            root.check(!known, "no aphotic answers nothing, not an error");
            root.check(!running, "an unanswerable status is not reported as running");
        }
        Qt.quit();
    }

    Timer {
        interval: 100
        repeat: true
        running: true

        onTriggered: {
            root.ticks++;
            if (root.started)
                return;

            // The status read is itself the thing being waited on, so it
            // gets its own budget rather than the settle budget below.
            if (root.testCase === "status") {
                if (RdpSettings.statusKnown || root.ticks > 30) {
                    root.started = true;
                    root.checkStatus();
                }
                return;
            }

            if (RdpSettings._settled || root.ticks > 50) {
                root.started = true;
                if (root.testCase === "merge")
                    root.checkMerge();
                else
                    root.checkDefaults();
            }
        }
    }

    // FileView defers the write by a turn of its own, so the read-back is
    // held back rather than racing it.
    Timer {
        id: writeDelay

        interval: 300
        onTriggered: readProc.running = true
    }

    Process {
        id: readProc

        command: ["cat", RdpSettings.configPath]

        stdout: StdioCollector {
            onStreamFinished: root.checkWritten(text)
        }
    }

}
