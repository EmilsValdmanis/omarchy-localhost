import QtQuick
import "Actions.js" as Actions
import "Discovery.js" as Discovery
import "Diagnostics.js" as Diagnostics
import "Memory.js" as Memory
import "Network.js" as Network
import "Paths.js" as Paths
import "Servers.js" as Servers
import "Sources.js" as Sources

Item {
  id: root
  visible: false
  property int refreshIntervalSec: 2
  property bool panelActive: false
  property bool includeDocker: true
  property string ignoredPorts: ""
  property var skippedServices: ({})
  // The shell replaces the whole settings object even for unrelated bar changes.
  readonly property string skippedServiceSignature: JSON.stringify(skippedServices)
  onSkippedServiceSignatureChanged: publishServers()
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
  property string actionServerId: ""
  property string actionServerLabel: ""
  property string actionSourceKey: ""
  property var forceStopSourceKeys: ({})
  readonly property bool actionBusy: actionName !== "" || stoppingProjectRoot !== ""
  property string stoppingProjectRoot: ""
  property var projectStopQueue: []
  property int projectStopTotal: 0
  property int projectStopSucceeded: 0
  property var projectStopErrors: []
  property var warnings: []
  property var dependencyWarnings: []
  property var diagnostics: []
  property string scanSummary: ""
  property int currentUid: -1
  property string routeWarning: ""
  property string resourceWarning: ""
  property var systemMemory: ({ totalBytes: -1, availableBytes: -1 })
  property var resourceByKey: ({})
  property var memoryHistoryByKey: ({})
  property real lastNativeResourceScanMs: 0
  property real lastDockerResourceScanMs: 0
  property bool resourceRescanQueued: false
  property bool dockerResourceRescanQueued: false
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
    var servicePorts = Object.create(null)
    for (let i = 0; i < entries.length; i++) {
      let entry = entries[i]
      let server = Discovery.serverFromContext(entry.context, entry.scheme,
        { ip: lanIp, interfaceName: lanInterface, subnet: lanSubnet }, lanInterfaces)
      if (server.serviceKey && skippedServices[server.serviceKey]) {
        if (!servicePorts[server.serviceKey]) servicePorts[server.serviceKey] = []
        servicePorts[server.serviceKey].push(server.port)
        continue
      }
      let key = Sources.key(server)
      activeKeys[key] = true
      server.memoryBytes = resourceByKey[key] === undefined ? -1 : resourceByKey[key]
      server.memoryHistory = memoryHistoryByKey[key] || []
      nextServers.push(server)
    }
    var nextResources = {}
    var nextHistory = {}
    for (let key in activeKeys) {
      if (resourceByKey[key] !== undefined) nextResources[key] = resourceByKey[key]
      if (memoryHistoryByKey[key]) nextHistory[key] = memoryHistoryByKey[key]
    }
    resourceByKey = nextResources
    memoryHistoryByKey = nextHistory
    nextServers.sort(function(a, b) { return a.port - b.port || a.name.toLowerCase().localeCompare(b.name.toLowerCase()) })
    if (Servers.syncServerModel(serverModel, nextServers)) revision++
    var nextDiagnostics = nativeDiscovery.diagnostics.concat(includeDocker ? dockerDiscovery.diagnostics : [])
    nextDiagnostics.sort(function(a, b) { return a.port - b.port || String(a.process).localeCompare(String(b.process)) })
    nextDiagnostics = Diagnostics.serviceEntries(skippedServices, servicePorts).concat(nextDiagnostics)
    if (!arraysEqual(diagnostics, nextDiagnostics)) diagnostics = nextDiagnostics
    var nextWarnings = dependencyWarnings.concat(routeWarning ? [routeWarning] : [],
      resourceWarning ? [resourceWarning] : [], nativeDiscovery.warnings, includeDocker ? dockerDiscovery.warnings : [])
    nextWarnings = nextWarnings.filter(function(value, index, all) { return all.indexOf(value) === index })
    if (!arraysEqual(warnings, nextWarnings)) warnings = nextWarnings
    var listeners = nativeDiscovery.listenerCount
    var candidates = nativeDiscovery.candidateCount + (includeDocker ? dockerDiscovery.candidateCount : 0)
    var browserReady = nextServers.filter(function(server) { return !!server.localUrl }).length
    scanSummary = listeners + " owned listener" + (listeners === 1 ? "" : "s")
      + " · " + candidates + " candidate" + (candidates === 1 ? "" : "s")
      + " · " + browserReady + " browser-ready"
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
    for (let i = 0; i < serverModel.count; i++) {
      let server = serverModel.get(i)
      let key = Sources.key(server)
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
      if (resourceProcess.busy) {
        if (force || missingNative) resourceRescanQueued = true
      } else {
        lastNativeResourceScanMs = now
        for (let k = 0; k < keys.length; k++)
          if (Sources.belongsTo(keys[k], "process") && nextResources[keys[k]] === undefined) nextResources[keys[k]] = -1
        resourceProcess.start(["python3", helperPath, "resources", "--pids", pids.join(","), "--uid", String(currentUid)])
      }
    }
    if (source !== "process" && includeDocker && containers.length
        && (force || missingDocker || now - lastDockerResourceScanMs >= dockerResourceIntervalMs)) {
      if (dockerMemoryProcess.busy) {
        if (force || missingDocker) dockerResourceRescanQueued = true
      } else {
        lastDockerResourceScanMs = now
        for (let d = 0; d < keys.length; d++)
          if (Sources.belongsTo(keys[d], "docker") && nextResources[keys[d]] === undefined) nextResources[keys[d]] = -1
        dockerMemoryProcess.start(["python3", helperPath, "resources", "--pids", "", "--uid", String(currentUid),
          "--containers", containers.join(","), "--no-system"])
      }
    }
    resourceByKey = nextResources
  }

  function finishResourceSample(raw, docker, exitCode) {
    if (docker && !includeDocker) return
    var parsed = Memory.parseResourcePayload(raw, currentUid)
    var successful = exitCode === 0 && parsed.ok
    var source = docker ? "docker" : "process"
    var nextResources = Object.assign({}, resourceByKey)
    var nextHistory = Object.assign({}, memoryHistoryByKey)
    for (let key in nextResources) {
      if (Sources.belongsTo(key, source) && (!successful || parsed.memory[key] === undefined)) {
        nextResources[key] = -1
        nextHistory[key] = []
      }
    }
    if (!docker) {
      systemMemory = successful ? parsed.systemMemory : { totalBytes: -1, availableBytes: -1 }
      resourceWarning = successful ? "" : "RAM sampling is unavailable"
    }
    if (successful) {
      for (let key in parsed.memory) {
        if (!Sources.belongsTo(key, source)) continue
        let bytes = parsed.memory[key]
        nextResources[key] = bytes
        nextHistory[key] = bytes < 0 ? [] : (nextHistory[key] || []).concat([bytes]).slice(-Memory.HISTORY_LIMIT)
      }
    }
    resourceByKey = nextResources
    memoryHistoryByKey = nextHistory
    publishServers()
    if (docker ? dockerResourceRescanQueued : resourceRescanQueued) {
      if (docker) dockerResourceRescanQueued = false
      else resourceRescanQueued = false
      sampleResources(true, docker ? "docker" : "process")
    }
  }

  function runAction(action, server) {
    if (!server || actionBusy) return false
    if (action === "restart" && !Actions.actionEnabled(Actions.ACTIONS.restart, server)) return false
    startAction(action, server)
    return true
  }

  function startAction(action, server) {
    actionName = action
    actionServerId = String(server.serverId || server.id || "")
    actionServerLabel = server.name + " (:" + server.port + ")"
    actionSourceKey = Sources.key(server)
    if (server.source === "docker" && server.containerId) {
      if (action === "force-stop") action = "stop"
      actionProcess.start([
        "python3", helperPath, "docker-action", "--action", action,
        "--id", String(server.containerId)
      ])
      return
    }
    actionProcess.start([
      "python3", helperPath, "process-action", "--action", action,
      "--pid", String(server.pid), "--start-time", String(server.startTime),
      "--url", String(server.localUrl)
    ])
  }

  function stop(server) { runAction("stop", server) }
  function forceStop(server) { runAction("force-stop", server) }
  function restart(server) { runAction("restart", server) }

  function stopProject(projectRoot) {
    if (actionBusy) return false
    var rows = []
    for (let index = 0; index < serverModel.count; index++) rows.push(serverModel.get(index))
    var targets = Actions.projectStopTargets(rows, projectRoot)
    if (!targets.length) return false
    stoppingProjectRoot = projectRoot
    projectStopQueue = targets
    projectStopTotal = targets.length
    projectStopSucceeded = 0
    projectStopErrors = []
    runNextProjectStop()
    return true
  }

  function runNextProjectStop() {
    if (projectStopQueue.length) {
      let server = projectStopQueue[0]
      projectStopQueue = projectStopQueue.slice(1)
      startAction("stop", server)
      return
    }
    var name = Paths.basename(stoppingProjectRoot)
    var failed = projectStopErrors.length
    var detail = "Stopped " + projectStopSucceeded + "/" + projectStopTotal
      + " services in " + name + "."
    if (failed) detail += " " + failed + " failed: " + projectStopErrors[0]
    stoppingProjectRoot = ""
    actionFinished("stop-project", failed === 0, detail, "")
    refresh()
  }

  function finishAction(exitCode, raw, detail, failedToStart) {
    var action = actionName
    var parsed = Actions.parseActionPayload(raw,
      failedToStart ? "Could not start the server action helper"
        : (detail || (exitCode === 0 ? "Action completed" : "Server action failed")))
    var successful = exitCode === 0 && parsed.ok
    var serverId = actionServerId
    var label = actionServerLabel
    var sourceKey = actionSourceKey
    actionName = ""
    actionServerId = ""
    actionServerLabel = ""
    actionSourceKey = ""
    if ((!successful && parsed.forceStopAvailable)
        || (successful && forceStopSourceKeys[sourceKey])) {
      let next = Object.assign({}, forceStopSourceKeys)
      if (successful) delete next[sourceKey]
      else next[sourceKey] = true
      forceStopSourceKeys = next
    }
    if (stoppingProjectRoot !== "") {
      if (successful) projectStopSucceeded++
      else projectStopErrors = projectStopErrors.concat([label + ": " + parsed.message])
      actionFinished(action, successful, parsed.message, serverId)
      Qt.callLater(root.runNextProjectStop)
    } else {
      actionFinished(action, successful, parsed.message, serverId)
      refresh()
    }
  }

  onPanelActiveChanged: if (panelActive) sampleResources(true)
  onSelectedLanInterfaceChanged: if (!ipProcess.busy) ipProcess.start()

  Component.onCompleted: {
    dependencyProcess.start()
    uidProcess.start()
    ipProcess.start()
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
    onTriggered: if (!ipProcess.busy) ipProcess.start()
  }

  CommandProcess {
    id: dependencyProcess
    command: [
      "bash", "-c",
      "for command in ss ip curl python3 wl-copy qrencode; do command -v \"$command\" >/dev/null 2>&1 || echo \"$command\"; done"
    ]
    onCompleted: {
      var missing = output.trim().split(/\r?\n/).filter(function(value) { return value !== "" })
      root.dependencyWarnings = missing.map(function(name) { return "Missing required command: " + name })
      root.publishServers()
    }
  }

  CommandProcess {
    id: uidProcess
    command: ["id", "-u"]
    onCompleted: function(exitCode) {
      var value = output.trim()
      root.currentUid = /^\d+$/.test(value) ? Number(value) : -1
      if (exitCode !== 0 || root.currentUid < 0) root.uidError = "Could not determine the current user"
      else root.scan()
    }
  }

  CommandProcess {
    id: ipProcess
    command: ["bash", "-c", "ip -j -4 route show && ip -j -4 address show up"]
    onCompleted: function(exitCode) {
      if (exitCode !== 0) {
        root.lanIp = ""
        root.lanInterface = ""
        root.lanSubnet = ""
        root.lanInterfaces = []
        root.routeWarning = "LAN route information is unavailable"
        root.publishServers()
        return
      }
      var parts = output.trim().split(/\r?\n/)
      var interfaces = Network.parseLanInterfaces(parts[1])
      var route = Network.parseLanRoute(parts[0], interfaces, root.selectedLanInterface)
      root.lanInterfaces = interfaces
      root.lanIp = route.ip
      root.lanInterface = route.interfaceName
      root.lanSubnet = route.subnet
      root.routeWarning = route.ip ? "" : (root.selectedLanInterface
        ? "No active IPv4 address on LAN interface " + root.selectedLanInterface
        : "No active IPv4 LAN route was found")
      root.publishServers()
    }
  }

  CommandProcess {
    id: resourceProcess
    onCompleted: function(exitCode) { root.finishResourceSample(output, false, exitCode) }
  }
  CommandProcess {
    id: dockerMemoryProcess
    onCompleted: function(exitCode) { root.finishResourceSample(output, true, exitCode) }
  }

  CommandProcess {
    id: actionProcess
    objectName: "serverActionProcess"
    onCompleted: function(exitCode, failedToStart) { root.finishAction(exitCode, output, errorOutput, failedToStart) }
  }
}
