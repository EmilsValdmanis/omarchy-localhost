import assert from "node:assert/strict"
import test from "node:test"
import { loadQmlJs, plain } from "./support/qml_js.mjs"

const Memory = loadQmlJs("Memory.js")

test("RAM formatting and totals count shared processes and containers once", () => {
  assert.equal(Memory.formatMemory(-1), "—")
  assert.equal(Memory.formatMemory(0), "0.0 MiB")
  assert.equal(Memory.formatMemory(104857600), "100 MiB")
  assert.equal(Memory.formatMemory(1073741824), "1.00 GiB")
  const result = Memory.memoryBreakdown([
    { source: "process", pid: 10, startTime: 20, memoryBytes: 104857600 },
    { source: "process", pid: 10, startTime: 20, memoryBytes: 104857600 },
    { source: "docker", containerId: "abc", memoryBytes: 52428800 },
    { source: "docker", containerId: "abc", memoryBytes: 52428800 },
    { source: "process", pid: 11, startTime: 30, memoryBytes: -1 },
    { serverId: "preview-a", source: "process", pid: 0, memoryBytes: 0 },
    { serverId: "preview-b", source: "process", pid: 0, memoryBytes: 0 },
  ])
  assert.equal(result.serverBytes, 157286400)
  assert.equal(result.measured, 4)
  assert.equal(result.unmeasured, 1)
})

test("system RAM breakdown groups measured sources by project and separates them from other usage and available RAM", () => {
  const mib = 1048576
  const servers = [
    { serverId: "web-a", projectRoot: "/work/shop", name: "Web", port: 3000, source: "process", pid: 10, startTime: 20, memoryBytes: 200 * mib },
    { serverId: "web-b", projectRoot: "/work/shop", name: "Web", port: 3001, source: "process", pid: 10, startTime: 20, memoryBytes: 200 * mib },
    { serverId: "api", projectRoot: "/work/shop", name: "API", port: 8000, source: "process", pid: 11, startTime: 21, memoryBytes: 100 * mib },
    { source: "docker", containerId: "redis", projectRoot: "/side/shop", memoryBytes: 50 * mib },
    { serverId: "unknown", name: "Unknown", port: 9000, source: "docker", containerId: "abc", memoryBytes: -1 },
  ]
  const result = plain(Memory.memoryBreakdown(servers, { totalBytes: 1000 * mib, availableBytes: 250 * mib }))
  assert.equal(result.totalBytes, 1000 * mib)
  assert.equal(result.serverBytes, 350 * mib)
  assert.equal(result.otherBytes, 400 * mib)
  assert.equal(result.availableBytes, 250 * mib)
  assert.equal(result.measured, 3)
  assert.equal(result.unmeasured, 1)
  assert.deepEqual(result.projects, [
    { key: "/work/shop", bytes: 300 * mib, barBytes: 300 * mib },
    { key: "/side/shop", bytes: 50 * mib, barBytes: 50 * mib },
  ])
  assert.equal(result.projects.reduce((sum, project) => sum + project.barBytes, 0)
    + result.otherBytes + result.availableBytes, result.totalBytes)

  const clamped = plain(Memory.memoryBreakdown(servers, { totalBytes: 400 * mib, availableBytes: 200 * mib }))
  assert.equal(clamped.otherBytes, 0)
  assert.ok(Math.abs(clamped.projects.reduce((sum, project) => sum + project.barBytes, 0)
    - 200 * mib) < 1)
  assert.deepEqual(plain(Memory.normalizeSystemMemory({ totalBytes: 10, availableBytes: 11 })),
    { totalBytes: -1, availableBytes: -1 })
})

test("resource payloads keep process identity and reject other users", () => {
  const raw = JSON.stringify({ ok: true, processes: [
    { pid: 100, uid: 1000, startTime: 10, memoryBytes: 1048576 },
    { pid: 100, uid: 1000, startTime: 11, memoryBytes: 2097152 },
    { pid: 101, uid: 0, startTime: 12, memoryBytes: 100 },
    { pid: 102, uid: 1000, startTime: 0, memoryBytes: 100 },
  ], containers: { abc123def456: 3145728, invalid: 400 }, systemMemory: { totalBytes: 1000, availableBytes: 400 } })
  assert.deepEqual(plain(Memory.parseResourcePayload(raw, 1000)), { ok: true,
    memory: { "process:100:10": 1048576, "process:100:11": 2097152, "docker:abc123def456": 3145728 },
    systemMemory: { totalBytes: 1000, availableBytes: 400 } })
  assert.equal(Memory.parseResourcePayload("invalid", 1000).ok, false)
})
