// SPDX-License-Identifier: GPL-3.0-only
// SPDX-FileCopyrightText: Aphotic-Hypr contributors

pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.services.ai

// The pet's own read of the harness event bus. A third subscriber to
// `AgentEvents`, not a second tail of `agent-events.jsonl` -- see
// `AgentGraphService.qml` in the agent-graph plugin for the same
// `Connections { target: AgentEvents }` + `hold()` shape this copies.
//
// `mood` is "" on a quiet desktop and one of "working" / "waitingProcess"
// / "attentionRequired" / "compacting" / "complete" / "error" while a
// harness session has something to show. Pet.qml treats a non-empty
// value as an override of its own idle/walk/react/fidget/sleep
// vocabulary -- see the comment there.
//
// `_nextBucket` and `_moodFor` are pure and exported for the same reason
// `AgentEvents.applyTo` is: a probe can drive them with synthetic events
// and a synthetic clock without touching the live tail, which matters
// here because this file cannot be exercised by literally waiting for a
// real tool call to run long enough to test the waiting/complete/error
// transitions.
Singleton {
    id: root

    // How long a tool call runs before the pet stops looking like it just
    // reacted to something (`working`) and starts looking like it is
    // waiting on a real result (`waitingProcess`). Short enough that a
    // one-shot `Read` still reads as instant, long enough that most tool
    // calls never cross it.
    readonly property int waitingThresholdMs: 1500

    // How long the pet holds a finished-turn pose before an idle desktop
    // takes back over. `stop`/`session_end` both light this rather than
    // one specific event, because a session can end on either.
    readonly property int flashDurationMs: 2200

    readonly property string mood: root._mood

    // The current session's own working directory, or "" -- all
    // `AgentWindowFocus.focusByCwd()` (core, `qs.services.ai`) needs to
    // turn `attentionRequired` into a click that focuses the window
    // behind it. Not part of `_mood`'s own state machine: it just rides
    // along on whichever bucket is current, same as `mood` itself.
    readonly property string cwd: root._current.length === 0 ? "" : (root._bucketFor(root._current).cwd || "")

    property string _mood: ""

    // One bucket per session that has ever sent an event this shell has
    // seen, keyed by sessionId. `_current` is whichever session most
    // recently sent one -- the same "most recently updated live session"
    // rule `AgentEvents.activeSession` uses, computed locally off event
    // arrival order instead of off that reactive property. Reading
    // `AgentEvents.activeSession` directly here would race: a
    // `session_end` retires the session from `liveSessions` as part of
    // the same write that is about to fire `record` for that very event,
    // so a gate on "is this still the active session" would throw away
    // the complete/error flash for the session that just ended.
    property var _sessions: ({})
    property string _current: ""

    function _initialBucket(): var {
        return {
            pending: ({}),
            workingSince: 0,
            attention: false,
            hadFailure: false,
            flash: ({ kind: "", until: 0 }),
            compacting: false,
            cwd: ""
        };
    }

    // Pure: same bucket in, same event in, same bucket out, every time.
    function _nextBucket(bucket: var, event: var, now: real): var {
        const next = {
            pending: Object.assign({}, bucket.pending),
            workingSince: bucket.workingSince,
            attention: bucket.attention,
            hadFailure: bucket.hadFailure,
            flash: bucket.flash,
            compacting: bucket.compacting,
            // Sticky for the bucket's whole life, not just the event that
            // happened to carry it -- a `notification` firing `attention`
            // is not guaranteed to be the same event that last carried
            // `cwd` (it wasn't, until agent_hook.py started forwarding
            // Claude Code's own `cwd` hook field to every event, but
            // nothing here should depend on that always being true).
            cwd: event.cwd || bucket.cwd
        };

        switch (event.event) {
        case "pre_tool_use": {
            // Forward progress resolves whatever the pet was waiting on.
            next.attention = false;
            const key = event.toolId || `t${event.t ?? now}`;
            next.pending[key] = event.t ?? now;
            if (Object.keys(next.pending).length === 1)
                next.workingSince = next.pending[key];
            break;
        }
        case "post_tool_use":
            if (event.toolId)
                delete next.pending[event.toolId];
            if (Object.keys(next.pending).length === 0)
                next.workingSince = 0;
            break;
        case "post_tool_use_failure":
            if (event.toolId)
                delete next.pending[event.toolId];
            if (Object.keys(next.pending).length === 0)
                next.workingSince = 0;
            // Sticky until the next turn boundary, which is what tells
            // `stop`/`session_end` below to flash error instead of complete.
            next.hadFailure = true;
            break;
        case "notification":
            next.attention = true;
            break;
        // No harness wires these yet (`PETS.md` §4.3, `PET-14`) -- handled
        // now so nothing here needs to change the day one does.
        case "pre_compact":
            next.compacting = true;
            break;
        case "post_compact":
            next.compacting = false;
            break;
        case "stop":
        case "session_end":
            next.flash = {
                kind: next.hadFailure ? "error" : "complete",
                until: now + root.flashDurationMs
            };
            next.hadFailure = false;
            next.attention = false;
            next.pending = ({});
            next.workingSince = 0;
            next.compacting = false;
            break;
        default:
            break;
        }

        return next;
    }

    // Pure: what the pet should show for one bucket at one instant.
    // Priority order matters -- an approval prompt outranks a stale
    // finished-turn flash, which outranks a tool still running.
    function _moodFor(bucket: var, now: real): string {
        if (bucket.attention)
            return "attentionRequired";
        if (bucket.flash.kind.length > 0 && now < bucket.flash.until)
            return bucket.flash.kind;
        if (bucket.compacting)
            return "compacting";
        const pendingCount = Object.keys(bucket.pending).length;
        if (pendingCount > 0)
            return now - bucket.workingSince > root.waitingThresholdMs ? "waitingProcess" : "working";
        return "";
    }

    function _bucketFor(id: string): var {
        return root._sessions[id] ?? root._initialBucket();
    }

    function _recompute(): void {
        root._mood = root._current.length === 0 ? "" : root._moodFor(root._bucketFor(root._current), Date.now());
    }

    // Whether anything about the current bucket still changes on its own
    // (a flash expiring, working turning into waitingProcess) rather than
    // only in response to the next event -- what the ticking timer below
    // is for.
    readonly property bool _ticking: {
        if (root._current.length === 0)
            return false;
        const bucket = root._bucketFor(root._current);
        return Object.keys(bucket.pending).length > 0 || bucket.flash.kind.length > 0;
    }

    Connections {
        target: AgentEvents

        function onRecord(event: var): void {
            if (!event || !event.sessionId || !event.event)
                return;
            const bucket = root._nextBucket(root._bucketFor(event.sessionId), event, Date.now());
            const sessions = Object.assign({}, root._sessions);
            sessions[event.sessionId] = bucket;
            root._sessions = sessions;
            root._current = event.sessionId;
            root._recompute();
        }
    }

    Timer {
        interval: 250
        running: root._ticking
        repeat: true
        onTriggered: root._recompute()
    }

    // Forgets a session's bucket once nothing about it is live and its
    // flash (if it had one) is long over, so a shell left running for
    // days doesn't grow this map forever.
    Timer {
        interval: 60000
        running: Object.keys(root._sessions).length > 0
        repeat: true
        onTriggered: {
            const cutoff = Date.now() - 300000;
            const kept = ({});
            for (const id in root._sessions) {
                const bucket = root._sessions[id];
                const live = Object.keys(bucket.pending).length > 0 || bucket.attention || bucket.compacting || bucket.flash.until > cutoff;
                if (live || id === root._current)
                    kept[id] = bucket;
            }
            root._sessions = kept;
        }
    }

    // Held for the plugin's lifetime rather than on some presence toggle:
    // the pet is always on screen, so there is no moment it would be
    // correct to let this tail stop while still drawing a creature that
    // is supposed to reflect it.
    Component.onCompleted: AgentEvents.hold("pet", true)
}
