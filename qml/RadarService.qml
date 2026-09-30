import QtQuick
import Quickshell.Io
import "RadarModel.js" as RadarModel

Item {
  id: root
  visible: false
  property int refreshIntervalSec: 2
  property bool panelActive: false
  property bool includeDocker: true
  property string ignoredPorts: ""
  property string alwaysIncludePorts: ""
  property string selectedLanInterface: ""
  property alias servers: serverModel
  readonly property int serverCount: serverModel.count
  property int revision: 0
  property string lanIp: ""
  property string lanInterface: ""
  property string lanSubnet: ""
  property var lanInterfaces: []
  readonly property bool scanning: nativeDiscovery.scanning || dockerDiscovery.scanning
  readonly property string scanError: uidError || nativeDiscovery.scanError
  property string uidError: ""
  property string actionName: ""
  property string actionError: ""
  property string actionOutput: ""
  property string actionServerId: ""
  property var warnings: []
  property var dependencyWarnings: []
  property var diagnostics: []
  property string scanSummary: ""
  property int currentUid: -1
  property string ipOutput: ""
  property string routeWarning: ""
  property string resourceWarning: ""
  property var systemMemory: ({ totalBytes: -1, availableBytes: -1 })
  property var resourceByKey: ({})
  property var memoryHistoryByKey: ({})
  property real lastNativeResourceScanMs: 0
  property real lastDockerResourceScanMs: 0
  property bool resourceRescanQueued: false
  property bool dockerResourceRescanQueued: false
  property string resourceOutput: ""
  property string dockerResourceOutput: ""
  readonly property int nativeResourceIntervalMs: panelActive ? 2000 : 15000
  readonly property int dockerResourceIntervalMs: panelActive ? 8000 : 30000
  readonly property int dockerDiscoveryIntervalSec: Math.max(refreshIntervalSec, panelActive ? 5 : 15)
  readonly property string helperPath: decodeURIComponent(
    String(Qt.resolvedUrl("../localhost_helper.py")).replace(/^file:\/\//, ""))

  signal actionFinished(string action, bool successful, string detail, string serverId)
  ListModel { id: serverModel }

  function arraysEqual(left, right) { return JSON.stringify(left || []) === JSON.stringify(right || []) }

  function publishServers() {
    if (!nativeDiscovery || !dockerDiscovery) return
    var entries = nativeDiscovery.readyContexts.concat(includeDocker ? dockerDiscovery.readyContexts : [])
    var nextServers = []
    var activeKeys = {}
    for (var i = 0; i < entries.length; i++) {
      var entry = entries[i]
      var server = RadarModel.serverFromContext(entry.context, entry.scheme,
        { ip: lanIp, interfaceName: lanInterface, subnet: lanSubnet }, lanInterfaces)
      var key = RadarModel.memorySourceKey(server)
      activeKeys[key] = true
      server.memoryBytes = resourceByKey[key] === undefined ? -1 : resourceByKey[key]
      server.memoryHistory = memoryHistoryByKey[key] || []
      nextServers.push(server)
    }
    var nextResources = {}
    var nextHistory = {}
    for (var key in activeKeys) {
      if (resourceByKey[key] !== undefined) nextResources[key] = resourceByKey[key]
      if (memoryHistoryByKey[key]) nextHistory[key] = memoryHistoryByKey[key]
    }
    resourceByKey = nextResources
    memoryHistoryByKey = nextHistory
    nextServers.sort(function(a, b) { return a.port - b.port || a.name.toLowerCase().localeCompare(b.name.toLowerCase()) })
    if (RadarModel.syncServerModel(serverModel, nextServers)) revision++
    var nextDiagnostics = nativeDiscovery.diagnostics.concat(includeDocker ? dockerDiscovery.diagnostics : []).slice(0, 30)
    if (!arraysEqual(diagnostics, nextDiagnostics)) diagnostics = nextDiagnostics
    var nextWarnings = dependencyWarnings.concat(routeWarning ? [routeWarning] : [],
      resourceWarning ? [resourceWarning] : [], nativeDiscovery.warnings, includeDocker ? dockerDiscovery.warnings : [])
    nextWarnings = nextWarnings.filter(function(value, index, all) { return all.indexOf(value) === index })
    if (!arraysEqual(warnings, nextWarnings)) warnings = nextWarnings
    var listeners = nativeDiscovery.listenerCount
    var candidates = nativeDiscovery.candidateCount + (includeDocker ? dockerDiscovery.candidateCount : 0)
    scanSummary = listeners + " owned listener" + (listeners === 1 ? "" : "s")
      + " · " + candidates + " candidate" + (candidates === 1 ? "" : "s")
      + " · " + nextServers.length + " browser-ready"
    sampleResources(false)
  }

  function refresh() { scan(true); sampleResources(true) }
  function scan(manual) {
    nativeDiscovery.scan(manual)
    dockerDiscovery.scan(manual)
  }

  function sampleResources(force, source) {
    if (currentUid < 0) return
    var now = Date.now()
    var pids = []
    var containers = []
    var keys = []
    var missingNative = false
    var missingDocker = false
    for (var i = 0; i < serverModel.count; i++) {
      var server = serverModel.get(i)
      var key = RadarModel.memorySourceKey(server)
      keys.push(key)
      if (server.source === "docker") {
        if (containers.indexOf(server.containerId) === -1) containers.push(server.containerId)
        if (resourceByKey[key] === undefined) missingDocker = true
      } else {
        if (pids.indexOf(String(server.pid)) === -1) pids.push(String(server.pid))
        if (resourceByKey[key] === undefined) missingNative = true
      }
    }
    var nextResources = Object.assign({}, resourceByKey)
    if (source !== "docker" && (force || missingNative || now - lastNativeResourceScanMs >= nativeResourceIntervalMs)) {
      if (resourceProcess.running) {
        if (force || missingNative) resourceRescanQueued = true
      } else {
        lastNativeResourceScanMs = now
        for (var k = 0; k < keys.length; k++)
          if (keys[k].indexOf("process:") === 0 && nextResources[keys[k]] === undefined) nextResources[keys[k]] = -1
        resourceOutput = ""
        resourceProcess.command = ["python3", helperPath, "resources", "--pids", pids.join(","), "--uid", String(currentUid)]
        resourceProcess.running = true
      }
    }
    if (source !== "process" && includeDocker && containers.length
        && (force || missingDocker || now - lastDockerResourceScanMs >= dockerResourceIntervalMs)) {
      if (dockerMemoryProcess.running) {
        if (force || missingDocker) dockerResourceRescanQueued = true
      } else {
        lastDockerResourceScanMs = now
        for (var d = 0; d < keys.length; d++)
          if (keys[d].indexOf("docker:") === 0 && nextResources[keys[d]] === undefined) nextResources[keys[d]] = -1
        dockerResourceOutput = ""
        dockerMemoryProcess.command = ["python3", helperPath, "resources", "--pids", "", "--uid", String(currentUid),
          "--containers", containers.join(","), "--no-system"]
        dockerMemoryProcess.running = true
      }
    }
    resourceByKey = nextResources
  }

  function finishResourceSample(raw, docker, exitCode) {
    if (docker && !includeDocker) return
    var parsed = RadarModel.parseResourcePayload(raw, currentUid)
    if (exitCode !== 0 || !parsed.ok) {
      if (!docker) resourceWarning = "RAM sampling is unavailable"
    } else {
      if (!docker) { systemMemory = parsed.systemMemory; resourceWarning = "" }
      var nextResources = Object.assign({}, resourceByKey)
      var nextHistory = Object.assign({}, memoryHistoryByKey)
      for (var key in parsed.memory) {
        var bytes = parsed.memory[key]
        nextResources[key] = bytes
        nextHistory[key] = bytes < 0 ? [] : (nextHistory[key] || []).concat([bytes]).slice(-30)
      }
      resourceByKey = nextResources
      memoryHistoryByKey = nextHistory
    }
    publishServers()
    if (docker ? dockerResourceRescanQueued : resourceRescanQueued) {
      if (docker) dockerResourceRescanQueued = false
      else resourceRescanQueued = false
      sampleResources(true, docker ? "docker" : "process")
    }
  }

  function runAction(action, server) {
    if (!server || actionProcess.running) return
    if (action === "restart" && !RadarModel.actionEnabled(RadarModel.ACTIONS.restart, server)) return
    actionName = action
    actionError = ""
    actionOutput = ""
    actionServerId = String(server.serverId || server.id || "")
    if (server.source === "docker" && server.containerId) {
      if (action === "force-stop") action = "stop"
      actionProcess.command = [
        "python3", helperPath, "docker-action", "--action", action,
        "--id", String(server.containerId)
      ]
      actionProcess.running = true
      return
    }
    actionProcess.command = [
      "python3", helperPath, "process-action", "--action", action,
      "--pid", String(server.pid), "--start-time", String(server.startTime),
      "--url", String(server.localUrl)
    ]
    actionProcess.running = true
  }

  function stop(server) { runAction("stop", server) }
  function forceStop(server) { runAction("force-stop", server) }
  function restart(server) { runAction("restart", server) }


  onPanelActiveChanged: if (panelActive) sampleResources(true)
  onSelectedLanInterfaceChanged: if (!ipProcess.running) ipProcess.running = true

  Component.onCompleted: {
    dependencyProcess.running = true
    uidProcess.running = true
    ipProcess.running = true
  }

  RadarDiscovery {
    id: nativeDiscovery
    objectName: "nativeDiscovery"
    source: "process"
    currentUid: root.currentUid
    helperPath: root.helperPath
    intervalSec: root.refreshIntervalSec
    ignoredPorts: root.ignoredPorts
    alwaysIncludePorts: root.alwaysIncludePorts
    onResultsChanged: root.publishServers()
  }
  RadarDiscovery {
    id: dockerDiscovery
    objectName: "dockerDiscovery"
    source: "docker"
    discoveryEnabled: root.includeDocker
    currentUid: root.currentUid
    helperPath: root.helperPath
    intervalSec: root.dockerDiscoveryIntervalSec
    ignoredPorts: root.ignoredPorts
    alwaysIncludePorts: root.alwaysIncludePorts
    onResultsChanged: root.publishServers()
  }
  Timer {
    interval: root.nativeResourceIntervalMs
    running: root.currentUid >= 0
    repeat: true
    onTriggered: root.sampleResources(false)
  }
  Timer {
    interval: 60000
    running: true
    repeat: true
    onTriggered: if (!ipProcess.running) ipProcess.running = true
  }
  Timer {
    id: postActionScan
    interval: 450
    repeat: false
    onTriggered: root.refresh()
  }

  Process {
    id: dependencyProcess
    command: [
      "bash", "-c",
      "for command in ss ip curl python3 wl-copy qrencode; do command -v \"$command\" >/dev/null 2>&1 || echo \"$command\"; done"
    ]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var missing = String(text || "").trim().split(/\r?\n/).filter(function(value) { return value !== "" })
        var nextWarnings = []
        for (var index = 0; index < missing.length; index++)
          nextWarnings.push("Missing required command: " + missing[index])
        root.dependencyWarnings = nextWarnings
      }
    }
  }

  Process {
    id: uidProcess
    command: ["id", "-u"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.currentUid = Number(String(text || "").trim())
    }
    onExited: function(exitCode) {
      if (exitCode !== 0 || root.currentUid < 0) root.uidError = "Could not determine the current user"
      else root.scan()
    }
  }

  Process {
    id: ipProcess
    command: ["bash", "-c", "ip -j -4 route show && ip -j -4 address show up"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.ipOutput = String(text || "")
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.lanIp = ""
        root.lanInterface = ""
        root.lanSubnet = ""
        root.lanInterfaces = []
        root.routeWarning = "LAN route information is unavailable"
        root.scan()
        return
      }
      var parts = root.ipOutput.trim().split(/\r?\n/)
      var route = RadarModel.parseLanRoute(parts[0], parts[1], root.selectedLanInterface)
      root.lanInterfaces = RadarModel.parseLanInterfaces(parts[0], parts[1])
      root.lanIp = route.ip
      root.lanInterface = route.interfaceName
      root.lanSubnet = route.subnet
      root.routeWarning = route.ip ? "" : (root.selectedLanInterface
        ? "No active IPv4 address on LAN interface " + root.selectedLanInterface
        : "No active IPv4 LAN route was found")
      root.scan()
    }
  }


  Process {
    id: resourceProcess
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.resourceOutput = String(text || "") }
    onExited: function(exitCode) { root.finishResourceSample(root.resourceOutput, false, exitCode) }
  }
  Process {
    id: dockerMemoryProcess
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.dockerResourceOutput = String(text || "") }
    onExited: function(exitCode) { root.finishResourceSample(root.dockerResourceOutput, true, exitCode) }
  }

  Process {
    id: actionProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.actionOutput = String(text || "")
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.actionError = String(text || "").trim()
    }
    onExited: function(exitCode) {
      var action = root.actionName
      var parsed = RadarModel.parseActionPayload(
        root.actionOutput,
        root.actionError || (exitCode === 0 ? "Action completed" : "Server action failed"))
      var successful = exitCode === 0 && parsed.ok
      root.actionFinished(action, successful, parsed.message, root.actionServerId)
      root.actionName = ""
      root.actionServerId = ""
      postActionScan.restart()
    }
  }
}
