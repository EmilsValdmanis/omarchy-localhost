import assert from "node:assert/strict"
import test from "node:test"
import { loadQmlJs, plain } from "./support/qml_js.mjs"

const Servers = loadQmlJs("Servers.js")

test("matches the global server filters", () => {
  const commonDev = { port: 5173, source: "process", lanAvailable: false }
  const unusualLan = { port: 4567, source: "process", lanAvailable: true }
  const docker = { port: 9000, source: "docker", lanAvailable: true }

  assert.equal(Servers.matchesServerFilter(commonDev, "all"), true)
  assert.equal(Servers.matchesServerFilter(commonDev, "dev"), true)
  assert.equal(Servers.matchesServerFilter(unusualLan, "dev"), false)
  assert.equal(Servers.matchesServerFilter(unusualLan, "lan"), true)
  assert.equal(Servers.matchesServerFilter(commonDev, "lan"), false)
  assert.equal(Servers.matchesServerFilter(docker, "docker"), true)
  assert.equal(Servers.matchesServerFilter(commonDev, "docker"), false)
  assert.equal(Servers.matchesServerFilter(commonDev, "unknown"), true)
})

test("normalizes servers from discovery and model rows", () => {
  const fromDiscovery = Servers.normalizeServer({
    id: "410:991:5173",
    name: "app",
    framework: "Vite",
    frameworkId: "vite",
    pid: 410,
    startTime: 991,
    port: 5173,
    cwd: "/work/app",
    localUrl: "http://localhost:5173",
    lanUrl: "http://192.168.0.119:5173",
    lanAvailable: true,
  })
  assert.deepEqual(plain(fromDiscovery), {
    serverId: "410:991:5173",
    name: "app",
    framework: "Vite",
    frameworkId: "vite",
    pid: 410,
    startTime: 991,
    source: "process",
    containerId: "",
    dependencyStates: "",
    serviceKey: "",
    serviceName: "",
    port: 5173,
    cwd: "/work/app",
    cwdDeleted: false,
    localUrl: "http://localhost:5173",
    lanUrl: "http://192.168.0.119:5173",
    lanAvailable: true,
    lanHost: "",
    lanInterface: "",
    lanSubnet: "",
    restartAvailable: false,
    restartReason: "Restart command could not be verified",
    hint: "",
    projectRoot: "/work/app",
    projectPath: "",
    gitBranch: "",
    gitCommonDir: "",
    memoryBytes: -1,
    memoryHistoryJson: "[]",
  })

  const fromModelRow = Servers.normalizeServer({ serverId: "docker:x:8000", port: "8000" })
  assert.equal(fromModelRow.serverId, "docker:x:8000")
  assert.equal(fromModelRow.port, 8000)
  assert.equal(fromModelRow.name, "Development server")

  assert.deepEqual(plain(Servers.normalizeServer(null)), {
    serverId: "",
    name: "Development server",
    framework: "Dev server",
    frameworkId: "server",
    pid: 0,
    startTime: 0,
    source: "process",
    containerId: "",
    dependencyStates: "",
    serviceKey: "",
    serviceName: "",
    port: 0,
    cwd: "",
    cwdDeleted: false,
    localUrl: "",
    lanUrl: "",
    lanAvailable: false,
    lanHost: "",
    lanInterface: "",
    lanSubnet: "",
    restartAvailable: false,
    restartReason: "Restart command could not be verified",
    hint: "",
    projectRoot: "Other servers",
    projectPath: "",
    gitBranch: "",
    gitCommonDir: "",
    memoryBytes: -1,
    memoryHistoryJson: "[]",
  })
})

test("renames and LAN availability changes invalidate server rows", () => {
  const base = Servers.normalizeServer({ id: "a", name: "app", lanAvailable: false })
  const same = Servers.normalizeServer({ id: "a", name: "app", lanAvailable: false })
  const renamed = Object.assign({}, base, { name: "renamed" })
  const lanChanged = Object.assign({}, base, { lanAvailable: true })

  assert.equal(Servers.serversEqual(base, same), true)
  assert.equal(Servers.serversEqual(base, renamed), false)
  assert.equal(Servers.serversEqual(base, lanChanged), false)
})

test("search composes with port filters across names, paths, ports and containers", () => {
  const server = Servers.normalizeServer({ name: "Storefront", port: 5173, cwd: "/src/shop", source: "docker", containerId: "abc123" })
  for (const query of ["store", "5173", "/src", "abc123", "docker"])
    assert.equal(Servers.matchesSearch(server, query, "docker"), true)
  assert.equal(Servers.matchesSearch(server, "missing", "all"), false)
  assert.equal(Servers.matchesSearch(server, "store", "lan"), false)
})

test("project grouping is stable, searchable and distinguishes repositories with the same name", () => {
  const rows = [
    { serverId: "web", name: "web", projectRoot: "/work/atlas", projectPath: "apps/web", port: 3000 },
    { serverId: "other", name: "web", projectRoot: "/other/atlas", port: 4000 },
    { serverId: "api", name: "api", projectRoot: "/work/atlas", projectPath: "apps/api", port: 8000 },
  ].map(row => plain(Servers.normalizeServer(row)))
  assert.deepEqual(rows.slice().sort((a, b) => Servers.compareServers(a, b, true)).map(row => row.serverId), ["other", "web", "api"])
  assert.deepEqual(rows.slice().sort((a, b) => Servers.compareServers(a, b, false)).map(row => row.serverId), ["web", "other", "api"])
  assert.deepEqual(plain(Servers.projectGroups(rows)), {
    "/work/atlas": { name: "atlas", branch: "", dependencyStates: "", hiddenDependencyStates: "", count: 2, stopCount: 2 },
    "/other/atlas": { name: "atlas", branch: "", dependencyStates: "", hiddenDependencyStates: "", count: 1, stopCount: 1 },
  })
  assert.equal(Servers.matchesSearch(rows[0], "atlas", "all"), true)
  assert.equal(Servers.matchesSearch(rows[2], "apps/api", "all"), true)
  const changed = { ...rows[0], projectRoot: "/work/another" }
  assert.equal(Servers.serversEqual(rows[0], changed), false)
})

test("branch labels use active worktrees of the same repository even while filtering", () => {
  const main = Servers.normalizeServer({ projectRoot: "/work/shop", gitCommonDir: "/work/shop/.git", gitBranch: "main" })
  const checkout = { ...main, projectRoot: "/trees/shop", gitBranch: "feature/Checkout" }
  const clone = { ...main, projectRoot: "/clone/shop", gitCommonDir: "/clone/shop/.git" }
  const detached = { ...checkout, gitBranch: "" }
  assert.equal(Servers.projectGroups([main, main, clone])[main.projectRoot].branch, "")
  assert.equal(Servers.projectGroups([main, detached])[detached.projectRoot].branch, "")
  assert.equal(Servers.projectGroups([checkout], [main, checkout])[checkout.projectRoot].branch, "feature/Checkout")
  assert.equal(Servers.matchesSearch(checkout, "feature/check", "all"), true)
  assert.equal(Servers.matchesSearch(main, "feature/check", "all"), false)
})

test("project warnings identify each owning service and deduplicate its published ports", () => {
  const rows = [
    { id: "api:8000", name: "shop / api" },
    { id: "api:8001", name: "shop / api" },
    { id: "admin:9000", name: "shop / admin" },
  ].map(row => Servers.normalizeServer({ ...row, projectRoot: "/shop", dependencyStates: "redis exited" }))
  const group = Servers.projectGroups([rows[0]], rows)["/shop"]
  assert.equal(group.dependencyStates, "shop / admin → redis exited\nshop / api → redis exited")
  assert.equal(group.hiddenDependencyStates, "shop / admin → redis exited")
})
