import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import test from "node:test"

const service = readFileSync(new URL("../qml/RadarService.qml", import.meta.url), "utf8")
const widget = readFileSync(new URL("../Widget.qml", import.meta.url), "utf8")
const panel = readFileSync(new URL("../qml/ServerPanel.qml", import.meta.url), "utf8")
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
  assert.match(widget, /selectedLanInterface: String\(root\.setting\("lanInterface", ""\)/)
  assert.match(service, /RadarModel\.parsePortSet\(ignoredPorts\)/)
  assert.match(service, /RadarModel\.parsePortSet\(alwaysIncludePorts\)/)
  assert.match(service, /exec timeout 3s docker \\\"\$@\\\"/)
  assert.doesNotMatch(service, /shift; exec docker/)
})

test("the bar icon and count share Omarchy's themed text label", () => {
  assert.match(widget, /readonly property bool showWhenEmpty: setting\("showWhenEmpty", false\)/)
  assert.match(widget, /visible: serverCount > 0 \|\| showWhenEmpty/)
  assert.doesNotMatch(widget, /visible: serverCount > 0 \|\| showWhenEmpty \|\|/)
  assert.match(widget, /readonly property bool showServerCount: setting\("showCountBadge", true\)/)
  assert.match(widget, /readonly property string countLabel: showServerCount && serverCount > 0 \? String\(serverCount\) : ""/)
  assert.match(widget, /WidgetButton\s*\{\s*id: button\s*objectName: "localhostBarButton"\s*anchors\.fill: parent\s*bar: root\.bar/)
  assert.match(widget, /text: root\.vertical \? "" : root\.glyph \+ \(root\.countLabel \? " " \+ root\.countLabel : ""\)/)
  assert.doesNotMatch(widget, /countBadge|badgeInk|"9\+"/)
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
  assert.match(widget, /"on", server\.lanInterface/)
  assert.match(widget, /"from", server\.lanSubnet/)
  assert.match(widget, /rules, server\.lanInterface, server\.lanSubnet, server\.port/)
  assert.match(panel, /server\.lanSubnet \+ " on " \+ server\.lanInterface/)
  assert.doesNotMatch(widget, /rules, radar\.lanInterface|"on", radar\.lanInterface|"from", radar\.lanSubnet/)
})

test("every explicit refresh uses the cache-bypassing entry point", () => {
  assert.match(widget, /function refresh\(\): string \{ radar\.refresh\(\)/)
  assert.match(widget, /mouseButton === Qt\.RightButton\) \{\s*radar\.refresh\(\)/)
  assert.match(widget, /onRefreshRequested: \{\s*radar\.refresh\(\)/)
  assert.match(service, /function refresh\(\) \{ scan\(true\) \}/)
  assert.match(service, /Date\.now\(\), bypassProbeCache/)
  assert.match(service, /onTriggered: if \(!root\.scanning\) root\.scan\(\)/)
})
