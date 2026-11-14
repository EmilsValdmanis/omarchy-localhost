var catalog = {
  metadataUnavailable: ["metadata-unavailable", "Process details unavailable", "\uf059"],
  ignored: ["ignored", "Excluded in settings", "\uf013"],
  privileged: ["privileged", "System port (below 1024)", "\uf108"],
  excludedProcess: ["excluded-process", "Desktop or system process", "\uf108"],
  runtimeHelper: ["runtime-helper", "Runtime helper", "\uf085"],
  devtools: ["devtools", "TanStack Devtools \u00b7 helper endpoint", "\uf085"],
  worker: ["worker", "Azure Functions \u00b7 worker endpoint", "\uf085"],
  nonHttp: ["non-http", "Port usually used by a non-web service", "\uf1c0"],
  debugger: ["debugger", "Debugger port", "\uf188"],
  unrecognized: ["unrecognized", "Not recognized as a dev server", "\uf059"],
  noResponse: ["no-response", "No response to the HTTP / HTTPS check", "\uf127"]
}
var REASONS = {}
var presentations = Object.create(null)
for (var name in catalog) {
  var entry = catalog[name]
  REASONS[name] = entry[0]
  presentations[entry[0]] = { text: entry[1], icon: entry[2] }
}

function skippedPortGroups(diagnostics) {
  var groups = { manual: [], automatic: [] }
  for (var i = 0; i < diagnostics.length; i++) {
    var entry = diagnostics[i]
    groups[entry.reason === REASONS.ignored ? "manual" : "automatic"].push(entry)
  }
  return groups
}

function skippedPortEntries(groups, collapsed) {
  if (!groups.manual.length && !groups.automatic.length) return []
  var entries = []
  var occurrences = Object.create(null)
  for (var id of ["manual", "automatic"]) {
    entries.push({ entryId: "group:" + id, kind: "header", groupId: id, name: id === "manual" ? "Manual" : "Automatic",
      count: groups[id].length, collapsed: collapsed[id] === true, port: 0, process: "", reason: "" })
    if (!collapsed[id]) for (var diagnostic of groups[id]) {
      var key = JSON.stringify([id, diagnostic.port, diagnostic.process])
      var occurrence = occurrences[key] || 0
      occurrences[key] = occurrence + 1
      entries.push({ entryId: "port:" + key + ":" + occurrence, kind: "port", groupId: id,
        name: "", count: 0, collapsed: false, port: diagnostic.port,
        process: diagnostic.process || "Unknown process", reason: diagnostic.reason || "" })
    }
  }
  return entries
}

function skippedEntriesEqual(left, right) {
  return left.entryId === right.entryId && left.kind === right.kind && left.groupId === right.groupId
    && left.name === right.name && left.count === right.count && left.collapsed === right.collapsed
    && left.port === right.port && left.process === right.process && left.reason === right.reason
}

function skippedPortPresentation(reason) {
  var key = String(reason || "")
  return presentations[key] || { text: key || "Reason unavailable", icon: "\uf05a" }
}
