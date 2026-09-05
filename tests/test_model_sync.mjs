import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import test from "node:test"
import vm from "node:vm"

const radar = vm.createContext({})
vm.runInContext(readFileSync(new URL("../RadarModel.js", import.meta.url), "utf8"), radar)
const plain = value => JSON.parse(JSON.stringify(value))

function modelFor(rows = []) {
  return {
    rows: rows.map(row => plain(radar.normalizeServer(row))), writes: 0, reads: 0,
    get count() { return this.rows.length },
    get(i) { this.reads++; return this.rows[i] },
    insert(i, row) { this.writes++; this.rows.splice(i, 0, plain(row)) },
    remove(i) { this.writes++; this.rows.splice(i, 1) },
    move(from, to) { this.writes++; this.rows.splice(to, 0, this.rows.splice(from, 1)[0]) },
    set(i, row) { this.writes++; this.rows[i] = plain(row) },
  }
}

test("stable scans use linear reads and never mutate the model", () => {
  const rows = Array.from({ length: 1000 }, (_, i) => ({ serverId: String(i), port: i + 3000 }))
  const model = modelFor(rows)
  const first = model.rows[0]
  assert.equal(radar.syncServerModel(model, rows), false)
  assert.equal(model.writes, 0)
  assert.ok(model.reads <= rows.length * 3)
  assert.equal(model.rows[0], first)
})

test("sync handles insertions, removals, reordering, edits and duplicate IDs", () => {
  const model = modelFor([{ serverId: "a" }, { serverId: "b" }, { serverId: "c" }])
  const rows = [{ serverId: "c", name: "renamed" }, { serverId: "d" }, { serverId: "b" }]
  assert.equal(radar.syncServerModel(model, [...rows, {}, { serverId: "d" }]), true)
  assert.deepEqual(model.rows, rows.map(row => plain(radar.normalizeServer(row))))
  assert.equal(radar.syncServerModel(model, rows), false)
  assert.equal(radar.syncServerModel(model, []), true)
  assert.equal(model.count, 0)
})

test("sync agrees with full replacement through repeated deterministic churn", () => {
  const model = modelFor()
  for (let tick = 0; tick < 100; tick++) {
    const rows = Array.from({ length: 30 }, (_, i) => ({ serverId: String(i), name: `${tick}:${i}` }))
      .filter((_, i) => (i + tick) % 3 !== 0)
    if (tick % 2) rows.reverse()
    radar.syncServerModel(model, rows)
    assert.deepEqual(model.rows, rows.map(row => plain(radar.normalizeServer(row))))
  }
})

test("prototype names are valid server IDs", () => {
  const model = modelFor()
  radar.syncServerModel(model, [{ serverId: "__proto__" }, { serverId: "constructor" }])
  assert.equal(model.count, 2)
})

test("search composes with port filters across names, paths, ports and containers", () => {
  const server = radar.normalizeServer({ name: "Storefront", port: 5173, cwd: "/src/shop", source: "docker", containerId: "abc123" })
  for (const query of ["store", "5173", "/src", "abc123", "docker"])
    assert.equal(radar.matchesSearch(server, query, "docker"), true)
  assert.equal(radar.matchesSearch(server, "missing", "all"), false)
  assert.equal(radar.matchesSearch(server, "store", "lan"), false)
})

test("successful and failed probe caches both expire", () => {
  const contexts = [1, 2, 3, 4].map(pid => ({
    listener: { pid, port: 3000 + pid }, process: { startTime: 10 },
  }))
  const ids = contexts.map(context => radar.contextId(context))
  const cache = {
    [ids[0]]: { scheme: "http", expiresAt: 101 },
    [ids[1]]: { scheme: "https", expiresAt: 100 },
    [ids[2]]: { scheme: "", expiresAt: 101 },
  }
  const plan = radar.probePlan(contexts, cache, 100)
  assert.deepEqual(plain(plan.schemes), { [ids[0]]: "http" })
  assert.deepEqual(plain(plan.pending), plain([contexts[1], contexts[3]]))
  assert.equal(radar.probePlan(contexts, cache, 101).pending.length, 4)
})

test("project grouping is stable, searchable and distinguishes repositories with the same name", () => {
  const rows = [
    { serverId: "web", name: "web", projectRoot: "/work/atlas", projectPath: "apps/web", port: 3000 },
    { serverId: "other", name: "web", projectRoot: "/other/atlas", port: 4000 },
    { serverId: "api", name: "api", projectRoot: "/work/atlas", projectPath: "apps/api", port: 8000 },
  ].map(row => plain(radar.normalizeServer(row)))
  assert.deepEqual(rows.slice().sort((a, b) => radar.compareServers(a, b, true)).map(row => row.serverId), ["other", "web", "api"])
  assert.deepEqual(rows.slice().sort((a, b) => radar.compareServers(a, b, false)).map(row => row.serverId), ["web", "other", "api"])
  assert.deepEqual(plain(radar.projectGroups(rows)), {
    "/work/atlas": { name: "atlas", count: 2 }, "/other/atlas": { name: "atlas", count: 1 },
  })
  assert.equal(radar.matchesSearch(rows[0], "atlas", "all"), true)
  assert.equal(radar.matchesSearch(rows[2], "apps/api", "all"), true)
  const changed = { ...rows[0], projectRoot: "/work/another" }
  assert.equal(radar.serversEqual(rows[0], changed), false)
})
