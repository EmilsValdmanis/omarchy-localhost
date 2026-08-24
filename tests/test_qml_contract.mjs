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
  assert.match(service, /exec docker \\\"\$@\\\"/)
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

test("the server panel supports keyboard search and safe destructive actions", () => {
  assert.match(widget, /KeyboardPanel\s*\{/)
  assert.match(panel, /property alias keyboardFocusTarget: keyCatcher/)
  assert.match(panel, /readonly property bool searchMode: searchField\.activeFocus/)
  assert.match(panel, /visible: !root\.showFirewallRules && !root\.showDiagnostics/)
  assert.match(panel, /function beginSearch\(\)[\s\S]*?searchField\.forceActiveFocus\(\)/)
  assert.match(panel, /function focusNavigation\(\)[\s\S]*?keyCatcher\.forceActiveFocus\(\)/)
  assert.match(panel, /else if \(searchMode\) \{\s*focusNavigation\(\)\s*\} else if \(query\) \{\s*clearSearch\(\)/)
  assert.match(panel, /onPressed: root\.beginSearch\(\)/)
  assert.match(panel, /Qt\.Key_Up/)
  assert.match(panel, /Qt\.Key_Down/)
  assert.match(panel, /Qt\.Key_Return/)
  assert.match(panel, /Qt\.Key_C/)
  assert.match(panel, /Qt\.Key_R/)
  assert.match(panel, /property int selectedActionIndex: 0/)
  assert.match(panel, /event\.key === Qt\.Key_Left \|\| event\.key === Qt\.Key_H\)[\s\S]*?selectAction\(-1\)/)
  assert.match(panel, /plainNavigation && event\.key === Qt\.Key_J/)
  assert.match(panel, /plainNavigation && event\.key === Qt\.Key_K/)
  assert.match(panel, /event\.key === Qt\.Key_Right \|\| event\.key === Qt\.Key_L\)[\s\S]*?selectAction\(1\)/)
  assert.match(panel, /plainNavigation && event\.key === Qt\.Key_Slash/)
  assert.doesNotMatch(panel, /plainNavigation = !searchMode && query === ""/)
  assert.doesNotMatch(panel, /alternate && event\.key === Qt\.Key_[HJKL]/)
  assert.match(panel, /hasCursor: row\.index === root\.selectedIndex && root\.selectedActionIndex === 6/)
  assert.match(panel, /ConfirmDialog\s*\{/)
  assert.match(panel, /requestStop\(server, force\)/)
})

test("background scans update the open panel without rebuilding unchanged rows", () => {
  assert.match(service, /if \(changed\) revision\+\+/)
  assert.match(service, /property var pendingDiagnostics: \[\]/)
  assert.match(service, /if \(!arraysEqual\(diagnostics, nextDiagnostics\)\)/)
  assert.doesNotMatch(panel, /filteredModel\.clear\(\)/)
  assert.doesNotMatch(panel, /enabled: !root\.scanning/)
})

test("server cards keep their borders and scroll promptly", () => {
  assert.match(panel, /readonly property real cardInset: Style\.space\(2\)/)
  assert.match(panel, /x: root\.cardInset/)
  assert.match(panel, /id: cardWrapper/)
  assert.match(panel, /width: parent\.width - root\.cardInset \* 2/)
  assert.match(panel, /borderSpec: Border\.flat\(/)
  assert.match(panel, /MouseArea\s*\{[\s\S]*?onWheel: function\(wheel\)/)
  assert.match(panel, /pixelDelta !== 0 \? -pixelDelta \* 1\.5 : -wheel\.angleDelta\.y \* 1\.25/)
  assert.match(panel, /serverList\.cancelFlick\(\)/)
  assert.match(panel, /wheel\.accepted = true/)
  assert.match(panel, /policy: serverList\.contentHeight > serverList\.height[\s\S]*?ScrollBar\.AlwaysOn[\s\S]*?ScrollBar\.AlwaysOff/)
  assert.match(panel, /width: Style\.space\(8\)[\s\S]*?implicitWidth: Style\.space\(3\)/)
  assert.match(panel, /serverScrollBar\.hovered \? 0\.64 : 0\.46/)
  assert.doesNotMatch(panel, /minimumSize: 0\.12/)
})

test("the server panel has a compact, composable global port filter", () => {
  assert.match(panel, /property string portFilter: "all"/)
  assert.match(panel, /value: "dev", label: "Dev ports"/)
  assert.match(panel, /value: "lan", label: "LAN ready"/)
  assert.match(panel, /value: "docker", label: "Docker"/)
  assert.match(panel, /RadarModel\.matchesServerFilter\(server, portFilter\)/)
  assert.match(panel, /onPortFilterChanged: rebuildFilteredModel\(\)/)
  assert.match(panel, /else if \(portFilter !== "all"\) \{\s*portFilter = "all"/)
  assert.match(panel, /Dropdown\s*\{[\s\S]*?value: root\.portFilter[\s\S]*?root\.portFilter = value/)
  assert.match(panel, /implicitHeight: rowContent\.implicitHeight \+ Style\.space\(12\)/)
  assert.match(panel, /Layout\.preferredWidth: Style\.space\(32\)/)
  assert.match(panel, /text: row\.framework\s*color: root\.dim/)
  assert.doesNotMatch(panel, /text: row\.framework \+ "  ·  :" \+ row\.port/)
  assert.doesNotMatch(panel, /text: row\.effectiveUrl[\s\S]*?font\.pixelSize: Style\.font\.bodySmall/)
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
