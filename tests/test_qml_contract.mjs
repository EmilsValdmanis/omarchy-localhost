import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import test from "node:test"

const service = readFileSync(new URL("../RadarService.qml", import.meta.url), "utf8")
const widget = readFileSync(new URL("../Widget.qml", import.meta.url), "utf8")
const panel = readFileSync(new URL("../ServerPanel.qml", import.meta.url), "utf8")
const readme = readFileSync(new URL("../README.md", import.meta.url), "utf8")

test("process actions cross the verified helper boundary", () => {
  assert.match(service, /"python3", helperPath, "process-action"/)
  assert.match(service, /"--start-time", String\(server\.startTime\)/)
  assert.match(service, /function forceStop\(server\)/)
  assert.doesNotMatch(service, /kill -TERM|kill -KILL/)
})

test("discovery settings are wired from the manifest-facing widget", () => {
  assert.match(widget, /includeDocker: root\.setting\("includeDocker", true\)/)
  assert.match(widget, /ignoredPorts: String\(root\.setting\("ignoredPorts", ""\)/)
  assert.match(widget, /alwaysIncludePorts: String\(root\.setting\("alwaysIncludePorts", ""\)/)
  assert.match(service, /RadarModel\.parsePortSet\(ignoredPorts\)/)
  assert.match(service, /RadarModel\.parsePortSet\(alwaysIncludePorts\)/)
  assert.match(service, /exec timeout 3s docker \\\"\$@\\\"/)
  assert.doesNotMatch(service, /shift; exec docker/)
})

test("the bar icon is centered and hidden when it has no servers by default", () => {
  assert.match(widget, /readonly property bool showWhenEmpty: setting\("showWhenEmpty", false\)/)
  assert.match(widget, /visible: serverCount > 0 \|\| showWhenEmpty/)
  assert.doesNotMatch(widget, /visible: serverCount > 0 \|\| showWhenEmpty \|\|/)
  assert.match(widget, /OpticalGlyph\s*\{\s*anchors\.centerIn: parent\s*anchors\.verticalCenterOffset: -Style\.spaceReal\(1\)/)
  assert.doesNotMatch(widget, /OpticalGlyph\s*\{[\s\S]*?y: Style\.spaceReal\(1\)[\s\S]*?text: "\\uf0ac"/)
})

test("the server count badge overlays the button outside the icon canvas", () => {
  assert.match(widget, /iconComponent: Component\s*\{[\s\S]*?OpticalGlyph[\s\S]*?\}\s*\}\s*Rectangle\s*\{\s*id: countBadge/)
  assert.match(widget, /id: countBadge[\s\S]*?visible: root\.showCountBadge && root\.serverCount > 0/)
  assert.match(widget, /text: root\.serverCount > 9 \? "9\+" : String\(root\.serverCount\)/)
})

test("the global shortcut targets the bar widget instead of the QR overlay", () => {
  assert.match(widget, /IpcHandler\s*\{\s*target: root\.moduleName[\s\S]*?function toggle\(\): string/)
  assert.match(readme, /omarchy-shell emils\.localhost toggle/)
  assert.doesNotMatch(readme, /omarchy-shell shell toggle emils\.localhost/)
})

test("scrolling uses native Qt views without wheel interception", () => {
  assert.doesNotMatch(panel, /onWheel|cancelFlick|contentY\s*=/)
  assert.match(panel, /ScrollBar\.AsNeeded/)
  assert.match(panel, /Layout\.fillHeight: true/)
})

test("firewall writes are explicit, scoped, and manageable", () => {
  assert.match(panel, /persistent UFW rule limited to/)
  assert.match(widget, /"pkexec", "\/usr\/bin\/ufw", "allow", "in", "on"/)
  assert.match(widget, /"--force", "delete", "allow", "in", "on"/)
  assert.match(widget, /onFirewallRemovalConfirmed/)
  assert.match(widget, /parseManagedUfwRules/)
  assert.match(panel, /iconText: "󰒘"/)
  assert.doesNotMatch(panel, /iconText: "\\uf3ed"/)
  assert.match(panel, /text: "Remove"/)
  assert.doesNotMatch(panel, /iconText: "\\uf2ed"/)
})
