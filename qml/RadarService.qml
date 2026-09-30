import QtQuick
import Quickshell.Io
import "RadarModel.js" as RadarModel

Item {
  id: root
  visible: false

  property int refreshIntervalSec: 2
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
  property bool scanning: false
  property string scanError: ""
  property bool scanQueued: false
  property bool manualScanQueued: false
  property bool bypassProbeCache: false
  property string actionName: ""
  property string actionError: ""
  property string actionOutput: ""
  property string actionServerId: ""
  property var warnings: []
  property var pendingWarnings: []
  property var dependencyWarnings: []
  property var diagnostics: []
  property var pendingDiagnostics: []
  property string scanSummary: ""

  property int currentUid: -1
  property var processCache: ({})
  property var systemMemory: ({ totalBytes: -1, availableBytes: -1 })
  property var dockerMemoryCache: ({})
  property var dockerMemoryAt: ({})
  property real lastDockerMemoryScanMs: 0
  property var dockerMemoryRequestedIds: []
  property string dockerMemoryOutput: ""
  property var memoryHistoryById: ({})
  property var probeCache: ({})
  property var pendingListeners: []
  property var pendingContexts: []
  property var pendingDockerContexts: []
  property var pendingSchemes: ({})
  property var probeTransferMap: []
  property var probedIds: []
  property string ssOutput: ""
  property string ssError: ""
  property string metadataOutput: ""
  property string metadataError: ""
  property string probeOutput: ""
  property string ipOutput: ""
  property string dockerOutput: ""
  property string dockerError: ""
  property string routeWarning: ""

  readonly property string helperPath: decodeURIComponent(
    String(Qt.resolvedUrl("../localhost_helper.py")).replace(/^file:\/\//, ""))

  signal actionFinished(string action, bool successful, string detail, string serverId)

  ListModel { id: serverModel }

  function syncServers(nextServers) {
    var nextHistory = Object.create(null)
    for (var index = 0; index < nextServers.length; index++) {
      var server = nextServers[index]
      var id = String(server.id)
      var previous = memoryHistoryById[id] || []
      var bytes = RadarModel.validMemory(server.memoryBytes)
      var history = bytes < 0 ? [] : previous.concat([bytes]).slice(-30)
      nextHistory[id] = history
      server.memoryHistory = history
    }
    memoryHistoryById = nextHistory
    if (RadarModel.syncServerModel(serverModel, nextServers)) revision++
  }

  function addWarning(message) {
    var detail = String(message || "").trim()
    if (!detail || pendingWarnings.indexOf(detail) !== -1) return
    pendingWarnings = pendingWarnings.concat([detail])
  }

  function diagnosticDetail(raw, fallback) {
    var lines = String(raw || "").trim().split(/\r?\n/)
    var detail = lines.length ? lines[lines.length - 1].trim() : ""
    return String(detail || fallback || "").slice(0, 220)
  }

  function arraysEqual(left, right) {
    return JSON.stringify(left || []) === JSON.stringify(right || [])
  }

  function refresh() { scan(true) }

  function scan(manual) {
    if (manual === true) manualScanQueued = true
    if (scanning || currentUid < 0) {
      scanQueued = true
      return
    }
    scanQueued = false
    bypassProbeCache = manualScanQueued
    manualScanQueued = false
    scanning = true
    pendingWarnings = []
    for (var warningIndex = 0; warningIndex < dependencyWarnings.length; warningIndex++)
      addWarning(dependencyWarnings[warningIndex])
    if (routeWarning) addWarning(routeWarning)
    ssOutput = ""
    ssError = ""
    dockerOutput = ""
    dockerError = ""
    ssProcess.command = ["ss", "-H", "-ltnp"]
    ssProcess.running = true
  }

  function scanDocker() {
    if (!includeDocker) {
      dockerOutput = ""
      resolveMetadata()
      return
    }
    dockerProcess.command = [
      "bash", "-c", "command -v docker >/dev/null 2>&1 || exit 127; exec timeout 3s docker \"$@\"",
      "localhost-docker", "ps", "--format",
      "[{{json .ID}},{{json .Names}},{{json .Image}},{{json .Ports}},{{json (.Label \"com.docker.compose.project.working_dir\")}},{{json (.Label \"com.docker.compose.service\")}},{{json (.Label \"com.docker.compose.project\")}}]"
    ]
    dockerProcess.running = true
  }

  function resolveMetadata() {
    var ignored = RadarModel.parsePortSet(ignoredPorts)
    var alwaysInclude = RadarModel.parsePortSet(alwaysIncludePorts)
    pendingListeners = RadarModel.parseSs(ssOutput)
    pendingDockerContexts = RadarModel.dockerPublishedContexts(dockerOutput, ignored, alwaysInclude)

    var processIds = []
    var seen = {}
    for (var index = 0; index < pendingListeners.length; index++) {
      var pid = String(pendingListeners[index].pid)
      if (!seen[pid]) {
        seen[pid] = true
        processIds.push(pid)
      }
    }
    var projectPaths = []
    var containerIds = []
    for (var dockerIndex = 0; dockerIndex < pendingDockerContexts.length; dockerIndex++) {
      var dockerContext = pendingDockerContexts[dockerIndex]
      var path = dockerContext.process.cwd
      if (path && projectPaths.indexOf(path) === -1) projectPaths.push(path)
      if (containerIds.indexOf(dockerContext.containerId) === -1)
        containerIds.push(dockerContext.containerId)
    }
    metadataOutput = ""
    metadataError = ""
    var now = Date.now()
    if (containerIds.length && !dockerMemoryProcess.running
        && now - lastDockerMemoryScanMs >= 8000) {
      lastDockerMemoryScanMs = now
      dockerMemoryRequestedIds = containerIds
      dockerMemoryOutput = ""
      dockerMemoryProcess.command = [
        "python3", helperPath, "inspect", "--pids", "", "--uid", String(currentUid),
        "--paths", "[]", "--containers", containerIds.join(",")
      ]
      dockerMemoryProcess.running = true
    }
    metadataProcess.command = [
      "python3", helperPath, "inspect", "--pids", processIds.join(","),
      "--uid", String(currentUid), "--paths", JSON.stringify(projectPaths.slice(0, 256)),
      "--containers", ""
    ]
    metadataProcess.running = true
  }

  function finishDockerMemorySample(exitCode) {
    if (exitCode !== 0 || !includeDocker) return
    var parsed = RadarModel.parseProcessPayload(dockerMemoryOutput, currentUid)
    if (!parsed.ok) return
    var nextMemory = Object.assign({}, dockerMemoryCache)
    var nextAt = Object.assign({}, dockerMemoryAt)
    var now = Date.now()
    var changed = false
    for (var index = 0; index < dockerMemoryRequestedIds.length; index++) {
      var containerId = dockerMemoryRequestedIds[index]
      var bytes = RadarModel.validMemory(parsed.containers[containerId])
      if (bytes < 0) continue
      if (nextMemory[containerId] !== bytes) changed = true
      nextMemory[containerId] = bytes
      nextAt[containerId] = now
    }
    dockerMemoryCache = nextMemory
    dockerMemoryAt = nextAt
    if (changed) scan()
  }

  function cacheMetadata() {
    var parsed = RadarModel.parseProcessPayload(metadataOutput, currentUid)
    processCache = parsed.processes
    systemMemory = parsed.systemMemory || { totalBytes: -1, availableBytes: -1 }
    var nextDockerMemory = Object.create(null)
    var nextDockerMemoryAt = Object.create(null)
    var now = Date.now()
    for (var containerIndex = 0; containerIndex < pendingDockerContexts.length; containerIndex++) {
      var containerId = pendingDockerContexts[containerIndex].containerId
      if (dockerMemoryCache[containerId] !== undefined
          && now - Number(dockerMemoryAt[containerId] || 0) < 20000) {
        nextDockerMemory[containerId] = dockerMemoryCache[containerId]
        nextDockerMemoryAt[containerId] = dockerMemoryAt[containerId]
      }
    }
    dockerMemoryCache = nextDockerMemory
    dockerMemoryAt = nextDockerMemoryAt
    var projects = parsed.projects || {}
    for (var index = 0; index < pendingDockerContexts.length; index++) {
      var context = pendingDockerContexts[index]
      context.process.project = projects[context.process.cwd] || {}
      context.process.memoryBytes = dockerMemoryCache[context.containerId] === undefined
        ? -1 : dockerMemoryCache[context.containerId]
    }
    if (!parsed.ok) addWarning(parsed.error || metadataError)
    selectCandidates()
  }

  function pruneProbeCache(contexts) {
    var activeIds = {}
    for (var index = 0; index < contexts.length; index++)
      activeIds[RadarModel.contextId(contexts[index])] = true

    var nextProbes = {}
    for (var id in probeCache)
      if (activeIds[id]) nextProbes[id] = probeCache[id]
    probeCache = nextProbes
  }

  function selectCandidates() {
    var ignored = RadarModel.parsePortSet(ignoredPorts)
    var alwaysInclude = RadarModel.parsePortSet(alwaysIncludePorts)
    var nativeContexts = RadarModel.candidateContexts(
      pendingListeners, processCache, ignored, alwaysInclude)
    pendingDiagnostics = RadarModel.candidateDiagnostics(
      pendingListeners, processCache, nativeContexts, ignored, alwaysInclude).slice(0, 30)
    pendingContexts = nativeContexts.concat(pendingDockerContexts)
    pruneProbeCache(pendingContexts)
    var plan = RadarModel.probePlan(pendingContexts, probeCache, Date.now(), bypassProbeCache)
    pendingSchemes = plan.schemes
    var toProbe = plan.pending
    if (!toProbe.length) {
      applyCandidates()
      return
    }
    probeCandidates(toProbe)
  }

  function probeCandidates(contexts) {
    var args = [
      "curl", "--noproxy", "*", "--head", "--silent", "--show-error",
      "--parallel", "--parallel-immediate", "--insecure",
      "--connect-timeout", "0.3", "--max-time", "0.7",
      "--header", "Accept: text/html,application/xhtml+xml",
      "--write-out", "%{urlnum}\\t%{http_code}\\n", "--"
    ]
    var transfers = []
    var ids = []
    for (var index = 0; index < contexts.length; index++) {
      var context = contexts[index]
      var id = RadarModel.contextId(context)
      var preferred = RadarModel.schemeFor(context.process.command)
      var alternate = preferred === "https" ? "http" : "https"
      ids.push(id)
      transfers.push({ id: id, scheme: preferred, preference: 0 })
      args.push(RadarModel.probeUrl(context, preferred))
      transfers.push({ id: id, scheme: alternate, preference: 1 })
      args.push(RadarModel.probeUrl(context, alternate))
    }
    probeTransferMap = transfers
    probedIds = ids
    probeOutput = ""
    probeProcess.command = args
    probeProcess.running = true
  }

  function finishProbes() {
    var accepted = RadarModel.parseProbeOutput(probeOutput, probeTransferMap)
    var nextCache = Object.assign({}, probeCache)
    var now = Date.now()
    for (var index = 0; index < probedIds.length; index++) {
      var id = probedIds[index]
      if (accepted[id]) {
        pendingSchemes[id] = accepted[id].scheme
        nextCache[id] = { scheme: accepted[id].scheme, expiresAt: now + 60000 }
      } else {
        var previousAttempts = Number((nextCache[id] && nextCache[id].attempts) || 0)
        var attempts = previousAttempts + 1
        nextCache[id] = {
          scheme: "",
          attempts: attempts,
          expiresAt: now + (attempts === 1 ? 3000 : 15000)
        }
      }
    }
    probeCache = nextCache
    applyCandidates()
  }

  function applyCandidates() {
    var servers = []
    var details = pendingDiagnostics.slice()
    for (var index = 0; index < pendingContexts.length; index++) {
      var context = pendingContexts[index]
      var id = RadarModel.contextId(context)
      var scheme = pendingSchemes[id] || ""
      if (scheme) servers.push(RadarModel.serverFromContext(context, scheme,
        { ip: lanIp, interfaceName: lanInterface, subnet: lanSubnet }, lanInterfaces))
      else details.push({
        port: context.listener.port,
        process: String(context.listener.process || context.displayName || "unknown"),
        reason: "no HTTP or HTTPS response"
      })
    }
    servers.sort(function(a, b) {
      return a.port - b.port || a.name.toLowerCase().localeCompare(b.name.toLowerCase())
    })
    var nextDiagnostics = details.slice(0, 30)
    if (!arraysEqual(diagnostics, nextDiagnostics)) diagnostics = nextDiagnostics
    scanSummary = pendingListeners.length + " owned listener"
      + (pendingListeners.length === 1 ? "" : "s") + " · "
      + pendingContexts.length + " candidate" + (pendingContexts.length === 1 ? "" : "s")
      + " · " + servers.length + " browser-ready"
    syncServers(servers)
    finishScan()
  }

  function finishScan() {
    if (!arraysEqual(warnings, pendingWarnings)) warnings = pendingWarnings
    scanning = false
    if (scanQueued) {
      scanQueued = false
      Qt.callLater(scan)
    }
  }

  function runAction(action, server) {
    if (!server || actionProcess.running) return
    if (action === "restart" && !RadarModel.actionEnabled(5, server)) return
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

  onSelectedLanInterfaceChanged: if (!ipProcess.running) ipProcess.running = true

  Component.onCompleted: {
    dependencyProcess.running = true
    uidProcess.running = true
    ipProcess.running = true
  }

  Timer {
    interval: Math.max(1, root.refreshIntervalSec) * 1000
    running: true
    repeat: true
    onTriggered: if (!root.scanning) root.scan()
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
    onTriggered: root.scan()
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
      if (exitCode !== 0 || root.currentUid < 0) root.scanError = "Could not determine the current user"
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
    id: ssProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.ssOutput = String(text || "")
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.ssError = String(text || "").trim()
    }
    onExited: function(exitCode) {
      if (exitCode === 0) {
        root.scanError = ""
        root.scanDocker()
      }
      else {
        root.scanError = root.ssError || "Could not scan local ports"
        root.systemMemory = { totalBytes: -1, availableBytes: -1 }
        root.diagnostics = []
        root.scanSummary = ""
        root.syncServers([])
        root.finishScan()
      }
    }
  }

  Process {
    id: dockerProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.dockerOutput = String(text || "")
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.dockerError = String(text || "").trim()
    }
    onExited: function(exitCode) {
      // Docker is optional. Native discovery still works without its CLI or daemon.
      if (exitCode !== 0) {
        root.dockerOutput = ""
        if (exitCode !== 127)
          root.addWarning(root.diagnosticDetail(root.dockerError, "Docker discovery is unavailable"))
      }
      root.resolveMetadata()
    }
  }

  Process {
    id: metadataProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.metadataOutput = String(text || "")
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.metadataError = String(text || "").trim()
    }
    onExited: function(exitCode) {
      if (exitCode !== 0 && !root.metadataOutput)
        root.addWarning(root.metadataError || "Process metadata is unavailable")
      root.cacheMetadata()
    }
  }

  Process {
    id: dockerMemoryProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.dockerMemoryOutput = String(text || "")
    }
    onExited: function(exitCode) { root.finishDockerMemorySample(exitCode) }
  }

  Process {
    id: probeProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.probeOutput = String(text || "")
    }
    stderr: StdioCollector {}
    onExited: function(exitCode) { root.finishProbes() }
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
