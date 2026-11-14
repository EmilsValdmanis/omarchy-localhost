import assert from "node:assert/strict"
import test from "node:test"

import { loadQmlJs, plain, listModel } from "./support/qml_js.mjs"

const Servers = loadQmlJs("Servers.js")
const ProjectList = loadQmlJs("ProjectList.js")
const ListModelSync = loadQmlJs("ListModelSync.js")
const servers = [
  { serverId: "a", projectRoot: "/work/atlas", port: 3000 },
  { serverId: "b", projectRoot: "/work/atlas", port: 3001 },
  { serverId: "c", projectRoot: "/other/atlas", port: 4000 },
].map(Servers.normalizeServer).sort((a, b) => Servers.compareServers(a, b, true))
const groups = Servers.projectGroups(servers)

test("folding keeps distinct project headers and original server indices", () => {
  const entries = plain(ProjectList.entriesFor(servers, groups, true, { "/other/atlas": true }))
  assert.deepEqual(entries.map(entry => entry.entryId), [
    "project:/other/atlas", "project:/work/atlas", "server:a", "server:b",
  ])
  assert.deepEqual(entries.map(entry => entry.serverIndex), [-1, -1, 1, 2])
  assert.deepEqual(entries.slice(0, 2).map(entry => [entry.name, entry.count, entry.collapsed]), [
    ["atlas", 1, true], ["atlas", 2, false],
  ])
  assert.equal(ProjectList.entriesFor(servers, groups, true, { "/other/atlas": true, "/work/atlas": true }).length, 2)
  assert.equal(ProjectList.entriesFor([], {}, true, {}).length, 0)
})

test("flat lists expose every server regardless of folds", () => {
  const entries = plain(ProjectList.entriesFor(servers, groups, false, { "/work/atlas": true }))
  assert.deepEqual(entries.map(entry => entry.serverId), servers.map(server => server.serverId))
  assert.ok(entries.every((entry, index) => !entry.projectHeader && entry.serverIndex === index))
})

test("folding and unfolding preserve surviving delegates and unchanged scans write nothing", () => {
  const model = listModel()
  const open = ProjectList.entriesFor(servers, groups, true, {})
  ListModelSync.sync(model, open, "entryId", ProjectList.entriesEqual)
  const survivingServer = model.rows[4]
  const folded = ProjectList.entriesFor(servers, groups, true, { "/other/atlas": true })
  assert.equal(ListModelSync.sync(model, folded, "entryId", ProjectList.entriesEqual), true)
  assert.deepEqual(model.rows, plain(folded))
  assert.equal(model.rows[3], survivingServer)
  model.writes = 0
  assert.equal(ListModelSync.sync(model, folded, "entryId", ProjectList.entriesEqual), false)
  assert.equal(model.writes, 0)
  ListModelSync.sync(model, open, "entryId", ProjectList.entriesEqual)
  assert.deepEqual(model.rows, plain(open))
  assert.equal(model.rows[4], survivingServer)
})

test("entry synchronization handles discovery churn and grouping changes", () => {
  const model = listModel()
  for (let tick = 0; tick < 30; tick++) {
    const rows = servers.filter((_, index) => (index + tick) % 3 !== 0)
    if (tick % 2) rows.reverse()
    const entries = ProjectList.entriesFor(rows, Servers.projectGroups(rows), tick % 2 === 0,
      { "/work/atlas": tick % 4 === 0 })
    ListModelSync.sync(model, entries, "entryId", ProjectList.entriesEqual)
    assert.deepEqual(model.rows, plain(entries))
  }
  ListModelSync.sync(model, [], "entryId", ProjectList.entriesEqual)
  assert.equal(model.count, 0)
})
