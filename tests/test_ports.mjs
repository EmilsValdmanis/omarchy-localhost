import assert from "node:assert/strict"
import test from "node:test"
import { loadQmlJs, plain } from "./support/qml_js.mjs"

const Ports = loadQmlJs("Ports.js")

test("port preferences are reversible within ranges and preserve unrelated settings", () => {
  const settings = { ignoredPorts: "3000-3010,8000", alwaysIncludePorts: "7000-7005", includeDocker: false, lanInterface: "wlan0" }
  const included = plain(Ports.portPreferenceSettings(settings, 3005, true))
  assert.deepEqual(included, { ...settings, ignoredPorts: "3000-3004,3006-3010,8000", alwaysIncludePorts: "3005,7000-7005" })
  assert.equal(settings.ignoredPorts, "3000-3010,8000", "do not mutate the host's settings object")
  assert.deepEqual(plain(Ports.portPreferenceSettings(included, 3005, false)), settings)
  const skipped = plain(Ports.portPreferenceSettings(settings, 7002, false))
  assert.equal(skipped.alwaysIncludePorts, "7000-7001,7003-7005")
  assert.equal(Ports.parsePortSet(skipped.ignoredPorts)[7002], true)
  assert.deepEqual(plain(Ports.portPreferenceSettings(skipped, 7002, false)), skipped)
  for (const port of [0, -1, 65536, 3.5, "invalid"]) assert.equal(Ports.portPreferenceSettings(settings, port, true), null)
  const many = Ports.parsePortSet("1-4097,4098-8194")
  assert.deepEqual(plain(Ports.parsePortSet(Ports.formatPortSet(many))), plain(many), "large sets remain parseable after formatting")
})

test("parses bounded port settings", () => {
  assert.deepEqual(plain(Ports.parsePortSet("3000, 8000-8002, 9:10, bad, 0, 70000")), {
    9: true,
    10: true,
    3000: true,
    8000: true,
    8001: true,
    8002: true,
  })
})
