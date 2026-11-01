import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import test from "node:test"
import vm from "node:vm"

const service = readFileSync(new URL("../qml/RadarService.qml", import.meta.url), "utf8")
const discovery = readFileSync(new URL("../qml/RadarDiscovery.qml", import.meta.url), "utf8")
const widget = readFileSync(new URL("../Widget.qml", import.meta.url), "utf8")
const panel = readFileSync(new URL("../qml/ServerPanel.qml", import.meta.url), "utf8")
const detailRow = readFileSync(new URL("../qml/DetailRow.qml", import.meta.url), "utf8")
const readme = readFileSync(new URL("../README.md", import.meta.url), "utf8")

test("port choices persist through the host API, preserve settings, and report save failures", () => {
  const model = vm.createContext({})
  vm.runInContext(readFileSync(new URL("../qml/RadarModel.js", import.meta.url), "utf8"), model)
  let refreshes = 0
  let saved = null
  let notice = null
  let accepted = true
  const settings = { ignoredPorts: "3000-3010", alwaysIncludePorts: "", includeDocker: false }
  const context = vm.createContext({
    RadarModel: model, root: { settings }, moduleName: "emils.localhost",
    setting: (key, fallback) => settings[key] ?? fallback,
    bar: { shell: { updateEntryInline(id, next) { assert.equal(id, "emils.localhost"); saved = next; return accepted } } },
    radar: { refresh() { refreshes++ } }, showNotice: (text, urgent) => { notice = { text, urgent } },
  })
  vm.runInContext(widget.match(/  function portSettingsApi\(host\) \{[^\n]+\}/)[0], context)
  vm.runInContext(widget.match(/  function setPortIncluded\(port, include\) \{[\s\S]*?\n  \}/)[0], context)
  context.setPortIncluded(3005, true)
  assert.equal(saved.ignoredPorts, "3000-3004,3006-3010")
  assert.equal(saved.alwaysIncludePorts, "3005")
  assert.equal(saved.includeDocker, false)
  assert.equal(refreshes, 1)
  assert.equal(notice.urgent, false)
  accepted = false
  context.setPortIncluded(8000, false)
  assert.equal(refreshes, 1, "a rejected save does not pretend to apply the preference")
  assert.equal(notice.urgent, true)
})

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
  assert.match(discovery, /RadarModel\.parsePortSet\(ignoredPorts\)/)
  assert.match(discovery, /RadarModel\.parsePortSet\(alwaysIncludePorts\)/)
  assert.match(discovery, /exec timeout 3s docker \\\"\$@\\\"/)
  assert.doesNotMatch(discovery, /shift; exec docker/)
})

test("the bar icon and count share Omarchy's themed text label", () => {
  assert.match(widget, /readonly property bool showWhenEmpty: setting\("showWhenEmpty", false\)/)
  assert.match(widget, /visible: serverCount > 0 \|\| showWhenEmpty/)
  assert.match(widget, /visible: serverCount > 0 \|\| showWhenEmpty \|\| hasManagedSkippedPorts/)
  assert.match(widget, /readonly property bool showServerCount: setting\("showCountBadge", true\)/)
  assert.match(widget, /readonly property string countLabel: showServerCount && serverCount > 0 \? String\(serverCount\) : ""/)
  assert.match(widget, /text: root\.vertical \? "" : root\.glyph \+ \(root\.countLabel \? " " \+ root\.countLabel : ""\)/)
})

test("the global shortcut targets the bar widget instead of the QR overlay", () => {
  assert.match(widget, /IpcHandler\s*\{\s*target: root\.moduleName[\s\S]*?function toggle\(\): string/)
  assert.match(readme, /omarchy-shell emils\.localhost toggle/)
  assert.doesNotMatch(readme, /omarchy-shell shell toggle emils\.localhost/)
})

test("firewall writes are explicit, scoped, and manageable", () => {
  assert.match(panel, /persistent UFW rule limited to/)
  assert.match(widget, /"pkexec", "\/usr\/bin\/ufw", "allow", "in", "on"/)
  assert.match(widget, /"--force", "delete", "allow", "in", "on"/)
  assert.match(widget, /onFirewallRemovalConfirmed/)
  assert.match(widget, /parseManagedUfwRules/)
  assert.match(detailRow, /text: "Remove"/)
  assert.match(panel, /onRemoveRequested: root\.requestFirewallRemoval\(modelData\)/)
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
  assert.match(service, /function refresh\(\) \{ scan\(true\); sampleResources\(true\)/)
  assert.match(service, /nativeDiscovery\.scan\(manual\)/)
  assert.match(service, /dockerDiscovery\.scan\(manual\)/)
  assert.match(discovery, /Date\.now\(\), bypassProbeCache/)
  assert.match(discovery, /onTriggered: if \(!root\.scanning\) root\.scan\(\)/)
})

test("local opening and separate local/LAN copying are wired explicitly", () => {
  assert.match(widget, /function openServer\(server\) \{\s*var url = RadarModel\.actionUrl\(server, false\)/)
  assert.match(widget, /onCopyRequested: function\(server\) \{ root\.copyServer\(server, false\)/)
  assert.match(widget, /onCopyLanRequested: function\(server\) \{ root\.copyServer\(server, true\)/)
  assert.match(widget, /panelActive: card\.open/)
  assert.doesNotMatch(widget, /effectiveUrl/)
})
