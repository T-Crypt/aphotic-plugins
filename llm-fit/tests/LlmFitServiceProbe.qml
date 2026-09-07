import QtQuick
import Quickshell
import qs.modules.plugins.llmFit

ShellRoot {
    id: root

    property bool scanStarted: false
    readonly property bool expectFailure: Quickshell.env("LLMFIT_TEST_EXPECT_FAILURE") === "1"

    function finish(): void {
        if (root.expectFailure) {
            if (LlmFitService.errorText.length === 0) {
                console.error("FAIL: an unlaunchable llmfit executable did not report an error");
                Qt.quit();
                return;
            }
            console.log("PASS: failed llmfit launch returns the advisor to idle");
            Qt.quit();
            return;
        }
        if (LlmFitService.errorText.length > 0) {
            console.error(`FAIL: ${LlmFitService.errorText}`);
            Qt.quit();
            return;
        }
        if (LlmFitService.systemInfo?.cpu_name !== "Test CPU" || LlmFitService.recommendations.length !== 1) {
            console.error("FAIL: successful scan did not publish its results");
            Qt.quit();
            return;
        }
        console.log("PASS: successful llmfit scan publishes recommendations");
        Qt.quit();
    }

    Connections {
        target: LlmFitService

        function onCheckedChanged(): void {
            if (!LlmFitService.checked)
                return;
            if (!LlmFitService.available) {
                console.error("FAIL: controlled llmfit executable was not found");
                Qt.quit();
                return;
            }
            root.scanStarted = true;
            LlmFitService.scan();
        }

        function onScanningChanged(): void {
            if (root.scanStarted && !LlmFitService.scanning)
                Qt.callLater(root.finish);
        }
    }

    Timer {
        interval: 10000
        running: true
        onTriggered: {
            console.error(`FAIL: timed out waiting for ${root.expectFailure ? "failed" : "successful"} llmfit scan`);
            Qt.quit();
        }
    }
}
