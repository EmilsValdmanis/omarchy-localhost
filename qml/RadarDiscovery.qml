import QtQuick
import "Diagnostics.js" as Diagnostics
import "Discovery.js" as Discovery
import "Ports.js" as Ports

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
  property var probeTransferMap: []
  property var probedIds: []

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
    sourceProcess.start(source === "docker" ? [
      "bash", "-c", "command -v docker >/dev/null 2>&1 || exit 127; exec timeout 3s docker \"$@\"",
      "localhost-docker", "ps", "--format",
      "[{{json .ID}},{{json .Names}},{{json .Image}},{{json .Ports}},{{json (.Label \"com.docker.compose.project.working_dir\")}},{{json (.Label \"com.docker.compose.service\")}},{{json (.Label \"com.docker.compose.project\")}}]"
    ] : ["ss", "-H", "-ltnp"])
  }

  function resolveMetadata(raw) {
    if (!discoveryEnabled) { finishScan(); return }
    var ignored = Ports.parsePortSet(ignoredPorts)
    var alwaysInclude = Ports.parsePortSet(alwaysIncludePorts)
    pendingListeners = source === "docker" ? [] : Discovery.parseSs(raw)
    var dockerResult = source === "docker" ? Discovery.classifyDockerPorts(raw, ignored, alwaysInclude)
      : { contexts: [], diagnostics: [], truncated: false }
    pendingContexts = dockerResult.contexts
    pendingDiagnostics = dockerResult.diagnostics
    if (dockerResult.truncated) addWarning("Docker discovery is incomplete: published ports exceed the discovery limit")
    listenerCount = pendingListeners.length
    var processIds = []
    var paths = []
    for (let i = 0; i < pendingListeners.length; i++) {
      let pid = String(pendingListeners[i].pid)
      if (processIds.indexOf(pid) === -1) processIds.push(pid)
    }
    for (let c = 0; c < pendingContexts.length; c++) {
      let path = pendingContexts[c].process.cwd
      if (path && paths.indexOf(path) === -1) paths.push(path)
    }
    metadataProcess.start([
      "python3", helperPath, "inspect", "--pids", processIds.join(","),
      "--uid", String(currentUid), "--paths", JSON.stringify(paths.slice(0, 256))
    ])
  }

  function cacheMetadata(raw, detail) {
    var parsed = Discovery.parseProcessPayload(raw, currentUid)
    if (!parsed.ok) addWarning(parsed.error || detail)
    var ignored = Ports.parsePortSet(ignoredPorts)
    var alwaysInclude = Ports.parsePortSet(alwaysIncludePorts)
    if (source === "docker") {
      for (let i = 0; i < pendingContexts.length; i++) {
        let context = pendingContexts[i]
        context.process.project = (parsed.projects || {})[context.process.cwd] || {}
      }
    } else {
      let classified = Discovery.classifyListeners(pendingListeners, parsed.processes, ignored, alwaysInclude, readyContexts)
      pendingContexts = classified.contexts
      pendingDiagnostics = classified.diagnostics
    }
    candidateCount = pendingContexts.length
    var nextCache = {}
    for (let c = 0; c < pendingContexts.length; c++) {
      let key = Discovery.probeCacheKey(pendingContexts[c])
      if (probeCache[key]) nextCache[key] = probeCache[key]
    }
    probeCache = nextCache
    var plan = Discovery.probePlan(pendingContexts, probeCache, Date.now(), bypassProbeCache)
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
    for (let i = 0; i < contexts.length; i++) {
      let context = contexts[i]
      let id = Discovery.contextId(context)
      let preferred = Discovery.schemeFor(context.process.command)
      let alternate = preferred === "https" ? "http" : "https"
      ids.push({ id: id, key: Discovery.probeCacheKey(context) })
      transfers.push({ id: id, scheme: preferred, preference: 0 })
      args.push(Discovery.probeUrl(context, preferred))
      transfers.push({ id: id, scheme: alternate, preference: 1 })
      args.push(Discovery.probeUrl(context, alternate))
    }
    probeTransferMap = transfers
    probedIds = ids
    probeProcess.start(args)
  }

  function finishProbes(raw) {
    var accepted = Discovery.parseProbeOutput(raw, probeTransferMap)
    var nextCache = Object.assign({}, probeCache)
    var now = Date.now()
    for (let i = 0; i < probedIds.length; i++) {
      let id = probedIds[i].id
      let key = probedIds[i].key
      if (accepted[id]) {
        pendingSchemes[id] = accepted[id].scheme
        nextCache[key] = { scheme: accepted[id].scheme, expiresAt: now + 60000 }
      } else {
        let attempts = Number((nextCache[key] && nextCache[key].attempts) || 0) + 1
        nextCache[key] = { scheme: "", attempts: attempts, expiresAt: now + (attempts === 1 ? 3000 : 15000) }
      }
    }
    probeCache = nextCache
    applyCandidates()
  }

  function applyCandidates() {
    var ready = []
    var details = pendingDiagnostics.slice()
    var previousIds = new Set(readyContexts.map(function(entry) { return Discovery.contextId(entry.context) }))
    for (let i = 0; i < pendingContexts.length; i++) {
      let context = pendingContexts[i]
      let id = Discovery.contextId(context)
      let scheme = pendingSchemes[id] || ""
      if (scheme || (context.process.cwdDeleted && previousIds.has(id))) ready.push({ context: context, scheme: scheme })
      else details.push({ port: context.listener.port,
        process: String(context.listener.process || context.displayName || "unknown"),
        reason: Diagnostics.REASONS.noResponse })
    }
    readyContexts = discoveryEnabled ? ready : []
    diagnostics = discoveryEnabled ? details : []
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

  CommandProcess {
    id: sourceProcess
    onCompleted: function(exitCode) {
      if (exitCode !== 0) {
        root.readyContexts = []
        root.diagnostics = []
        root.listenerCount = 0
        root.candidateCount = 0
        if (root.source === "docker") {
          if (exitCode !== 127) root.addWarning(errorOutput || "Docker discovery is unavailable")
        } else root.scanError = errorOutput || "Could not scan local ports"
        root.finishScan()
      } else { root.scanError = ""; root.resolveMetadata(output) }
    }
  }
  CommandProcess {
    id: metadataProcess
    onCompleted: function(exitCode) {
      if (!root.discoveryEnabled) { root.finishScan(); return }
      if (exitCode !== 0 && !output) root.addWarning(errorOutput || "Process metadata is unavailable")
      root.cacheMetadata(output, errorOutput)
    }
  }
  CommandProcess {
    id: probeProcess
    onCompleted: function(exitCode, failedToStart) {
      if (failedToStart) {
        root.addWarning("Could not start HTTP probes")
        root.applyCandidates()
      } else root.finishProbes(output)
    }
  }
}
