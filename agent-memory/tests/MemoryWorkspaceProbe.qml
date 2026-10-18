import QtQuick
import Quickshell
import qs.modules.plugins.agentMemory

// Instantiates the workspace plane against a folded fixture store. A plane
// whose bindings throw still "loads", so the runner also scans the log for
// ReferenceError and TypeError lines.
ShellRoot {
    id: root

    property var plane: null
    property int ticks: 0

    function pass(message: string): void {
        console.log(`PASS: ${message}`);
    }

    function fail(message: string): void {
        console.error(`FAIL: ${message}`);
        Qt.callLater(Qt.quit);
    }

    Component {
        id: planeComponent

        MemoryWorkspace {
            width: 1400
            height: 820
        }
    }

    Component.onCompleted: {
        root.plane = planeComponent.createObject(null);
        if (!root.plane) {
            root.fail("the workspace plane did not instantiate");
            return;
        }
        root.pass("the workspace plane instantiated");
    }

    Timer {
        interval: 100
        repeat: true
        running: root.plane !== null

        onTriggered: {
            root.ticks += 1;
            if (root.plane.projectRows.length === 0 && root.ticks < 150)
                return;
            if (root.plane.projectRows.length === 0) {
                root.fail("the plane never read the folded store");
                return;
            }
            root.pass("the plane read the folded store");
            // A colour binding that throws leaves the property at opaque
            // black, which is what a broken plane looks like on screen.
            const lit = c => c.r + c.g + c.b > 0;
            if (lit(root.plane.panelColour) && lit(root.plane.textPrimary))
                root.pass("the plane's palette resolved");
            else
                root.fail("the plane's palette is undefined");
            root.plane.selectedProject = "/repo";
            if (root.plane.toolRows.length > 0)
                root.pass("the selected project lists its tools");
            else
                root.fail("the selected project lists no tools");
            running = false;
            Qt.callLater(Qt.quit);
        }
    }
}
