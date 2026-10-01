import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import test from "node:test"
import vm from "node:vm"

const context = vm.createContext({})
for (const file of ["RadarModel.js", "ProjectList.js"])
  vm.runInContext(readFileSync(new URL(`../qml/${file}`, import.meta.url), "utf8"), context)
const plain = value => JSON.parse(JSON.stringify(value))
const servers = [
  { serverId: "a", projectRoot: "/work/atlas", port: 3000 },
  { serverId: "b", projectRoot: "/work/atlas", port: 3001 },
  { serverId: "c", projectRoot: "/other/atlas", port: 4000 },
].map(context.normalizeServer).sort((a, b) => context.compareServers(a, b, true))
const groups = context.projectGroups(servers)

test("folding keeps distinct project headers and original server indices", () => {
  const entries = plain(context.entriesFor(servers, groups, true, { "/other/atlas": true }))
  assert.deepEqual(entries.map(entry => entry.entryId), [
    "project:/other/atlas", "project:/work/atlas", "server:a", "server:b",
  ])
  assert.deepEqual(entries.map(entry => entry.serverIndex), [-1, -1, 1, 2])
  assert.deepEqual(entries.slice(0, 2).map(entry => [entry.name, entry.count, entry.collapsed]), [
    ["atlas", 1, true], ["atlas", 2, false],
  ])
  assert.equal(context.entriesFor(servers, groups, true, { "/other/atlas": true, "/work/atlas": true }).length, 2)
  assert.equal(context.entriesFor([], {}, true, {}).length, 0)
})

test("flat lists expose every server regardless of folds", () => {
  const entries = plain(context.entriesFor(servers, groups, false, { "/work/atlas": true }))
  assert.deepEqual(entries.map(entry => entry.serverId), servers.map(server => server.serverId))
  assert.ok(entries.every((entry, index) => !entry.projectHeader && entry.serverIndex === index))
})

function modelFor() {
  return {
    rows: [], writes: 0,
    get count() { return this.rows.length },
    get(i) { return this.rows[i] },
    insert(i, row) { this.writes++; this.rows.splice(i, 0, plain(row)) },
    remove(i) { this.writes++; this.rows.splice(i, 1) },
    move(from, to) { this.writes++; this.rows.splice(to, 0, this.rows.splice(from, 1)[0]) },
    set(i, row) { this.writes++; this.rows[i] = plain(row) },
  }
}

test("folding and unfolding preserve surviving delegates and unchanged scans write nothing", () => {
  const model = modelFor()
  const open = context.entriesFor(servers, groups, true, {})
  context.syncEntries(model, open)
  const survivingServer = model.rows[4]
  const folded = context.entriesFor(servers, groups, true, { "/other/atlas": true })
  assert.equal(context.syncEntries(model, folded), true)
  assert.deepEqual(model.rows, plain(folded))
  assert.equal(model.rows[3], survivingServer)
  model.writes = 0
  assert.equal(context.syncEntries(model, folded), false)
  assert.equal(model.writes, 0)
  context.syncEntries(model, open)
  assert.deepEqual(model.rows, plain(open))
  assert.equal(model.rows[4], survivingServer)
})

test("entry synchronization handles discovery churn and grouping changes", () => {
  const model = modelFor()
  for (let tick = 0; tick < 30; tick++) {
    const rows = servers.filter((_, index) => (index + tick) % 3 !== 0)
    if (tick % 2) rows.reverse()
    const entries = context.entriesFor(rows, context.projectGroups(rows), tick % 2 === 0,
      { "/work/atlas": tick % 4 === 0 })
    context.syncEntries(model, entries)
    assert.deepEqual(model.rows, plain(entries))
  }
  context.syncEntries(model, [])
  assert.equal(model.count, 0)
})
