import QtQuick
import Quickshell.Io

Item {
  id: root
  visible: false

  property int refreshIntervalSec: 2
  property alias servers: serverModel
  readonly property int serverCount: serverModel.count
  property string lanIp: ""
  property bool scanning: false
  property string scanError: ""
  property bool scanQueued: false
  property string actionName: ""
  property string actionError: ""

  signal actionFinished(string action, bool successful, string detail)

  readonly property string backendPath: decodeURIComponent(
    String(Qt.resolvedUrl("scripts/radar.py")).replace(/^file:\/\//, ""))

  ListModel { id: serverModel }

  function normalizedServer(server) {
    return {
      serverId: String(server.id || ""),
      name: String(server.name || "Development server"),
      framework: String(server.framework || "Dev server"),
      frameworkId: String(server.frameworkId || "server"),
      pid: Number(server.pid || 0),
      port: Number(server.port || 0),
      cwd: String(server.cwd || ""),
      localUrl: String(server.localUrl || ""),
      lanUrl: String(server.lanUrl || ""),
      lanAvailable: server.lanAvailable === true,
      hint: String(server.hint || "")
    }
  }

  function modelIndex(serverId) {
    for (var i = 0; i < serverModel.count; i++) {
      if (serverModel.get(i).serverId === serverId) return i
    }
    return -1
  }

  // Keep delegates stable across scans. Updating the old array wholesale made
  // ListView recreate every row, so one newcomer looked like the entire list
  // had reloaded. This keyed diff inserts/removes only what actually changed.
  function syncServers(nextServers) {
    var incoming = {}
    var normalized = []
    for (var i = 0; i < nextServers.length; i++) {
      var server = normalizedServer(nextServers[i])
      if (server.serverId === "") continue
      incoming[server.serverId] = true
      normalized.push(server)
    }

    for (var oldIndex = serverModel.count - 1; oldIndex >= 0; oldIndex--) {
      if (!incoming[serverModel.get(oldIndex).serverId]) serverModel.remove(oldIndex)
    }

    for (var targetIndex = 0; targetIndex < normalized.length; targetIndex++) {
      var next = normalized[targetIndex]
      var currentIndex = modelIndex(next.serverId)
      if (currentIndex === -1) {
        serverModel.insert(targetIndex, next)
      } else {
        if (currentIndex !== targetIndex) serverModel.move(currentIndex, targetIndex, 1)
        serverModel.set(targetIndex, next)
      }
    }
  }

  function scan() {
    if (scanProcess.running) {
      scanQueued = true
      return
    }
    scanning = true
    scanProcess.command = ["python3", backendPath, "scan"]
    scanProcess.running = true
  }

  function applyScan(raw) {
    try {
      var payload = JSON.parse(String(raw || "{}"))
      syncServers(Array.isArray(payload.servers) ? payload.servers : [])
      lanIp = String(payload.lanIp || "")
      scanError = ""
    } catch (exception) {
      scanError = "Localhost returned an unreadable scan"
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
        if (detail !== "") root.scanError = detail
      }
    }

    onExited: function(exitCode) {
      root.scanning = false
      if (exitCode !== 0 && root.scanError === "") root.scanError = "Could not scan local ports"
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
