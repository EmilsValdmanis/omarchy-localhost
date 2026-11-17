import assert from "node:assert/strict"
import test from "node:test"
import { loadQmlJs, plain } from "./support/qml_js.mjs"

const Actions = loadQmlJs("Actions.js")
const Servers = loadQmlJs("Servers.js")
const Discovery = loadQmlJs("Discovery.js")

function listener(port) {
  return { pid: 410, port, process: "node", addresses: ["127.0.0.1"] }
}

test("project stops snapshot only their project and deduplicate processes and containers", () => {
  const native = { serverId: "web", pid: 410, startTime: 100, projectRoot: "/work/atlas", port: 3000 }
  const docker = { serverId: "api", source: "docker", containerId: "abc123", projectRoot: "/work/atlas", port: 8000 }
  const rows = [
    native, { ...native, serverId: "web-extra", port: 3001 },
    docker, { ...docker, serverId: "api-extra", port: 8001 },
    { ...native, serverId: "reused-pid", startTime: 101 },
    { ...native, serverId: "other", pid: 411, projectRoot: "/work/console" },
  ]
  const targets = Actions.projectStopTargets(rows, "/work/atlas")
  assert.deepEqual(plain(targets.map(row => row.serverId)), ["web", "api", "reused-pid"])
  const group = Servers.projectGroups(rows.slice(0, 2), rows)["/work/atlas"]
  assert.equal(group.stopCount, targets.length)
  assert.equal(Actions.projectStopHint(group), "Stop all 3 servers in atlas")
  native.pid = 999
  assert.equal(targets[0].pid, 410, "a discovery mutation cannot change queued identities")
  assert.equal(Actions.projectStopTargets(rows, "").length, 0)
  assert.equal(Actions.projectStopTargets(rows, "/work/missing").length, 0)
})

test("parses structured action responses", () => {
  assert.deepEqual(plain(Actions.parseActionPayload('{"ok":true,"message":"Server stopped"}', "fallback")), {
    ok: true,
    message: "Server stopped",
  })
  assert.deepEqual(plain(Actions.parseActionPayload('{"ok":false,"error":"stale PID"}', "fallback")), {
    ok: false,
    message: "stale PID",
    forceStopAvailable: false,
  })
  assert.equal(Actions.parseActionPayload(JSON.stringify({ ok: false,
    error: "The server did not stop cleanly; use Force stop if needed" })).forceStopAvailable, false,
    "display text does not grant permission to force stop")
  assert.equal(Actions.parseActionPayload(JSON.stringify({ ok: false,
    error: "A localized failure", forceStopAvailable: true })).forceStopAvailable, true)
})

test("restart requires verified recovery for native servers and remains available for Docker", () => {
  assert.equal(Actions.actionEnabled(Actions.ACTIONS.restart, { source: "process", restartAvailable: false }), false)
  assert.equal(Actions.actionEnabled(Actions.ACTIONS.restart, { source: "process", restartAvailable: true }), true)
  assert.equal(Actions.actionEnabled(Actions.ACTIONS.restart, { source: "docker" }), true)
  assert.equal(Actions.actionEnabled(Actions.ACTIONS.stop, { source: "process", restartAvailable: false }), true)
})

test("local actions stay local and sharing is explicit", () => {
  const server = { localUrl: "http://localhost:3000", lanUrl: "http://192.0.2.12:3000", lanAvailable: true }
  assert.equal(Actions.actionUrl(server, false), server.localUrl)
  assert.equal(Actions.actionUrl(server, true), server.lanUrl)
  assert.equal(Actions.actionEnabled(Actions.ACTIONS.copyLan, server), true)
  server.lanAvailable = false
  assert.equal(Actions.actionUrl(server, true), "")
  assert.equal(Actions.actionEnabled(Actions.ACTIONS.copyLan, server), false)
  assert.equal(Actions.actionEnabled(Actions.ACTIONS.qr, server), false)
  assert.equal(Actions.actionEnabled(Actions.ACTIONS.copyLocal, server), true)
})

test("unavailable LAN sharing explains loopback binds separately from missing network addresses", () => {
  const context = { listener: listener(3000), process: { cwd: "/work", startTime: 1 }, framework: { name: "Vite", id: "vite" } }
  const local = Discovery.serverFromContext(context, "http", { ip: "192.168.1.2" })
  assert.equal(Actions.actionEnabled(Actions.ACTIONS.qr, local), false)
  assert.match(Actions.lanUnavailableReason(local), /localhost only.*0\.0\.0\.0/)
  context.listener.addresses = ["0.0.0.0"]
  const offline = Discovery.serverFromContext(context, "http", { ip: "" })
  assert.equal(Actions.actionEnabled(Actions.ACTIONS.qr, offline), false)
  assert.match(Actions.lanUnavailableReason(offline), /No LAN address.*LAN interface/)
  const available = Discovery.serverFromContext(context, "http", { ip: "192.168.1.2" })
  assert.equal(Actions.actionEnabled(Actions.ACTIONS.qr, available), true)
  assert.equal(Actions.lanUnavailableReason(available), "")
  assert.match(Actions.lanUnavailableReason(null), /Select a server/)
})
