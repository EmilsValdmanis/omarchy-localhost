import assert from "node:assert/strict"
import test from "node:test"

import { loadQmlJs, plain, listModel } from "./support/qml_js.mjs"

const Servers = loadQmlJs("Servers.js")

test("stable scans use linear reads and never mutate the model", () => {
  const rows = Array.from({ length: 1000 }, (_, i) => ({ serverId: String(i), port: i + 3000 }))
  const model = listModel(rows.map(Servers.normalizeServer))
  const first = model.rows[0]
  assert.equal(Servers.syncServerModel(model, rows), false)
  assert.equal(model.writes, 0)
  assert.ok(model.reads <= rows.length * 3)
  assert.equal(model.rows[0], first)
})

test("sync handles insertions, removals, reordering, edits and duplicate IDs", () => {
  const model = listModel([{ serverId: "a" }, { serverId: "b" }, { serverId: "c" }].map(Servers.normalizeServer))
  const rows = [{ serverId: "c", name: "renamed" }, { serverId: "d" }, { serverId: "b" }]
  assert.equal(Servers.syncServerModel(model, [...rows, {}, { serverId: "d" }]), true)
  assert.deepEqual(model.rows, rows.map(row => plain(Servers.normalizeServer(row))))
  assert.equal(Servers.syncServerModel(model, rows), false)
  assert.equal(Servers.syncServerModel(model, []), true)
  assert.equal(model.count, 0)
})

test("sync agrees with full replacement through repeated deterministic churn", () => {
  const model = listModel()
  for (let tick = 0; tick < 100; tick++) {
    const rows = Array.from({ length: 30 }, (_, i) => ({ serverId: String(i), name: `${tick}:${i}` }))
      .filter((_, i) => (i + tick) % 3 !== 0)
    if (tick % 2) rows.reverse()
    Servers.syncServerModel(model, rows)
    assert.deepEqual(model.rows, rows.map(row => plain(Servers.normalizeServer(row))))
  }
})

test("prototype names are valid server IDs", () => {
  const model = listModel()
  Servers.syncServerModel(model, [{ serverId: "__proto__" }, { serverId: "constructor" }])
  assert.equal(model.count, 2)
})
