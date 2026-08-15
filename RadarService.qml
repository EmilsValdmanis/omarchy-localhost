import QtQuick
import Quickshell.Io

Item {
  id: root
  visible: false

  property int refreshIntervalSec: 2
  property var servers: []
  property string lanIp: ""
  property bool loading: false
  property string error: ""
  property bool scanQueued: false
  property string actionName: ""
  property string actionError: ""

  signal actionFinished(string action, bool successful, string detail)

  readonly property string backendPath: decodeURIComponent(
    String(Qt.resolvedUrl("scripts/radar.py")).replace(/^file:\/\//, ""))

  function scan() {
    if (scanProcess.running) {
      scanQueued = true
      return
    }
    loading = true
    scanProcess.command = ["python3", backendPath, "scan"]
    scanProcess.running = true
  }

  function applyScan(raw) {
    try {
      var payload = JSON.parse(String(raw || "{}"))
      servers = Array.isArray(payload.servers) ? payload.servers : []
      lanIp = String(payload.lanIp || "")
      error = ""
    } catch (exception) {
      error = "Localhost returned an unreadable scan"
    }
  }

  function runAction(action, server) {
    if (!server || actionProcess.running) return
    actionName = action
    actionError = ""
    actionProcess.command = ["python3", backendPath, action, String(server.pid)]
    actionProcess.running = true
  }

  function stop(server) { runAction("stop", server) }
  function restart(server) { runAction("restart", server) }

  Timer {
    interval: Math.max(1, root.refreshIntervalSec) * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.scan()
  }

  Timer {
    id: postActionScan
    interval: 450
    repeat: false
    onTriggered: root.scan()
  }

  Process {
    id: scanProcess
    running: false

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyScan(text)
    }

    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var detail = String(text || "").trim()
        if (detail !== "") root.error = detail
      }
    }

    onExited: function(exitCode) {
      root.loading = false
      if (exitCode !== 0 && root.error === "") root.error = "Could not scan local ports"
      if (root.scanQueued) {
        root.scanQueued = false
        Qt.callLater(root.scan)
      }
    }
  }

  Process {
    id: actionProcess
    running: false

    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.actionError = String(text || "").trim()
    }

    onExited: function(exitCode) {
      var action = root.actionName
      var successful = exitCode === 0
      var detail = successful
        ? (action === "restart" ? "Server restarted" : "Server stopped")
        : (root.actionError || "Server action failed")
      root.actionFinished(action, successful, detail)
      root.actionName = ""
      postActionScan.restart()
    }
  }
}
