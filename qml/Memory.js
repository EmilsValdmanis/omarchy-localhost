.import "Sources.js" as Sources

var HISTORY_LIMIT = 30

function validMemory(value) {
  if (value === undefined || value === null || value === "") return -1
  var bytes = Number(value)
  return Number.isFinite(bytes) && bytes >= 0 ? Math.round(bytes) : -1
}

function parseResourcePayload(raw, currentUid) {
  var memory = {}
  try {
    var payload = JSON.parse(String(raw || ""))
    if (!payload || payload.ok !== true) return { ok: false, memory: memory }
    var processes = Array.isArray(payload.processes) ? payload.processes : []
    for (var i = 0; i < processes.length; i++) {
      var process = processes[i]
      var pid = Number(process.pid)
      var startTime = Number(process.startTime)
      if (Number(process.uid) !== Number(currentUid) || !Number.isInteger(pid) || pid <= 1
          || !Number.isInteger(startTime) || startTime <= 0) continue
      memory[Sources.key(process)] = validMemory(process.memoryBytes)
    }
    var containers = payload.containers || {}
    for (var id in containers)
      if (/^[0-9a-f]{12,64}$/.test(id)) memory[Sources.key({ source: "docker", containerId: id })] = validMemory(containers[id])
    return { ok: true, memory: memory, systemMemory: normalizeSystemMemory(payload.systemMemory) }
  } catch (exception) { return { ok: false, memory: memory } }
}

function normalizeSystemMemory(value) {
  var total = validMemory(value && value.totalBytes)
  var available = validMemory(value && value.availableBytes)
  if (total <= 0 || available < 0 || available > total)
    return { totalBytes: -1, availableBytes: -1 }
  return { totalBytes: total, availableBytes: available }
}

function formatMemory(value) {
  var bytes = validMemory(value)
  if (bytes < 0) return "—"
  var mib = bytes / 1048576
  if (mib >= 1024) return (mib / 1024).toFixed(2) + " GiB"
  if (mib >= 10) return Math.round(mib) + " MiB"
  return mib.toFixed(1) + " MiB"
}

function parseMemoryHistory(value) {
  var samples = value
  if (typeof value === "string") {
    try { samples = JSON.parse(value) } catch (exception) { return [] }
  }
  if (!Array.isArray(samples)) return []
  return samples.slice(-HISTORY_LIMIT).map(validMemory).filter(function(bytes) { return bytes >= 0 })
}

function memorySummary(servers) {
  var seen = Object.create(null)
  var total = 0
  var measured = 0
  var unmeasured = 0
  for (var index = 0; index < servers.length; index++) {
    var row = servers[index]
    var key = Sources.key(row)
    if (seen[key]) continue
    seen[key] = true
    var bytes = validMemory(row.memoryBytes)
    if (bytes < 0) unmeasured++
    else { total += bytes; measured++ }
  }
  return { totalBytes: total, measured: measured, unmeasured: unmeasured }
}

function memoryBreakdown(servers, systemMemory) {
  var system = normalizeSystemMemory(systemMemory)
  var summary = memorySummary(servers)
  var seen = Object.create(null)
  var sources = []
  for (var index = 0; index < servers.length; index++) {
    var row = servers[index]
    var key = Sources.key(row)
    if (seen[key]) continue
    seen[key] = true
    var bytes = validMemory(row.memoryBytes)
    if (bytes >= 0) sources.push({ key: key, name: String(row.name || "Server"),
      port: Number(row.port || 0), bytes: bytes })
  }
  var used = system.totalBytes < 0 ? -1 : system.totalBytes - system.availableBytes
  var shownServers = used < 0 ? 0 : Math.min(summary.totalBytes, used)
  var scale = summary.totalBytes > 0 ? shownServers / summary.totalBytes : 0
  for (var sourceIndex = 0; sourceIndex < sources.length; sourceIndex++)
    sources[sourceIndex].barBytes = sources[sourceIndex].bytes * scale
  return {
    totalBytes: system.totalBytes,
    availableBytes: system.availableBytes,
    serverBytes: summary.totalBytes,
    otherBytes: used < 0 ? -1 : used - shownServers,
    measured: summary.measured,
    unmeasured: summary.unmeasured,
    sources: sources
  }
}
