import QtQuick
import Quickshell.Io
import "RadarModel.js" as RadarModel

Item {
  id: root
  visible: false

  property string source: "process"
  property bool discoveryEnabled: true
  property int intervalSec: 2
  property int currentUid: -1
  property string helperPath: ""
  property string ignoredPorts: ""
  property string alwaysIncludePorts: ""
  property bool scanning: false
  property bool scanQueued: false
  property bool manualScanQueued: false
  property bool bypassProbeCache: false
  property string scanError: ""
  property var warnings: []
  property var diagnostics: []
  property var readyContexts: []
  property int listenerCount: 0
  property int candidateCount: 0
  property var probeCache: ({})
  property var pendingWarnings: []
  property var pendingDiagnostics: []
  property var pendingListeners: []
  property var pendingContexts: []
  property var pendingSchemes: ({})
  property var processCache: ({})
  property var probeTransferMap: []
  property var probedIds: []
  property string sourceOutput: ""
  property string sourceError: ""
  property string metadataOutput: ""
  property string metadataError: ""
  property string probeOutput: ""

  signal resultsChanged()

  function addWarning(message) {
    var detail = String(message || "").trim()
    if (detail && pendingWarnings.indexOf(detail) === -1)
      pendingWarnings = pendingWarnings.concat([detail.slice(0, 220)])
  }

  function scan(manual) {
    if (!discoveryEnabled) return
    if (manual === true) manualScanQueued = true
    if (scanning || currentUid < 0) { scanQueued = true; return }
    scanQueued = false
    bypassProbeCache = manualScanQueued
    manualScanQueued = false
    scanning = true
    pendingWarnings = []
    sourceOutput = ""
    sourceError = ""
    sourceProcess.command = source === "docker" ? [
      "bash", "-c", "command -v docker >/dev/null 2>&1 || exit 127; exec timeout 3s docker \"$@\"",
      "localhost-docker", "ps", "--format",
      "[{{json .ID}},{{json .Names}},{{json .Image}},{{json .Ports}},{{json (.Label \"com.docker.compose.project.working_dir\")}},{{json (.Label \"com.docker.compose.service\")}},{{json (.Label \"com.docker.compose.project\")}}]"
    ] : ["ss", "-H", "-ltnp"]
    sourceProcess.running = true
  }

  function resolveMetadata() {
    if (!discoveryEnabled) { finishScan(); return }
    var ignored = RadarModel.parsePortSet(ignoredPorts)
    var alwaysInclude = RadarModel.parsePortSet(alwaysIncludePorts)
    pendingListeners = source === "docker" ? [] : RadarModel.parseSs(sourceOutput)
    pendingContexts = source === "docker"
      ? RadarModel.dockerPublishedContexts(sourceOutput, ignored, alwaysInclude) : []
    listenerCount = pendingListeners.length
    var processIds = []
    var paths = []
    for (var i = 0; i < pendingListeners.length; i++) {
      var pid = String(pendingListeners[i].pid)
      if (processIds.indexOf(pid) === -1) processIds.push(pid)
    }
    for (var c = 0; c < pendingContexts.length; c++) {
      var path = pendingContexts[c].process.cwd
      if (path && paths.indexOf(path) === -1) paths.push(path)
    }
    metadataOutput = ""
    metadataError = ""
    metadataProcess.command = [
      "python3", helperPath, "inspect", "--pids", processIds.join(","),
      "--uid", String(currentUid), "--paths", JSON.stringify(paths.slice(0, 256)), "--no-resources"
    ]
    metadataProcess.running = true
  }

  function cacheMetadata() {
    var parsed = RadarModel.parseProcessPayload(metadataOutput, currentUid)
    processCache = parsed.processes
    if (!parsed.ok) addWarning(parsed.error || metadataError)
    var ignored = RadarModel.parsePortSet(ignoredPorts)
    var alwaysInclude = RadarModel.parsePortSet(alwaysIncludePorts)
    if (source === "docker") {
      for (var i = 0; i < pendingContexts.length; i++) {
        var context = pendingContexts[i]
        context.process.project = (parsed.projects || {})[context.process.cwd] || {}
      }
      pendingDiagnostics = []
    } else {
      pendingContexts = RadarModel.candidateContexts(pendingListeners, processCache, ignored, alwaysInclude)
      pendingDiagnostics = RadarModel.candidateDiagnostics(
        pendingListeners, processCache, pendingContexts, ignored, alwaysInclude).slice(0, 30)
    }
    candidateCount = pendingContexts.length
    var nextCache = {}
    for (var c = 0; c < pendingContexts.length; c++) {
      var id = RadarModel.contextId(pendingContexts[c])
      if (probeCache[id]) nextCache[id] = probeCache[id]
    }
    probeCache = nextCache
    var plan = RadarModel.probePlan(pendingContexts, probeCache, Date.now(), bypassProbeCache)
    pendingSchemes = plan.schemes
    if (!plan.pending.length) { applyCandidates(); return }
    probeCandidates(plan.pending)
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
    for (var i = 0; i < contexts.length; i++) {
      var context = contexts[i]
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
    for (var i = 0; i < probedIds.length; i++) {
      var id = probedIds[i]
      if (accepted[id]) {
        pendingSchemes[id] = accepted[id].scheme
        nextCache[id] = { scheme: accepted[id].scheme, expiresAt: now + 60000 }
      } else {
        var attempts = Number((nextCache[id] && nextCache[id].attempts) || 0) + 1
        nextCache[id] = { scheme: "", attempts: attempts, expiresAt: now + (attempts === 1 ? 3000 : 15000) }
      }
    }
    probeCache = nextCache
    applyCandidates()
  }

  function applyCandidates() {
    var ready = []
    var details = pendingDiagnostics.slice()
    for (var i = 0; i < pendingContexts.length; i++) {
      var context = pendingContexts[i]
      var scheme = pendingSchemes[RadarModel.contextId(context)] || ""
      if (scheme) ready.push({ context: context, scheme: scheme })
      else details.push({ port: context.listener.port,
        process: String(context.listener.process || context.displayName || "unknown"),
        reason: "no HTTP or HTTPS response" })
    }
    readyContexts = discoveryEnabled ? ready : []
    diagnostics = discoveryEnabled ? details.slice(0, 30) : []
    finishScan()
  }

  function finishScan() {
    if (!discoveryEnabled) {
      readyContexts = []
      diagnostics = []
      pendingWarnings = []
    }
    warnings = pendingWarnings
    scanning = false
    resultsChanged()
    if (scanQueued) { scanQueued = false; Qt.callLater(scan) }
  }

  onDiscoveryEnabledChanged: {
    if (discoveryEnabled) scan()
    else { readyContexts = []; diagnostics = []; warnings = []; resultsChanged() }
  }
  onIgnoredPortsChanged: scan()
  onAlwaysIncludePortsChanged: scan()

  Timer {
    interval: Math.max(1, root.intervalSec) * 1000
    running: root.discoveryEnabled && root.currentUid >= 0
    repeat: true
    onTriggered: if (!root.scanning) root.scan()
  }

  Process {
    id: sourceProcess
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.sourceOutput = String(text || "") }
    stderr: StdioCollector { waitForEnd: true; onStreamFinished: root.sourceError = String(text || "").trim() }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.readyContexts = []
        root.diagnostics = []
        root.listenerCount = 0
        root.candidateCount = 0
        if (root.source === "docker") {
          if (exitCode !== 127) root.addWarning(root.sourceError || "Docker discovery is unavailable")
        } else root.scanError = root.sourceError || "Could not scan local ports"
        root.finishScan()
      } else { root.scanError = ""; root.resolveMetadata() }
    }
  }
  Process {
    id: metadataProcess
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.metadataOutput = String(text || "") }
    stderr: StdioCollector { waitForEnd: true; onStreamFinished: root.metadataError = String(text || "").trim() }
    onExited: function(exitCode) {
      if (!root.discoveryEnabled) { root.finishScan(); return }
      if (exitCode !== 0 && !root.metadataOutput) root.addWarning(root.metadataError || "Process metadata is unavailable")
      root.cacheMetadata()
    }
  }
  Process {
    id: probeProcess
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.probeOutput = String(text || "") }
    stderr: StdioCollector {}
    onExited: function(exitCode) { root.finishProbes() }
  }
}
