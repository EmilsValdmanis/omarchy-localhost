.import "Paths.js" as Paths
.import "Sources.js" as Sources
.import "ListModelSync.js" as ListModelSync
.import "Memory.js" as Memory
.import "Ports.js" as Ports

function matchesServerFilter(server, filterId) {
  var source = server || {}
  var selectedFilter = String(filterId || "all")
  if (selectedFilter === "dev") return Ports.isCommonDevPort(source.port || 0)
  if (selectedFilter === "lan") return source.lanAvailable === true
  if (selectedFilter === "docker") return String(source.source || "process") === "docker"
  return true
}

function normalizeServer(server) {
  var source = server || {}
  return {
    serverId: String(source.serverId || source.id || ""),
    name: String(source.name || "Development server"),
    framework: String(source.framework || "Dev server"),
    frameworkId: String(source.frameworkId || "server"),
    pid: Number(source.pid || 0),
    startTime: Number(source.startTime || 0),
    source: String(source.source || "process"),
    containerId: String(source.containerId || ""),
    dependencyStates: String(source.dependencyStates || ""),
    serviceKey: String(source.serviceKey || ""),
    serviceName: String(source.serviceName || ""),
    port: Number(source.port || 0),
    cwd: String(source.cwd || ""),
    cwdDeleted: source.cwdDeleted === true,
    localUrl: String(source.localUrl || ""),
    probeTarget: String(source.probeTarget || "/"),
    lanUrl: String(source.lanUrl || ""),
    lanHost: String(source.lanHost || ""),
    lanInterface: String(source.lanInterface || ""),
    lanSubnet: String(source.lanSubnet || ""),
    lanAvailable: source.lanAvailable === true,
    restartAvailable: source.source === "docker" || source.restartAvailable === true,
    restartReason: String(source.restartReason || "Restart command could not be verified"),
    hint: String(source.hint || ""),
    projectRoot: String(source.projectRoot || source.cwd || source.serverId || source.id || "Other servers"),
    projectPath: String(source.projectPath || ""),
    gitBranch: String(source.gitBranch || ""),
    gitCommonDir: String(source.gitCommonDir || ""),
    memoryBytes: Memory.validMemory(source.memoryBytes),
    memoryHistoryJson: JSON.stringify(Memory.parseMemoryHistory(source.memoryHistoryJson || source.memoryHistory))
  }
}

function serversEqual(left, right) {
  return Object.keys(right).every(function(key) { return left[key] === right[key] })
}

function syncServerModel(model, servers) {
  return ListModelSync.sync(model, servers.map(normalizeServer), "serverId", serversEqual)
}

function matchesSearch(server, query, filterId) {
  if (!matchesServerFilter(server, filterId)) return false
  if (!query) return true
  return [server.name, server.framework, server.frameworkId, server.port,
    server.cwd, server.projectRoot, server.projectPath, server.gitBranch, server.localUrl, server.lanUrl, server.source, server.containerId]
    .join(" ").toLowerCase().indexOf(query) !== -1
}

function compareServers(left, right, grouped) {
  if (grouped) {
    var group = Paths.basename(left.projectRoot).localeCompare(Paths.basename(right.projectRoot))
      || left.projectRoot.localeCompare(right.projectRoot)
    if (group) return group
  }
  return left.port - right.port || left.name.localeCompare(right.name) || left.serverId.localeCompare(right.serverId)
}

function projectGroups(servers, activeServers) {
  var roots = new Map()
  var targetsByRoot = new Map()
  for (var row of activeServers || servers) {
    if (!targetsByRoot.has(row.projectRoot)) targetsByRoot.set(row.projectRoot, new Set())
    targetsByRoot.get(row.projectRoot).add(Sources.key(row))
    if (!row.gitCommonDir) continue
    if (!roots.has(row.gitCommonDir)) roots.set(row.gitCommonDir, new Set())
    roots.get(row.gitCommonDir).add(row.projectRoot)
  }
  var groups = Object.create(null)
  for (var i = 0; i < servers.length; i++) {
    var server = servers[i]
    var key = server.projectRoot
    if (!groups[key]) {
      var name = server.source === "docker" && key === "docker:" + server.containerId
        ? server.name : (Paths.basename(key).replace(/^compose:/, "") || key)
      groups[key] = { name: server.cwdDeleted ? name + " (deleted working directory)" : name, branch: "", count: 0,
        stopCount: targetsByRoot.get(key).size }
    }
    if (server.gitBranch && roots.has(server.gitCommonDir) && roots.get(server.gitCommonDir).size > 1)
      groups[key].branch = server.gitBranch
    groups[key].count++
  }
  return groups
}
