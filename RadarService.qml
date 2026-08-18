import QtQuick
import Quickshell.Io
import "RadarModel.js" as RadarModel

Item {
  id: root
  visible: false

  property int refreshIntervalSec: 2
  property alias servers: serverModel
  readonly property int serverCount: serverModel.count
  property string lanIp: ""
  property string lanInterface: ""
  property string lanSubnet: ""
  property bool scanning: false
  property string scanError: ""
  property bool scanQueued: false
  property string actionName: ""
  property string actionError: ""

  property int currentUid: -1
  property var processCache: ({})
  property var probeCache: ({})
  property var pendingListeners: []
  property var pendingProcesses: ({})
  property var pendingProcessIds: []
  property var pendingContexts: []
  property var pendingDockerContexts: []
  property var pendingSchemes: ({})
  property var probeTransferMap: []
  property var probedIds: []
  property string ssOutput: ""
  property string psOutput: ""
  property string pwdxOutput: ""
  property string probeOutput: ""
  property string ipOutput: ""
  property string dockerOutput: ""

  signal actionFinished(string action, bool successful, string detail)

  readonly property string stopScript: [
    "pid=$1",
    "[[ $pid =~ ^[0-9]+$ && $pid -gt 0 ]] || { echo 'Invalid process ID' >&2; exit 1; }",
    "owner=$(stat -c %u /proc/$pid 2>/dev/null) || { echo 'Process is no longer running' >&2; exit 1; }",
    "[[ $owner == $(id -u) ]] || { echo 'Process is not owned by the current user' >&2; exit 1; }",
    "kill -TERM -- $pid"
  ].join("\n")

  readonly property string restartScript: [
    "pid=$1",
    "[[ $pid =~ ^[0-9]+$ && $pid -gt 0 ]] || { echo 'Invalid process ID' >&2; exit 1; }",
    "proc=/proc/$pid",
    "owner=$(stat -c %u $proc 2>/dev/null) || { echo 'Process is no longer running' >&2; exit 1; }",
    "[[ $owner == $(id -u) ]] || { echo 'Process is not owned by the current user' >&2; exit 1; }",
    "cwd=$(readlink -e $proc/cwd) || { echo 'Could not recover the server directory' >&2; exit 1; }",
    "exe=$(readlink -e $proc/exe) || true",
    "argv=()",
    "while IFS= read -r -d '' value; do argv+=(\"$value\"); done < $proc/cmdline",
    "[[ ${#argv[@]} -gt 0 ]] || { echo 'Could not recover the server command' >&2; exit 1; }",
    "environment=()",
    "while IFS= read -r -d '' value; do environment+=(\"$value\"); done < $proc/environ",
    "if [[ ${argv[0]} != /* && -x $exe ]]; then argv[0]=$exe; fi",
    "kill -TERM -- $pid",
    "for ((attempt=0; attempt<30; attempt++)); do",
    "  [[ ! -d $proc ]] && break",
    "  state=$(awk '{print $3}' $proc/stat 2>/dev/null || true)",
    "  [[ $state == Z ]] && break",
    "  sleep 0.05",
    "done",
    "if [[ -d $proc ]]; then",
    "  state=$(awk '{print $3}' $proc/stat 2>/dev/null || true)",
    "  [[ $state == Z ]] || { echo 'The server did not stop cleanly; restart was cancelled' >&2; exit 1; }",
    "fi",
    "state_root=${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/localhost",
    "mkdir -p -- \"$state_root\"",
    "log=$state_root/restart-$(date +%s).log",
    "cd -- \"$cwd\"",
    "nohup env -i \"${environment[@]}\" setsid -- \"${argv[@]}\" >>\"$log\" 2>&1 </dev/null &",
    "echo $!"
  ].join("\n")

  ListModel { id: serverModel }

  function normalizedServer(server) {
    return {
      serverId: String(server.id || ""),
      name: String(server.name || "Development server"),
      framework: String(server.framework || "Dev server"),
      frameworkId: String(server.frameworkId || "server"),
      pid: Number(server.pid || 0),
      source: String(server.source || "process"),
      containerId: String(server.containerId || ""),
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
    if (scanning || currentUid < 0) {
      scanQueued = true
      return
    }
    scanning = true
    scanError = ""
    ssOutput = ""
    dockerOutput = ""
    ssProcess.command = ["ss", "-H", "-ltnp"]
    ssProcess.running = true
  }

  function scanDocker() {
    dockerProcess.command = [
      "docker", "ps", "--format",
      "[{{json .ID}},{{json .Names}},{{json .Image}},{{json .Ports}},{{json (.Label \"com.docker.compose.project.working_dir\")}},{{json (.Label \"com.docker.compose.service\")}},{{json (.Label \"com.docker.compose.project\")}}]"
    ]
    dockerProcess.running = true
  }

  function resolveMetadata() {
    pendingListeners = RadarModel.parseSs(ssOutput)
    pendingDockerContexts = RadarModel.dockerPublishedContexts(dockerOutput)
    pruneCaches(pendingListeners)

    var unknown = []
    var seen = {}
    for (var index = 0; index < pendingListeners.length; index++) {
      var pid = String(pendingListeners[index].pid)
      if (!processCache[pid] && !seen[pid]) {
        seen[pid] = true
        unknown.push(pid)
      }
    }
    if (!unknown.length) {
      selectCandidates()
      return
    }

    pendingProcessIds = unknown
    psOutput = ""
    psProcess.command = ["ps", "-ww", "-o", "pid=,uid=,args=", "-p", unknown.join(",")]
    psProcess.running = true
  }

  function resolveDirectories() {
    pendingProcesses = RadarModel.parsePs(psOutput, currentUid)
    var owned = []
    for (var index = 0; index < pendingProcessIds.length; index++) {
      var pid = pendingProcessIds[index]
      if (pendingProcesses[pid]) owned.push(pid)
    }
    if (!owned.length) {
      selectCandidates()
      return
    }

    pendingProcessIds = owned
    pwdxOutput = ""
    pwdxProcess.command = ["pwdx"].concat(owned)
    pwdxProcess.running = true
  }

  function cacheMetadata() {
    var directories = RadarModel.parsePwdx(pwdxOutput)
    var nextCache = Object.assign({}, processCache)
    for (var index = 0; index < pendingProcessIds.length; index++) {
      var pid = pendingProcessIds[index]
      var process = pendingProcesses[pid]
      if (!process || !directories[pid]) continue
      nextCache[pid] = {
        pid: process.pid,
        uid: process.uid,
        command: process.command,
        cwd: directories[pid]
      }
    }
    processCache = nextCache
    selectCandidates()
  }

  function pruneCaches(listeners) {
    var activePids = {}
    var activeIds = {}
    for (var index = 0; index < listeners.length; index++) {
      activePids[String(listeners[index].pid)] = true
      activeIds[listeners[index].pid + ":" + listeners[index].port] = true
    }
    for (var dockerIndex = 0; dockerIndex < pendingDockerContexts.length; dockerIndex++)
      activeIds[RadarModel.contextId(pendingDockerContexts[dockerIndex])] = true
    var nextProcesses = {}
    for (var pid in processCache)
      if (activePids[pid]) nextProcesses[pid] = processCache[pid]
    processCache = nextProcesses

    var nextProbes = {}
    for (var id in probeCache)
      if (activeIds[id]) nextProbes[id] = probeCache[id]
    probeCache = nextProbes
  }

  function selectCandidates() {
    pendingContexts = RadarModel.candidateContexts(pendingListeners, processCache)
      .concat(pendingDockerContexts)
    pendingSchemes = ({})
    var toProbe = []
    var now = Date.now()
    for (var index = 0; index < pendingContexts.length; index++) {
      var context = pendingContexts[index]
      var id = RadarModel.contextId(context)
      var cached = probeCache[id]
      if (cached && cached.scheme) pendingSchemes[id] = cached.scheme
      else if (!cached || Number(cached.expiresAt || 0) <= now) toProbe.push(context)
    }
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
      "--write-out", "%{urlnum}\\t%{http_code}\\t%{content_type}\\n", "--"
    ]
    var transfers = []
    var ids = []
    for (var index = 0; index < contexts.length; index++) {
      var context = contexts[index]
      var id = RadarModel.contextId(context)
      var preferred = RadarModel.schemeFor(context.process.command)
      ids.push(id)
      transfers.push({ id: id, scheme: preferred, preference: 0 })
      args.push(RadarModel.probeUrl(context, preferred))
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
    for (var index = 0; index < pendingContexts.length; index++) {
      var context = pendingContexts[index]
      var id = RadarModel.contextId(context)
      var scheme = pendingSchemes[id] || ""
      if (scheme) servers.push(RadarModel.serverFromContext(context, scheme, lanIp))
    }
    servers.sort(function(a, b) {
      return a.port - b.port || a.name.toLowerCase().localeCompare(b.name.toLowerCase())
    })
    syncServers(servers)
    finishScan()
  }

  function finishScan() {
    scanning = false
    if (scanQueued) {
      scanQueued = false
      Qt.callLater(scan)
    }
  }

  function runAction(action, server) {
    if (!server || actionProcess.running) return
    actionName = action
    actionError = ""
    if (server.source === "docker" && server.containerId) {
      actionProcess.command = ["docker", action, String(server.containerId)]
      actionProcess.running = true
      return
    }
    var script = action === "restart" ? restartScript : stopScript
    actionProcess.command = ["bash", "-c", script, "localhost-" + action, String(server.pid)]
    actionProcess.running = true
  }

  function stop(server) { runAction("stop", server) }
  function restart(server) { runAction("restart", server) }

  Component.onCompleted: {
    uidProcess.running = true
    ipProcess.running = true
  }

  Timer {
    interval: Math.max(1, root.refreshIntervalSec) * 1000
    running: true
    repeat: true
    onTriggered: root.scan()
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
    command: ["ip", "-j", "-4", "route", "show"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.ipOutput = String(text || "")
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) return
      var route = RadarModel.parseLanRoute(root.ipOutput)
      root.lanIp = route.ip
      root.lanInterface = route.interfaceName
      root.lanSubnet = route.subnet
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
      onStreamFinished: {
        var detail = String(text || "").trim()
        if (detail) root.scanError = detail
      }
    }
    onExited: function(exitCode) {
      if (exitCode === 0) root.scanDocker()
      else {
        if (!root.scanError) root.scanError = "Could not scan local ports"
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
    stderr: StdioCollector {}
    onExited: function(exitCode) {
      // Docker is optional. Native discovery still works without its CLI or daemon.
      if (exitCode !== 0) root.dockerOutput = ""
      root.resolveMetadata()
    }
  }

  Process {
    id: psProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.psOutput = String(text || "")
    }
    onExited: function(exitCode) {
      root.resolveDirectories()
    }
  }

  Process {
    id: pwdxProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.pwdxOutput = String(text || "")
    }
    onExited: function(exitCode) {
      root.cacheMetadata()
    }
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
