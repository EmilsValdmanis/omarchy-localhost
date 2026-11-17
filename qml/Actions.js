.import "Sources.js" as Sources
.import "Servers.js" as Servers

var ACTIONS = { open: 0, copyLocal: 1, copyLan: 2, qr: 3, terminal: 4, project: 5, restart: 6, stop: 7, skip: 8 }

var primary = [
  { action: ACTIONS.open, label: "Open", icon: "\uf08e", tip: "Open local URL (Enter)" },
  { action: ACTIONS.copyLocal, label: "Copy", icon: "\uf0c5", tip: "Copy local URL (Ctrl+C)" },
  { action: ACTIONS.qr, label: "QR", icon: "\uf029", tip: "" }
]
var secondary = [
  { action: ACTIONS.terminal, icon: "\uf120", tip: "Open terminal here" },
  { action: ACTIONS.project, icon: "\uf121", tip: "Open in editor" },
  { action: ACTIONS.restart, icon: "\uf2f9", tip: "Restart server (Alt+R)" },
  { action: ACTIONS.skip, icon: "\uf05e", tip: "Skip this port for all listeners. Restore it from Skipped." },
  { action: ACTIONS.stop, icon: "\uf04d", tip: "Stop server (Delete)" }
]
var visibleOrder = primary.concat(secondary).map(function(entry) { return entry.action })

function actionUrl(server, shareOverLan) {
  if (!server) return ""
  return shareOverLan ? (server.lanAvailable ? String(server.lanUrl || "") : "") : String(server.localUrl || "")
}

function projectStopTargets(servers, projectRoot) {
  var targets = []
  var seen = Object.create(null)
  if (!projectRoot) return targets
  for (var index = 0; index < servers.length; index++) {
    var server = Servers.normalizeServer(servers[index])
    if (server.projectRoot !== projectRoot) continue
    var key = Sources.key(server)
    if (!seen[key]) {
      seen[key] = true
      targets.push(server)
    }
  }
  return targets
}

function projectStopHint(group) {
  if (!group) return ""
  var total = group.stopCount
  return "Stop " + (total === 1 ? "1 server" : "all " + total + " servers") + " in " + group.name
}

function actionEnabled(index, server, busy) {
  return !!server && (!busy || (index !== ACTIONS.restart && index !== ACTIONS.stop))
    && ((index !== ACTIONS.copyLan && index !== ACTIONS.qr) || actionUrl(server, true) !== "")
    && ((index !== ACTIONS.open && index !== ACTIONS.copyLocal) || !!server.localUrl)
    && (index !== ACTIONS.restart || (!server.cwdDeleted && (server.source === "docker" || server.restartAvailable === true)))
    && ((index !== ACTIONS.terminal && index !== ACTIONS.project) || (!!server.cwd && !server.cwdDeleted))
}

function lanUnavailableReason(server) {
  if (!server) return "Select a server to share over LAN."
  if (actionUrl(server, true)) return ""
  return String(server.hint || "No LAN URL is available. Check the server's bind address and network connection.")
}

function parseActionPayload(raw, fallback) {
  try {
    var payload = JSON.parse(String(raw || ""))
    if (payload && payload.ok === true)
      return { ok: true, message: String(payload.message || fallback || "Action completed") }
    var failure = { ok: false, message: String((payload && payload.error) || fallback || "Action failed"),
      forceStopAvailable: !!payload && payload.forceStopAvailable === true }
    if (payload && typeof payload.log === "string" && payload.log.startsWith("/")) failure.logPath = payload.log
    return failure
  } catch (exception) {
    return { ok: false, message: String(fallback || "Action failed") }
  }
}
