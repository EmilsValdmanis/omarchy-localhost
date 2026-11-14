import assert from "node:assert/strict"
import test from "node:test"
import { loadQmlJs, plain } from "./support/qml_js.mjs"

const Diagnostics = loadQmlJs("Diagnostics.js")

test("skipped port explanations preserve unknown reasons and avoid claiming a failed probe is not a web server", () => {
  assert.equal(Diagnostics.skippedPortPresentation("ignored").text, "Excluded in settings")
  assert.equal(Diagnostics.skippedPortPresentation("no-response").text, "No response to the HTTP / HTTPS check")
  assert.equal(Diagnostics.skippedPortPresentation("non-http").text, "Port usually used by a non-web service")
  for (const reason of ["A future diagnostic reason", "constructor", "__proto__"])
    assert.equal(Diagnostics.skippedPortPresentation(reason).text, reason)
  assert.equal(Diagnostics.skippedPortPresentation(null).text, "Reason unavailable")
})

test("skipped groups put manual choices first and preserve entry order within each section", () => {
  const diagnostics = [
    { port: 3000, reason: "runtime-helper" },
    { port: 8000, reason: "ignored" },
    { port: 4206, reason: "devtools" },
  ]
  const groups = Diagnostics.skippedPortGroups(diagnostics)
  assert.deepEqual(plain(groups.manual), [diagnostics[1]])
  assert.deepEqual(plain(groups.automatic), [diagnostics[0], diagnostics[2]])
  const folded = plain(Diagnostics.skippedPortEntries(groups, { automatic: true }))
  assert.deepEqual(folded.map(entry => entry.kind === "header" ? entry.name : entry.port), ["Manual", 8000, "Automatic"])
  assert.equal(folded[2].count, 2)
  assert.equal(Diagnostics.skippedPortEntries(groups, {}).length, 5)
  assert.equal(Diagnostics.skippedPortEntries(groups, { manual: true, automatic: true }).length, 2)
  assert.deepEqual(plain(Diagnostics.skippedPortEntries(Diagnostics.skippedPortGroups([]), {})), [])
})
