import QtQuick
import QtTest
import Quickshell
import qs.Commons
import "Plugin/qml" as PluginUi
import "Plugin/qml/RadarModel.js" as RadarModel

ShellRoot {
  FloatingWindow {
    id: window
    visible: true
    implicitWidth: 900
    implicitHeight: 800
    color: Color.popups.background

    TestCase {
      id: tests
      name: "Localhost"
      visible: true
      anchors.fill: parent
      when: window.visible
      property var panel
      property var servers
      property var list
      property int failuresBefore: 0
      property int executed: 0
      property int originalFontSize: 12

      Component { id: modelComponent; ListModel {} }
      Component { id: panelComponent; PluginUi.ServerPanel {
        width: 500; height: 560
        systemMemory: ({ totalBytes: 16 * 1073741824, availableBytes: 4 * 1073741824 })
      } }
      Component { id: qrComponent; PluginUi.QrCode {} }
      Component { id: qrContentComponent; PluginUi.QrContent { width: implicitWidth; height: implicitHeight } }
      Component { id: serviceComponent; PluginUi.RadarService { includeDocker: false } }
      Component { id: overlayComponent; PluginUi.QrService {} }
      Component { id: metricsComponent; TextMetrics {} }

      SignalSpy { id: openSpy; signalName: "openRequested" }
      SignalSpy { id: stopSpy; signalName: "stopRequested" }
      SignalSpy { id: projectStopSpy; signalName: "projectStopRequested" }
      SignalSpy { id: actionSpy; signalName: "actionFinished" }
      SignalSpy { id: copySpy; signalName: "copyRequested" }
      SignalSpy { id: copyLanSpy; signalName: "copyLanRequested" }

      function check(value, message) {
        if (!value) console.error("ASSERT", qtest_results.functionName, message || "verification failed")
        verify(value, message)
      }

      function equal(actual, expected, message) {
        if (actual !== expected) console.error("ASSERT", qtest_results.functionName, message || "comparison failed", actual, expected)
        compare(actual, expected, message)
      }

      function fixtures(count) {
        var rows = []
        var trends = [
          [7, 8, 10, 9, 11, 13, 12, 14],
          [14, 13, 12, 12, 10, 9, 8, 7],
          [9, 11, 8, 12, 10, 11, 9, 10]
        ]
        for (var i = 0; i < count; i++) rows.push(RadarModel.normalizeServer({
          serverId: "server-" + i, name: "Project " + i,
          framework: "Vite", frameworkId: "vite", port: 3000 + i,
          pid: 1000 + i, startTime: 100, cwd: "/tmp/project-" + i,
          projectRoot: "/tmp/fixtures",
          memoryBytes: (i + 1) * 10485760,
          memoryHistory: trends[i % trends.length].map(function(sample) {
            return sample * (i + 1) * 1048576
          }),
          localUrl: "http://localhost:" + (3000 + i),
          lanUrl: "http://192.168.1.2:" + (3000 + i), lanAvailable: i % 2 === 0
        }))
        return rows
      }

      function init() {
        originalFontSize = Style.fontBaseSize
        failuresBefore = qtest_results.failCount
        servers = createTemporaryObject(modelComponent, tests)
        RadarModel.syncServerModel(servers, fixtures(50))
        panel = createTemporaryObject(panelComponent, tests, { servers: servers, groupByProject: false })
        check(panel !== null)
        list = findChild(panel, "serverList")
        check(list !== null)
        openSpy.target = panel
        stopSpy.target = panel
        openSpy.clear()
        stopSpy.clear()
        projectStopSpy.target = panel
        projectStopSpy.clear()
        copySpy.target = panel
        copyLanSpy.target = panel
        copySpy.clear()
        copyLanSpy.clear()
        mouseMove(tests, 850, 750)
        tryCompare(list, "count", 50)
        waitForRendering(panel)
      }

      function cleanup() {
        Style.fontBaseSize = originalFontSize
        executed++
        console.log("LOCALHOST_CASE", qtest_results.functionName,
          qtest_results.failCount === failuresBefore ? "PASS" : "FAIL")
        openSpy.target = null
        stopSpy.target = null
        projectStopSpy.target = null
        actionSpy.target = null
        actionSpy.clear()
        copySpy.target = null
        copyLanSpy.target = null
      }

      function settled() {
        wait(100)
        tryVerify(function() { return !list.moving })
      }

      function verifyViewport() {
        check(list.height > 0, "list has a viewport")
        check(list.contentY >= list.originY - 1, "scroll did not pass the top")
        check(list.contentY <= list.originY + Math.max(0, list.contentHeight - list.height) + 1,
          "scroll did not pass the bottom")
        check([0.25, 0.5, 0.75].some(function(ratio) {
          return list.indexAt(10, list.contentY + Math.min(list.height, list.contentHeight) * ratio) >= 0
        }),
          "viewport still contains a server")
        var bottom = list.mapToItem(panel, 0, list.height).y
        check(bottom <= panel.height, "list fits inside the popup")
      }

      function test_scrollbar_can_be_dragged_in_both_directions() {
        var scrollbar = findChild(panel, "serverScrollBar")
        check(scrollbar.visible && scrollbar.interactive)
        check(scrollbar.mapToItem(panel, scrollbar.width, 0).x <= panel.width,
          "the entire drag target stays inside the panel")
        var firstRow = list.itemAtIndex(0)
        check(scrollbar.mapToItem(panel, 0, 0).x > firstRow.mapToItem(panel, firstRow.width, 0).x,
          "the scrollbar track never overlaps a row")
        fuzzyCompare(findChild(panel, "memoryOverview").width, panel.width, 0.5,
          "the header uses the full panel width without a global scrollbar gutter")
        fuzzyCompare(scrollbar.mapToItem(panel, 0, 0).x - firstRow.mapToItem(panel, firstRow.width, 0).x,
          Style.space(2), 0.5, "the list keeps a compact gap beside the scrollbar")
        var selected = panel.selectedServer().serverId
        var initial = list.contentY
        var x = scrollbar.width - Style.space(1.5)
        var thumbCenter = scrollbar.height * (scrollbar.visualPosition + scrollbar.visualSize / 2)
        mousePress(scrollbar, x, thumbCenter)
        tryCompare(scrollbar, "pressed", true)
        mouseMove(scrollbar, x, scrollbar.height * 0.75, 100)
        mouseRelease(scrollbar, x, scrollbar.height * 0.75)
        settled()
        check(list.contentY > initial + list.height, "dragging the thumb scrolls down")
        equal(panel.selectedServer().serverId, selected, "dragging does not change the server selection")
        thumbCenter = scrollbar.height * (scrollbar.visualPosition + scrollbar.visualSize / 2)
        mousePress(scrollbar, x, thumbCenter)
        tryCompare(scrollbar, "pressed", true)
        mouseMove(scrollbar, x, 0, 100)
        mouseRelease(scrollbar, x, 0)
        settled()
        check(list.atYBeginning, "dragging back up reaches the first row")
        verifyViewport()
        RadarModel.syncServerModel(servers, fixtures(1))
        panel.revision++
        tryCompare(list, "count", 1)
        tryCompare(scrollbar, "visible", false, 2000, "no scrollbar is shown when the rows fit")
        fuzzyCompare(list.width, panel.width, 0.5, "no scrollbar padding is reserved when rows fit")
      }

      function test_toolbar_actions_use_consistent_buttons() {
        panel.selectedIndex = 0
        panel.selectedActionIndex = RadarModel.ACTIONS.terminal
        mouseMove(tests, 850, 750)
        settled()
        var open = findChild(panel, "serverAction0")
        var copy = findChild(panel, "serverAction1")
        equal(open.borderTop, 0, "Open has no idle outline")
        equal(copy.borderTop, 0, "Copy has no idle outline")
        for (var index = 4; index < 9; index++) {
          var action = findChild(panel, "serverAction" + index)
          fuzzyCompare(action.height, open.height, 0.5, "both toolbar sides share the same height")
          fuzzyCompare(action.iconSize, open.iconSize, 0.5, "both toolbar sides share the same icon size")
          fuzzyCompare(action.width, action.height, 0.5, "icon actions have square hit targets")
        }
      }

      function test_native_wheel_and_bounds_after_removals() {
        var before = list.contentY
        mouseWheel(list, list.width / 2, list.height / 2, 0, -120)
        settled()
        check(list.contentY > before, "native wheel input scrolls")
        list.positionViewAtIndex(35, ListView.Beginning)
        settled()
        servers.remove(0, 30)
        panel.revision++
        tryCompare(list, "count", 20)
        settled()
        check(Math.abs(list.originY) > 1, "exercise the nonzero origin regression")
        list.positionViewAtEnd()
        mouseWheel(list, 20, 20, 0, -1200)
        settled()
        verifyViewport()
        check(list.atYEnd)
        list.positionViewAtBeginning()
        mouseWheel(list, 20, 20, 0, 1200)
        settled()
        verifyViewport()
        check(list.atYBeginning)
      }

      function test_background_scan_preserves_manual_scroll_and_selection() {
        panel.selectedIndex = 1
        list.positionViewAtIndex(35, ListView.Beginning)
        settled()
        var before = list.contentY
        servers.setProperty(40, "name", "Renamed project")
        panel.revision++
        settled()
        equal(panel.selectedServer().serverId, "server-1")
        fuzzyCompare(list.contentY, before, 1)
        verifyViewport()
      }

      function test_shrink_filter_empty_and_repopulate() {
        list.positionViewAtEnd()
        panel.query = "Project 49"
        tryCompare(list, "count", 1)
        settled()
        equal(panel.selectedServer().serverId, "server-49")
        verifyViewport()
        panel.query = "no matches"
        tryCompare(list, "count", 0)
        equal(panel.selectedServer(), null)
        panel.query = ""
        tryCompare(list, "count", 50)
        settled()
        verifyViewport()
        RadarModel.syncServerModel(servers, fixtures(2))
        panel.revision++
        tryCompare(list, "count", 2)
        settled()
        verifyViewport()
      }

      function test_small_popup_and_auxiliary_pages() {
        panel.height = 320
        settled()
        list.positionViewAtEnd()
        settled()
        verifyViewport()
        var capturePath = Quickshell.env("LOCALHOST_TEST_ARTIFACTS")
        if (capturePath) grabImage(panel).save(capturePath + "/compact-panel.png")
        var rules = []
        for (var i = 0; i < 40; i++) rules.push({ port: 3000 + i, subnet: "192.168.1.0/24", interfaceName: "wlan0" })
        panel.firewallRules = rules
        panel.showFirewallRules = true
        wait(100)
        var firewall = findChild(panel, "firewallList")
        check(firewall.interactive)
        check(firewall.mapToItem(panel, 0, firewall.height).y <= panel.height)
        var initial = firewall.contentY
        mouseWheel(firewall, 100, 50, 0, -120)
        wait(300)
        check(firewall.contentY > initial)
        panel.showFirewallRules = false
        panel.diagnostics = rules.map(function(rule) { return { port: rule.port, process: "node", reason: "no HTTP response" } })
        panel.showDiagnostics = true
        wait(100)
        var diagnostics = findChild(panel, "diagnosticList")
        check(diagnostics.interactive)
        check(diagnostics.mapToItem(panel, 0, diagnostics.height).y <= panel.height)
      }

      function test_auxiliary_lists_show_every_entry_and_share_scroll_layout() {
        panel.height = 320
        var rules = []
        for (var i = 0; i < 40; i++) rules.push({ port: 3000 + i, subnet: "192.168.1.0/24", interfaceName: "wlan0" })
        panel.firewallRules = rules
        panel.diagnostics = rules.map(function(rule) {
          return { port: rule.port, process: "node", reason: "no HTTP or HTTPS response" }
        })
        var removals = []
        panel.firewallRemovalConfirmed.connect(function(rule) { removals.push(rule.port) })
        for (var page = 0; page < 2; page++) {
          panel.showFirewallRules = page === 0
          panel.showDiagnostics = page === 1
          var area = findChild(panel, page === 0 ? "firewallList" : "diagnosticList")
          tryCompare(area, "count", page === 0 ? 40 : 42)
          wait(100)
          var scrollbar = findChild(area, "auxiliaryScrollBar")
          check(scrollbar.visible && scrollbar.interactive)
          var initial = area.contentY
          var thumbCenter = scrollbar.height * (scrollbar.visualPosition + scrollbar.visualSize / 2)
          mousePress(scrollbar, scrollbar.width / 2, thumbCenter)
          tryCompare(scrollbar, "pressed", true)
          mouseMove(scrollbar, scrollbar.width / 2, scrollbar.height * 0.8, 100)
          mouseRelease(scrollbar, scrollbar.width / 2, scrollbar.height * 0.8)
          check(area.contentY > initial, "both auxiliary scrollbars support dragging")
          var lastIndex = page === 0 ? 39 : 41
          area.positionViewAtIndex(lastIndex, ListView.End)
          tryVerify(function() { return area.itemAtIndex(lastIndex) !== null })
          var entry = area.itemAtIndex(lastIndex)
          var row = page === 0 ? entry : entry.item
          fuzzyCompare(row.width, area.viewportWidth, 0.5)
          check(scrollbar.mapToItem(panel, 0, 0).x > row.mapToItem(panel, row.width, 0).x)
          fuzzyCompare(scrollbar.mapToItem(panel, 0, 0).x - row.mapToItem(panel, row.width, 0).x,
            Style.space(2), 0.5, "auxiliary lists use the same scrollbar gap")
          check(scrollbar.mapToItem(panel, scrollbar.width, 0).x <= panel.width)
          if (page === 0) {
            equal(row.title, ":3039")
            var remove = findChild(row, "removeRule")
            check(remove.iconText !== "")
            panel.firewallBusy = true
            equal(remove.enabled, false)
            panel.firewallBusy = false
            mouseClick(remove, remove.width / 2, remove.height / 2)
            equal(panel.pendingAction, "remove-firewall")
            equal(panel.pendingFirewallRule.port, 3039)
            equal(removals.length, 0, "Remove still asks for confirmation")
            panel.confirmPendingAction()
            equal(removals.length, 1)
            equal(removals[0], 3039)
          } else {
            equal(row.title, ":3039", "listeners beyond the old eight-row limit are reachable")
            equal(row.trailingText, "node")
            equal(row.detail, "No response to the HTTP / HTTPS check")
          }
        }
        panel.diagnostics = []
        tryCompare(findChild(panel, "diagnosticList"), "count", 0)
        panel.firewallRules = []
        panel.showDiagnostics = false
        panel.showFirewallRules = true
        tryCompare(findChild(panel, "firewallList"), "count", 0)
      }

      function test_keyboard_navigation_actions_and_confirmation() {
        panel.focusNavigation()
        wait(50)
        for (var repeat = 0; repeat < 4; repeat++) {
          keyClick(Qt.Key_K)
          keyClick(Qt.Key_Up)
          keyClick(Qt.Key_P, Qt.ControlModifier)
        }
        equal(panel.selectedIndex, 0, "upward navigation stops at the first row")
        keyClick(Qt.Key_G, Qt.ShiftModifier)
        settled()
        equal(panel.selectedIndex, 49)
        check(list.atYEnd)
        for (repeat = 0; repeat < 4; repeat++) {
          keyClick(Qt.Key_J)
          keyClick(Qt.Key_Down)
          keyClick(Qt.Key_N, Qt.ControlModifier)
        }
        equal(panel.selectedIndex, 49, "downward navigation stops at the last row")
        keyClick(Qt.Key_G)
        keyClick(Qt.Key_G)
        settled()
        equal(panel.selectedIndex, 0)
        check(list.atYBeginning)
        keyClick(Qt.Key_Return)
        equal(openSpy.count, 1)
        keyClick(Qt.Key_Delete)
        equal(stopSpy.count, 0)
        equal(panel.pendingAction, "stop")
        keyClick(Qt.Key_Escape)
        equal(panel.pendingAction, "")
        equal(stopSpy.count, 0)
        panel.requestStop(panel.selectedServer(), false)
        panel.confirmPendingAction()
        equal(stopSpy.count, 1)
        panel.selectedIndex = 1
        panel.selectedActionIndex = 1
        panel.selectAction(1)
        equal(panel.selectedActionIndex, RadarModel.ACTIONS.qr, "disabled QR remains reachable for its explanation")
        check(!panel.actionEnabled(RadarModel.ACTIONS.terminal, { cwd: "" }))
        check(!panel.actionEnabled(RadarModel.ACTIONS.project, { cwd: "" }))
      }

      function test_mouse_selection_stays_on_target_when_moving_to_toolbar() {
        RadarModel.syncServerModel(servers, fixtures(5))
        panel.revision++
        tryCompare(list, "count", 5)
        settled()

        var selectedRow = list.itemAtIndex(1)
        check(selectedRow !== null)
        mouseClick(selectedRow, selectedRow.width / 2, selectedRow.height / 2)
        equal(panel.selectedServer().serverId, "server-1")
        equal(openSpy.count, 0, "a single click selects without opening")
        for (var i = 2; i < 5; i++) {
          var crossedRow = list.itemAtIndex(i)
          check(crossedRow !== null)
          mouseMove(crossedRow, crossedRow.width / 2, crossedRow.height / 2)
          equal(panel.selectedServer().serverId, "server-1", "crossing rows must keep the chosen server")
          check(selectedRow.selected, "the chosen row stays highlighted")
          check(!crossedRow.selected, "hover does not select another row")
        }

        var stop = findChild(panel, "serverAction7")
        mouseMove(stop, stop.width / 2, stop.height / 2)
        mouseClick(stop, stop.width / 2, stop.height / 2)
        equal(panel.pendingAction, "stop")
        equal(panel.pendingServer.serverId, "server-1", "Stop still targets the clicked server")
        equal(stopSpy.count, 0, "stopping still requires confirmation")
        keyClick(Qt.Key_Escape)
        equal(panel.pendingAction, "")

        var hoveredRow = list.itemAtIndex(4)
        mouseMove(hoveredRow, hoveredRow.width / 2, hoveredRow.height / 2)
        keyClick(Qt.Key_Down)
        equal(panel.selectedServer().serverId, "server-2", "keyboard navigation continues from the clicked row")
        mouseMove(hoveredRow, hoveredRow.width / 2 + 10, hoveredRow.height / 2)
        equal(panel.selectedServer().serverId, "server-2", "mouse movement preserves keyboard selection")
      }

      function test_mouse_port_opens_clicked_server() {
        var row = list.itemAtIndex(1)
        check(row !== null)
        var port = findChild(row, "openPort")
        check(port !== null)
        mouseClick(port, port.width / 2, port.height / 2)
        equal(openSpy.count, 1)
        equal(openSpy.signalArguments[0][0].serverId, "server-1")
        equal(panel.selectedServer().serverId, "server-1")
      }

      function test_single_copy_action_uses_local_url() {
        panel.selectedIndex = 0
        var copy = findChild(panel, "serverAction1")
        equal(copy.text, "Copy")
        check(copy.iconText !== "")
        equal(findChild(copy.parent, "copyMenuTrigger"), null)
        mouseClick(copy, copy.width / 2, copy.height / 2)
        equal(copySpy.count, 1)
        equal(copySpy.signalArguments[0][0].localUrl, "http://localhost:3000")
        equal(copyLanSpy.count, 0)
        panel.focusNavigation()
        keyClick(Qt.Key_C, Qt.ControlModifier)
        equal(copySpy.count, 2)
        panel.selectedIndex = 1
        mouseClick(copy, copy.width / 2, copy.height / 2)
        equal(copySpy.count, 3, "local copying is independent of LAN availability")
        equal(copySpy.signalArguments[2][0].localUrl, "http://localhost:3001")
        equal(copyLanSpy.count, 0)
      }

      function test_include_and_direct_skip_with_keyboard_and_mouse() {
        var included = []
        var skipped = []
        panel.includePortRequested.connect(function(port) { included.push(port) })
        panel.skipPortRequested.connect(function(port) { skipped.push(port) })
        panel.diagnostics = [{ port: 4206, process: "bun", reason: "ignored by settings" }]
        panel.showDiagnostics = true
        var area = findChild(panel, "diagnosticList")
        tryCompare(area, "count", 3)
        settled()
        var button = findChild(area.itemAtIndex(1), "includePort")
        check(button.enabled)
        equal(button.text, "Unskip")
        mouseClick(button, button.width / 2, button.height / 2)
        equal(included.length, 1)
        equal(included[0], 4206)
        panel.includedPorts = ({4206: true})
        panel.diagnostics = [{ port: 4206, process: "bun", reason: "no HTTP or HTTPS response" }]
        settled()
        button = findChild(area.itemAtIndex(2), "includePort")
        equal(button.text, "Included")
        equal(button.enabled, false)
        panel.showDiagnostics = false
        panel.selectedIndex = 0
        panel.selectedActionIndex = RadarModel.ACTIONS.restart
        panel.focusNavigation()
        wait(50)
        keyClick(Qt.Key_Right)
        equal(panel.selectedActionIndex, RadarModel.ACTIONS.skip)
        keyClick(Qt.Key_Return)
        equal(skipped.length, 1)
        equal(skipped[0], 3000)
        equal(stopSpy.count, 0, "skipping never stops the process")
        panel.selectedIndex = 1
        var skip = findChild(panel, "serverAction8")
        equal(skip.text, "")
        var stop = findChild(panel, "serverAction7")
        check(skip.mapToItem(panel, skip.width, 0).x <= stop.mapToItem(panel, 0, 0).x,
          "Skip is immediately before Stop")
        mouseClick(skip, skip.width / 2, skip.height / 2)
        equal(skipped.length, 2)
        equal(skipped[1], 3001, "mouse click skips the currently selected port directly")
        equal(stopSpy.count, 0)
      }

      function test_skipped_controls_fit_content_without_scrollbar_feedback() {
        panel.height = Qt.binding(function() { return panel.implicitHeight })
        panel.showDiagnostics = true
        panel.diagnostics = [4206, 36811, 8000, 8080].map(function(port) {
          return { port: port, process: "process-with-a-long-name", reason: "no HTTP or HTTPS response" }
        })
        panel.includedPorts = ({8080:true})
        var area = findChild(panel, "diagnosticList")
        var bar = findChild(area, "auxiliaryScrollBar")
        tryCompare(area, "count", 6)
        settled()
        tryCompare(bar, "visible", false)
        fuzzyCompare(area.viewportWidth, panel.width, 0.5)
        panel.height = 230
        tryCompare(bar, "visible", true)
        panel.height = Qt.binding(function() { return panel.implicitHeight })
        tryCompare(bar, "visible", false)
      }

      function test_skipped_sections_default_folds_and_keyboard() {
        var entries = [
          { port: 4206, process: "bun", reason: "TanStack Devtools event bus" },
          { port: 8000, process: "api", reason: "ignored by settings" },
          { port: 5432, process: "postgres", reason: "non-HTTP service port" }
        ]
        panel.diagnostics = entries
        panel.showDiagnostics = true
        var area = findChild(panel, "diagnosticList")
        tryCompare(area, "count", 3)
        settled()
        var manual = area.itemAtIndex(0).item
        var automatic = area.itemAtIndex(2).item
        equal(manual.name, "Manual")
        equal(manual.count, 1)
        equal(manual.collapsed, false)
        equal(automatic.name, "Automatic")
        equal(automatic.count, 2)
        equal(automatic.collapsed, true)
        check(!findChild(manual, "projectStopAll").visible, "section headers do not expose project stop actions")
        equal(area.itemAtIndex(1).item.title, ":8000")
        var chevron = findChild(automatic, "projectChevron")
        equal(chevron.rotation, 0)
        mouseClick(automatic, automatic.width / 2, automatic.height / 2)
        tryCompare(area, "count", 5)
        equal(area.itemAtIndex(2).item, automatic, "folding preserves the header instance for its animation")
        check(automatic.selected && automatic.hasCursor, "clicking highlights the header like a project")
        if (!Style.reduceMotion)
          tryVerify(function() { return chevron.rotation > 0 && chevron.rotation < 90 }, 120, "the shared chevron animates")
        tryCompare(chevron, "rotation", 90)
        panel.diagnostics = entries.map(function(entry) { return Object.assign({}, entry) })
        settled()
        equal(area.count, 5, "polling does not reset an explicitly opened section")
        equal(area.itemAtIndex(2).item, automatic, "polling preserves the selected header")
        automatic = area.itemAtIndex(2).item
        automatic.forceActiveFocus()
        keyClick(Qt.Key_Left)
        tryCompare(area, "count", 3)
        tryVerify(function() { return area.itemAtIndex(2).item.activeFocus })
        keyClick(Qt.Key_Right)
        tryCompare(area, "count", 5)
        manual = area.itemAtIndex(0).item
        mouseClick(manual, manual.width / 2, manual.height / 2)
        tryCompare(area, "count", 4)
        equal(area.itemAtIndex(0).item, manual)
        check(manual.selected && manual.hasCursor)
        check(!automatic.selected, "only the most recently selected header is highlighted")
        panel.diagnostics = entries.filter(function(entry) { return entry.reason !== "ignored by settings" })
        settled()
        equal(area.itemAtIndex(1).item.collapsed, false, "removing the last manual skip opens Automatic")
        panel.diagnostics = entries
        settled()
        equal(area.itemAtIndex(1).item.collapsed, true, "a new manual section closes Automatic by default")
        panel.diagnostics = []
        tryCompare(area, "count", 0)
      }

      function test_skipped_process_names_and_actions_align() {
        panel.showDiagnostics = true
        panel.diagnostics = [
          { port: 3773, process: "t3code", reason: "command and port are not recognized as a development server" },
          { port: 4206, process: "bun", reason: "TanStack Devtools event bus" },
          { port: 5432, process: "a-very-long-application-name-that-must-not-push-the-action", reason: "ignored by settings" },
          { port: 36811, process: "node-MainThread", reason: "no HTTP or HTTPS response" }
        ]
        panel.includedPorts = ({36811:true})
        var area = findChild(panel, "diagnosticList")
        tryCompare(area, "count", 3)
        panel.toggleSkippedGroup("automatic")
        tryCompare(area, "count", 6)
        for (var size of [12, 18]) {
          Style.fontBaseSize = size
          panel.width = panel.implicitWidth
          panel.height = 650
          settled()
          var processX = -1
          var actionX = -1
          var actionWidth = -1
          for (var i = 0; i < 4; i++) {
            var row = area.itemAtIndex([3, 4, 1, 5][i]).item
            check(row !== null)
            var title = findChild(row, "detailTitle")
            var process = findChild(row, "detailProcess")
            var action = findChild(row, "includePort")
            var currentProcessX = process.mapToItem(row, 0, 0).x
            var currentActionX = action.mapToItem(row, 0, 0).x
            if (i === 0) { processX = currentProcessX; actionX = currentActionX; actionWidth = action.width }
            fuzzyCompare(currentProcessX, processX, 0.5, "app names share a left edge beside four- and five-digit ports")
            fuzzyCompare(currentActionX, actionX, 0.5, "all actions share a column")
            fuzzyCompare(action.width, actionWidth, 0.5)
            check(action.width >= action.implicitWidth, "the action label fits inside its button")
            check(action.mapToItem(row, action.width, 0).x <= row.width, "the complete action stays inside the row")
            fuzzyCompare(title.mapToItem(row, 0, title.baselineOffset).y,
              process.mapToItem(row, 0, process.baselineOffset).y, 0.5)
            check(process.mapToItem(row, process.width, 0).x < currentActionX)
            if (i === 2) { check(process.truncated); equal(action.text, "Unskip") }
            else equal(action.text, i === 3 ? "Included" : "Include")
          }
          var path = Quickshell.env("LOCALHOST_TEST_ARTIFACTS")
          if (path) grabImage(panel).save(path + "/skipped-alignment-" + size + ".png")
        }
      }

      function test_keyboard_can_inspect_disabled_actions_without_running_them() {
        var qrRequests = 0
        var terminals = 0
        var editors = 0
        var restarts = 0
        panel.qrRequested.connect(function() { qrRequests++ })
        panel.terminalRequested.connect(function() { terminals++ })
        panel.projectRequested.connect(function() { editors++ })
        panel.restartRequested.connect(function() { restarts++ })
        servers.setProperty(1, "cwd", "")
        servers.setProperty(1, "hint", "Server listens on localhost only.")
        servers.setProperty(1, "restartReason", "No restart command is configured.")
        panel.revision++
        panel.selectedIndex = 1
        panel.selectedActionIndex = RadarModel.ACTIONS.open
        panel.focusNavigation()
        wait(50)
        keyClick(Qt.Key_L)
        equal(panel.selectedActionIndex, RadarModel.ACTIONS.copyLocal)
        keyClick(Qt.Key_Right)
        equal(panel.selectedActionIndex, RadarModel.ACTIONS.qr)
        var qr = findChild(panel, "serverAction3")
        var qrTip = findChild(qr.parent, "disabledActionTip3")
        equal(qr.enabled, false)
        equal(qr.hasCursor, true)
        tryCompare(qrTip, "visible", true)
        check(qrTip.text.indexOf("localhost only") !== -1)
        keyClick(Qt.Key_Return)
        equal(qrRequests, 0)
        keyClick(Qt.Key_L)
        equal(panel.selectedActionIndex, RadarModel.ACTIONS.terminal)
        tryCompare(qrTip, "visible", false)
        var terminal = findChild(panel, "serverAction4")
        var terminalTip = findChild(terminal.parent, "disabledActionTip4")
        tryCompare(terminalTip, "visible", true)
        check(terminalTip.text.indexOf("directory") !== -1)
        keyClick(Qt.Key_Return)
        equal(terminals, 0)
        keyClick(Qt.Key_Right)
        equal(panel.selectedActionIndex, RadarModel.ACTIONS.project)
        keyClick(Qt.Key_Return)
        equal(editors, 0)
        keyClick(Qt.Key_Right)
        equal(panel.selectedActionIndex, RadarModel.ACTIONS.restart)
        var restart = findChild(panel, "serverAction6")
        var restartTip = findChild(restart.parent, "disabledActionTip6")
        tryCompare(restartTip, "visible", true)
        equal(restartTip.text, "No restart command is configured.")
        keyClick(Qt.Key_Return)
        equal(restarts, 0)
        panel.actionBusy = true
        keyClick(Qt.Key_Right)
        equal(panel.selectedActionIndex, RadarModel.ACTIONS.skip)
        keyClick(Qt.Key_Right)
        equal(panel.selectedActionIndex, RadarModel.ACTIONS.stop)
        var stop = findChild(panel, "serverAction7")
        var stopTip = findChild(stop.parent, "disabledActionTip7")
        tryCompare(stopTip, "visible", true)
        check(stopTip.text.indexOf("in progress") !== -1)
        keyClick(Qt.Key_Return)
        equal(stopSpy.count, 0)
        equal(panel.pendingAction, "")
        keyClick(Qt.Key_H)
        equal(panel.selectedActionIndex, RadarModel.ACTIONS.skip)
        keyClick(Qt.Key_H)
        equal(panel.selectedActionIndex, RadarModel.ACTIONS.restart)
        keyClick(Qt.Key_Left)
        equal(panel.selectedActionIndex, RadarModel.ACTIONS.project)
      }

      function test_qr_sharing_content_copies_lan_and_closes_by_keyboard() {
        var qr = createTemporaryObject(overlayComponent, tests)
        qr.open(JSON.stringify({ name: "My web app", framework: "React", url: "http://192.168.1.2:3000" }))
        tryVerify(function() { return qr.showingQr }, 5000)
        var view = createTemporaryObject(qrContentComponent, tests, { qrState: qr })
        check(view !== null)
        var copies = []
        var closes = 0
        var retries = 0
        view.copyRequested.connect(function() { copies.push(view.url) })
        view.closeRequested.connect(function() { closes++ })
        view.retryRequested.connect(function() { retries++ })
        equal(findChild(view, "qrProjectName").text, "My web app")
        equal(findChild(view, "qrLanUrl").text, "http://192.168.1.2:3000")
        var code = findChild(view, "sharingQrCode")
        check(code.width <= view.width - Style.space(24))
        equal(code.width, code.rows.length * code.moduleSize, "QR modules remain integer-sized")
        panel.visible = false
        waitForRendering(view)
        wait(150)
        var capturePath = Quickshell.env("LOCALHOST_TEST_ARTIFACTS")
        if (capturePath) grabImage(view).save(capturePath + "/qr-sharing.png")
        var initialHeight = view.height
        var copy = findChild(view, "copyQrLan")
        mouseClick(copy, copy.width / 2, copy.height / 2)
        equal(copies.length, 1)
        equal(copies[0], "http://192.168.1.2:3000")
        equal(view.copied, true)
        equal(findChild(view, "qrStatus"), null)
        fuzzyCompare(view.height, initialHeight, 0.5)
        view.forceActiveFocus()
        keyClick(Qt.Key_C, Qt.ControlModifier)
        equal(copies.length, 2)
        equal(findChild(view, "closeQr"), null)
        view.forceActiveFocus()
        keyClick(Qt.Key_Escape)
        equal(closes, 1)
        qr.error = "Could not generate the QR code"
        var retry = findChild(view, "retryQr")
        tryCompare(retry, "visible", true)
        mouseClick(retry, retry.width / 2, retry.height / 2)
        equal(retries, 1)
        qr.close()
      }

      function test_disabled_qr_explains_why_and_never_shares() {
        var requests = []
        panel.qrRequested.connect(function(server) { requests.push(server.serverId) })
        servers.setProperty(1, "hint", "Server listens on localhost only. Bind it to 0.0.0.0 or a LAN address to share.")
        panel.revision++
        panel.selectedIndex = 1
        var qr = findChild(panel, "serverAction3")
        var tip = findChild(qr.parent, "disabledActionTip3")
        tryCompare(qr, "enabled", false)
        check(qr.opacity < 1, "unavailable QR is visibly disabled")
        mouseMove(qr.parent, qr.width / 2, qr.height / 2)
        tryCompare(tip, "visible", true, 2000)
        check(tip.text.indexOf("localhost only") !== -1)
        equal(qr.tooltipText, "", "the built-in tooltip must not duplicate the compact tooltip")
        equal(panel.selectedActionIndex, RadarModel.ACTIONS.open, "disabled hover does not move the action cursor")
        mouseClick(qr.parent, qr.width / 2, qr.height / 2)
        equal(requests.length, 0)

        panel.selectedIndex = 0
        tryCompare(qr, "enabled", true)
        tryCompare(tip, "visible", false)
        equal(tip.text, "", "available QR needs no redundant tooltip")
        equal(qr.tooltipText, "")
        equal(qr.opacity, 1)
        mouseClick(qr, qr.width / 2, qr.height / 2)
        equal(requests.length, 1)
        equal(requests[0], "server-0")
      }

      function test_port_filter_toggle_outside_click_and_keyboard() {
        var filter = findChild(panel, "portFilter")
        var trigger = findChild(filter, "portFilterTrigger")
        var popup = findChild(trigger, "portFilterPopup")
        mouseClick(trigger, trigger.width / 2, trigger.height / 2)
        tryCompare(filter, "popupOpen", true)
        mouseClick(trigger, trigger.width / 2, trigger.height / 2)
        tryCompare(filter, "popupOpen", false)
        wait(100)
        equal(filter.popupOpen, false, "the closing click must not reopen the filter")

        mouseClick(trigger, trigger.width / 2, trigger.height / 2)
        tryCompare(filter, "popupOpen", true)
        var lan = findChild(popup.contentItem, "portFilterOption2")
        check(lan.iconText !== "")
        mouseClick(lan, lan.width / 2, lan.height / 2)
        tryCompare(panel, "portFilter", "lan")
        tryCompare(filter, "popupOpen", false)
        tryCompare(list, "count", 25)

        trigger.forceActiveFocus()
        keyClick(Qt.Key_Return)
        tryCompare(filter, "popupOpen", true)
        keyClick(Qt.Key_Up)
        keyClick(Qt.Key_Up)
        keyClick(Qt.Key_Return)
        tryCompare(panel, "portFilter", "all")
        tryCompare(filter, "popupOpen", false)
        equal(panel.searchMode, false)
        mouseClick(trigger, trigger.width / 2, trigger.height / 2)
        tryCompare(filter, "popupOpen", true)
        keyClick(Qt.Key_Escape)
        tryCompare(filter, "popupOpen", false)
        mouseClick(trigger, trigger.width / 2, trigger.height / 2)
        tryCompare(filter, "popupOpen", true)
        mouseClick(tests, 850, 750)
        tryCompare(filter, "popupOpen", false)
      }

      function test_notices_do_not_move_footer_or_resize_popup() {
        var status = findChild(panel, "footerStatus")
        var action = findChild(panel, "serverAction0")
        var hints = status.text
        var messages = ["Copied http://localhost:3000", "Unable to open server.\n" + "A long explanation ".repeat(20), ""]
        for (var mode = 0; mode < 2; mode++) {
          if (mode === 1) panel.height = Qt.binding(function() { return panel.implicitHeight })
          settled()
          var actionY = action.mapToItem(panel, 0, 0).y
          var panelHeight = panel.height
          var preferredHeight = panel.implicitHeight
          var listHeight = list.height
          for (var i = 0; i < messages.length; i++) {
            panel.notice = messages[i]
            panel.noticeUrgent = i === 1
            wait(50)
            fuzzyCompare(action.mapToItem(panel, 0, 0).y, actionY, 0.5)
            fuzzyCompare(panel.height, panelHeight, 0.5)
            fuzzyCompare(panel.implicitHeight, preferredHeight, 0.5)
            fuzzyCompare(list.height, listHeight, 0.5)
            check(status.text.indexOf("\n") === -1)
            if (i === 1) check(status.truncated, "long errors remain on one line")
          }
          equal(status.text, hints, "clearing a notice restores the shortcut hint")
        }
      }

      function test_header_views_are_separate_from_actions() {
        var refreshes = 0
        panel.refreshRequested.connect(function() { refreshes++ })
        var discovery = findChild(panel, "headerView1")
        var access = findChild(panel, "headerView2")
        var serversTab = findChild(panel, "headerView0")
        mouseClick(discovery, discovery.width / 2, discovery.height / 2)
        equal(panel.showDiagnostics, true)
        equal(panel.showFirewallRules, false)
        mouseClick(discovery, discovery.width / 2, discovery.height / 2)
        equal(panel.showDiagnostics, true, "clicking the active tab does not toggle views")
        var refresh = findChild(panel, "refreshServers")
        fuzzyCompare(refresh.height, discovery.height, 0.5, "refresh has the same height as the view buttons")
        equal(refresh.text, "")
        fuzzyCompare(refresh.width, refresh.height, 0.5, "refresh keeps the same-sized square target without a label")
        mouseClick(refresh, refresh.width / 2, refresh.height / 2)
        equal(refreshes, 1)
        equal(panel.showDiagnostics, true)
        mouseClick(access, access.width / 2, access.height / 2)
        equal(panel.showFirewallRules, true)
        equal(panel.showDiagnostics, false)
        mouseClick(serversTab, serversTab.width / 2, serversTab.height / 2)
        equal(panel.showFirewallRules, false)
        var group = findChild(panel, "groupToggle")
        mouseClick(group, group.width / 2, group.height / 2)
        equal(panel.groupByProject, true)
        equal(panel.showDiagnostics, false)
        equal(panel.showFirewallRules, false)
      }

      function test_always_visible_memory_preserves_server_colors() {
        var overview = findChild(panel, "memoryOverview")
        var originalHeight = overview.height
        var memoryBar = findChild(panel, "memoryBar")
        check(memoryBar.visible)
        check(findChild(panel, "trackedMemory").visible)
        check(findChild(panel, "totalMemory").visible)
        var color = String(panel.colorForServer(servers.get(0)))
        mouseClick(overview, overview.width / 2, overview.height / 2)
        check(memoryBar.visible, "clicking RAM does not hide the breakdown")
        var row = fixtures(1)[0]
        row.serverId = "inserted"
        row.pid = 9999
        servers.insert(0, row)
        panel.revision++
        equal(String(panel.colorForServer(servers.get(1))), color)
        equal(String(panel.colorForSource(RadarModel.memorySourceKey(servers.get(1)))), color)
        panel.focusNavigation()
        keyClick(Qt.Key_M, Qt.ControlModifier)
        wait(100)
        check(memoryBar.visible, "Ctrl+M does not hide the breakdown")
        equal(overview.height, originalHeight)
        verifyViewport()
      }

      function test_memory_hover_highlights_segment_without_changing_selection() {
        RadarModel.syncServerModel(servers, fixtures(2))
        panel.systemMemory = { totalBytes: 100 * 1048576, availableBytes: 40 * 1048576 }
        panel.revision++
        tryCompare(list, "count", 2)
        var bar = findChild(panel, "memoryBar")
        var selected = panel.selectedServer().serverId
        mouseMove(tests, 850, 750)
        tryCompare(bar, "hoveredSegment", -1)
        waitForRendering(bar)
        wait(50)
        // Capture the panel so the software renderer includes the child Canvas.
        var normal = grabImage(panel)
        var firstX = Math.floor(bar.width * 0.05)
        var secondX = Math.floor(bar.width * 0.2)
        var centerY = Math.floor(bar.height / 2)
        var origin = bar.mapToItem(panel, 0, 0)
        function pixel(image, x) {
          var px = Math.floor(origin.x + x)
          var py = Math.floor(origin.y + centerY)
          return [image.red(px, py), image.green(px, py), image.blue(px, py)].join(",")
        }

        mouseMove(bar, firstX, centerY)
        tryCompare(bar, "hoveredSegment", 0)
        waitForRendering(bar)
        wait(50)
        var highlighted = grabImage(panel)
        equal(pixel(highlighted, firstX), pixel(normal, firstX), "hovered server keeps its color")
        check(pixel(highlighted, secondX) !== pixel(normal, secondX), "other segments dim")
        equal(panel.selectedServer().serverId, selected, "chart hover does not move server selection")

        mouseMove(bar, bar.width * 0.45, centerY)
        tryCompare(bar, "hoveredSegment", 2)
        mouseMove(bar, bar.width * 0.8, centerY)
        tryCompare(bar, "hoveredSegment", 3)
        panel.panelActive = false
        tryCompare(bar, "hoveredSegment", -1)
        panel.panelActive = true
        mouseMove(tests, 850, 750)
        tryCompare(bar, "hoveredSegment", -1)
        waitForRendering(bar)
        wait(50)
        var restored = grabImage(panel)
        equal(pixel(restored, firstX), pixel(normal, firstX))
        equal(pixel(restored, secondX), pixel(normal, secondX), "leaving restores the normal chart")
      }

      function test_closed_panel_defers_updates() {
        panel.panelActive = false
        RadarModel.syncServerModel(servers, fixtures(3))
        panel.revision++
        wait(100)
        equal(list.count, 50)
        panel.panelActive = true
        tryCompare(list, "count", 3)
      }

      function test_font_scaling_and_long_plain_text() {
        Style.fontBaseSize = 18
        panel.width = panel.implicitWidth
        panel.height = 650
        servers.setProperty(0, "name", "<b>A very long project name that is plain text</b>")
        panel.revision++
        settled()
        list.positionViewAtEnd()
        settled()
        verifyViewport()
        list.positionViewAtBeginning()
        settled()
        var row = list.itemAtIndex(0)
        check(row !== null)
        var before = row.height
        servers.setProperty(0, "name", "Short")
        panel.revision++
        settled()
        equal(list.itemAtIndex(0).height, before, "long names do not change row geometry")
        var path = Quickshell.env("LOCALHOST_TEST_ARTIFACTS")
        if (path) grabImage(panel).save(path + "/server-panel-scaled.png")
      }

      function verifyInlineAlignment(item) {
        var checked = 0
        if (item.visible && item.label && item.paintedCenterY !== undefined) {
          var metrics = createTemporaryObject(metricsComponent, tests, { font: item.label.font, text: "H" })
          var labelCenter = item.label.mapToItem(tests, 0, item.label.baselineOffset
            + metrics.tightBoundingRect.y + metrics.tightBoundingRect.height / 2).y
          fuzzyCompare(item.mapToItem(tests, 0, item.paintedCenterY).y, labelCenter, 0.6,
            "icon aligns to the visible text at font size " + Style.fontBaseSize)
          checked++
        }
        if (item.children) for (var i = 0; i < item.children.length; i++) checked += verifyInlineAlignment(item.children[i])
        return checked
      }

      function test_icons_and_project_counts_align_at_multiple_font_sizes() {
        groupedFixtures(6)
        servers.setProperty(0, "name", "transactional")
        servers.setProperty(0, "frameworkId", "react")
        panel.revision++
        var qr = createTemporaryObject(qrContentComponent, tests, { qrState: {
          projectName: "transactional", url: "http://192.168.1.2:3000", error: "",
          qrSize: 0, qrRows: [], loading: false, showingQr: false
        } })
        qr.height = Qt.binding(function() { return qr.implicitHeight })
        for (var size of [12, 18]) {
          Style.fontBaseSize = size
          panel.width = panel.implicitWidth
          panel.height = 650
          list.positionViewAtBeginning()
          settled()
          check(verifyInlineAlignment(panel) >= 4, "check RAM, sharing and project action icons")
          equal(verifyInlineAlignment(qr), 1)
          var header = findChild(list.itemAtIndex(0), "projectHeader")
          var name = findChild(header, "projectName")
          var count = findChild(header, "projectCount")
          fuzzyCompare(name.mapToItem(header, 0, name.baselineOffset).y,
            count.mapToItem(header, 0, count.baselineOffset).y, 0.6, "project label and count share a baseline")
          var glyph = findChild(list.itemAtIndex(1), "frameworkGlyph")
          check(glyph !== null)
          fuzzyCompare(glyph.paintedCenterX, glyph.width / 2, 0.01)
          fuzzyCompare(glyph.paintedCenterY, glyph.height / 2, 0.01)
          var path = Quickshell.env("LOCALHOST_TEST_ARTIFACTS")
          qr.visible = false
          if (path) grabImage(panel).save(path + "/alignment-" + size + ".png")
          qr.visible = true
        }
      }

      function test_project_grouping_filtering_and_shared_actions() {
        panel.groupByProject = true
        var rows = fixtures(6)
        for (var i = 0; i < rows.length; i++) {
          rows[i].projectRoot = i % 2 ? "/work/console" : "/work/atlas"
          rows[i].projectPath = "apps/" + rows[i].name
        }
        RadarModel.syncServerModel(servers, rows)
        panel.revision++
        tryCompare(list, "count", 8)
        settled()
        equal(panel.projectCount, 2)
        panel.selectedIndex = 2
        equal(panel.selectedServer().serverId, "server-4")
        var toggle = findChild(panel, "groupToggle")
        mouseClick(toggle, toggle.width / 2, toggle.height / 2)
        settled()
        equal(panel.groupByProject, false)
        equal(panel.selectedServer().serverId, "server-4")
        equal(panel.selectedIndex, 4)
        var open = findChild(panel, "serverAction0")
        mouseClick(open, open.width / 2, open.height / 2)
        equal(openSpy.count, 1)
        equal(openSpy.signalArguments[0][0].serverId, "server-4")
        panel.groupByProject = true
        panel.query = "console"
        tryCompare(list, "count", 4)
        equal(panel.projectCount, 1)
        panel.selectedIndex = 0
        equal(findChild(panel, "serverAction3").enabled, false)
        settled()
        verifyViewport()
      }

      function groupedFixtures(count) {
        var rows = fixtures(count)
        for (var i = 0; i < count; i++) {
          rows[i].projectRoot = ["/work/atlas", "/work/console", "/work/tools"][i % 3]
          rows[i].projectPath = "apps/" + rows[i].name
        }
        panel.groupByProject = true
        RadarModel.syncServerModel(servers, rows)
        panel.revision++
        tryCompare(list, "count", count + 3)
        settled()
      }

      function test_project_stop_all_is_one_click_and_does_not_fold() {
        groupedFixtures(9)
        panel.setProjectCollapsed("/work/atlas", true)
        settled()
        var header = findChild(list.itemAtIndex(0), "projectHeader")
        check(header !== null)
        var button = findChild(header, "projectStopAll")
        check(button !== null && button.enabled)
        equal(findChild(button, "projectStopIcon").text, "\uf04d")
        mouseClick(button, button.width / 2, button.height / 2)
        equal(projectStopSpy.count, 1)
        equal(projectStopSpy.signalArguments[0][0], "/work/atlas")
        equal(panel.pendingAction, "", "one click needs no per-server confirmation")
        equal(panel.isProjectCollapsed("/work/atlas"), true, "stop does not toggle folding")
        button.forceActiveFocus()
        keyClick(Qt.Key_Return)
        equal(projectStopSpy.count, 2, "the stop icon supports keyboard activation")
        equal(panel.isProjectCollapsed("/work/atlas"), true, "Enter on stop does not fold the project")
        panel.actionBusy = true
        panel.stoppingProjectRoot = "/work/atlas"
        equal(button.enabled, false)
        equal(findChild(button, "projectStopIcon").text, "\uf251")
        mouseClick(button, button.width / 2, button.height / 2)
        equal(projectStopSpy.count, 2, "a busy stop cannot be started twice")
        panel.actionBusy = false
        panel.stoppingProjectRoot = ""
        panel.query = "Project 3"
        tryCompare(list, "count", 2)
        settled()
        header = findChild(list.itemAtIndex(0), "projectHeader")
        button = findChild(header, "projectStopAll")
        mouseClick(button, button.width / 2, button.height / 2)
        equal(projectStopSpy.count, 3)
        equal(projectStopSpy.signalArguments[2][0], "/work/atlas",
          "filtering still requests the entire project")
        check(button.mapToItem(panel, button.width, 0).x <= panel.width,
          "stop fits inside the panel")
      }

      function test_project_stop_arrow_navigation_and_busy_guard() {
        groupedFixtures(9)
        panel.focusNavigation()
        wait(50)
        keyClick(Qt.Key_Home)
        equal(panel.selectedProjectRoot, "/work/atlas")
        equal(panel.projectStopSelected, false)
        var header = findChild(list.itemAtIndex(0), "projectHeader")
        var button = findChild(header, "projectStopAll")
        keyClick(Qt.Key_Right)
        equal(panel.projectStopSelected, true)
        equal(header.hasCursor, false, "the header yields the visible keyboard cursor")
        equal(button.hasCursor, true, "the stop icon visibly owns the keyboard cursor")
        keyClick(Qt.Key_Return)
        equal(projectStopSpy.count, 1)
        equal(projectStopSpy.signalArguments[0][0], "/work/atlas")
        equal(panel.pendingAction, "")
        equal(panel.isProjectCollapsed("/work/atlas"), false)
        panel.revision++
        settled()
        check(panel.projectStopSelected, "stable discovery preserves the action cursor")
        var path = Quickshell.env("LOCALHOST_TEST_ARTIFACTS")
        if (path) grabImage(panel).save(path + "/project-stop-keyboard.png")
        keyClick(Qt.Key_Left)
        equal(panel.projectStopSelected, false)
        keyClick(Qt.Key_Space)
        equal(panel.isProjectCollapsed("/work/atlas"), true)
        keyClick(Qt.Key_Right)
        check(panel.projectStopSelected, "Stop all remains reachable on a folded header")
        keyClick(Qt.Key_Space)
        equal(projectStopSpy.count, 2)
        equal(panel.isProjectCollapsed("/work/atlas"), true, "Space on stop does not fold")
        var closed = 0
        panel.closeRequested.connect(function() { closed++ })
        keyClick(Qt.Key_Escape)
        equal(panel.projectStopSelected, false)
        equal(closed, 0, "Escape leaves the action before closing the panel")
        keyClick(Qt.Key_Right)
        keyClick(Qt.Key_Down)
        equal(panel.selectedProjectRoot, "/work/console")
        equal(panel.projectStopSelected, false, "moving projects clears the destructive action cursor")
        keyClick(Qt.Key_Right)
        panel.actionBusy = true
        equal(panel.projectStopSelected, false)
        panel.activateSelected()
        equal(projectStopSpy.count, 2, "busy activation cannot dispatch another batch")
        keyClick(Qt.Key_Right)
        check(panel.selectedServer() !== null, "right skips the disabled stop action")
        equal(panel.projectStopSelected, false)
        equal(stopSpy.count, 0)
      }

      function test_project_stop_vim_navigation_search_and_auxiliary_guards() {
        groupedFixtures(9)
        panel.focusNavigation()
        wait(50)
        keyClick(Qt.Key_G)
        keyClick(Qt.Key_G)
        keyClick(Qt.Key_L)
        check(panel.projectStopSelected)
        keyClick(Qt.Key_Return)
        equal(projectStopSpy.count, 1)
        equal(projectStopSpy.signalArguments[0][0], "/work/atlas")
        keyClick(Qt.Key_H)
        equal(panel.projectStopSelected, false)
        keyClick(Qt.Key_Z)
        keyClick(Qt.Key_C)
        check(panel.isProjectCollapsed("/work/atlas"))
        keyClick(Qt.Key_L)
        keyClick(Qt.Key_Return)
        equal(projectStopSpy.count, 2)
        check(panel.isProjectCollapsed("/work/atlas"))
        keyClick(Qt.Key_Z)
        keyClick(Qt.Key_O)
        check(!panel.isProjectCollapsed("/work/atlas"))
        equal(panel.projectStopSelected, false, "fold commands restore the header cursor")
        keyClick(Qt.Key_L)
        keyClick(Qt.Key_J, Qt.ShiftModifier)
        equal(panel.selectedProjectRoot, "/work/console")
        equal(panel.projectStopSelected, false)
        keyClick(Qt.Key_L)
        keyClick(Qt.Key_K, Qt.ShiftModifier)
        equal(panel.selectedProjectRoot, "/work/atlas")
        equal(panel.projectStopSelected, false)
        keyClick(Qt.Key_L)
        panel.showDiagnostics = true
        equal(panel.projectStopSelected, false)
        keyClick(Qt.Key_L)
        keyClick(Qt.Key_Return)
        equal(projectStopSpy.count, 2, "diagnostics cannot activate a hidden project action")
        panel.showDiagnostics = false
        keyClick(Qt.Key_L)
        panel.showFirewallRules = true
        equal(panel.projectStopSelected, false)
        keyClick(Qt.Key_Return)
        equal(projectStopSpy.count, 2)
        panel.showFirewallRules = false
        keyClick(Qt.Key_L)
        panel.beginSearch()
        wait(50)
        check(panel.searchMode)
        equal(panel.projectStopSelected, false)
        keyClick(Qt.Key_L)
        keyClick(Qt.Key_H)
        equal(panel.query, "lh", "Vim action keys remain ordinary search text")
        keyClick(Qt.Key_Return)
        equal(projectStopSpy.count, 2, "search input cannot retain a destructive action cursor")
        panel.clearSearch()
        wait(50)
        keyClick(Qt.Key_Home)
        keyClick(Qt.Key_L)
        check(panel.projectStopSelected)
        var remaining = []
        for (var i = 0; i < servers.count; i++)
          if (servers.get(i).projectRoot !== "/work/atlas") remaining.push(servers.get(i))
        RadarModel.syncServerModel(servers, remaining)
        panel.revision++
        settled()
        equal(panel.projectStopSelected, false, "removing the selected project clears its action cursor")
        keyClick(Qt.Key_Return)
        equal(projectStopSpy.count, 2, "discovery changes cannot redirect Enter to another project's stop")
        equal(stopSpy.count, 0)
      }

      function test_project_keyboard_fold_and_jump() {
        groupedFixtures(9)
        panel.focusNavigation()
        wait(50)
        keyClick(Qt.Key_Home)
        equal(panel.selectedProjectRoot, "/work/atlas")
        equal(panel.selectedServer(), null)
        equal(findChild(panel, "serverAction0").enabled, false)
        keyClick(Qt.Key_Delete)
        keyClick(Qt.Key_C, Qt.ControlModifier)
        equal(panel.pendingAction, "")
        equal(stopSpy.count, 0)
        equal(copySpy.count, 0)
        keyClick(Qt.Key_Space)
        tryCompare(list, "count", 9)
        equal(panel.resultCount, 9, "folding keeps result totals")
        equal(panel.projectCount, 3)
        keyClick(Qt.Key_J)
        equal(panel.selectedProjectRoot, "/work/console", "down skips hidden servers")
        keyClick(Qt.Key_H)
        tryCompare(list, "count", 6)
        keyClick(Qt.Key_Left)
        equal(list.count, 6, "left is idempotent")
        keyClick(Qt.Key_Right, Qt.ControlModifier)
        tryCompare(list, "count", 9)
        equal(panel.selectedProjectRoot, "/work/console", "Ctrl+right expands the project")
        keyClick(Qt.Key_Right)
        check(panel.projectStopSelected, "right selects the project's stop action")
        keyClick(Qt.Key_Right)
        equal(panel.selectedServer().serverId, "server-1")
        keyClick(Qt.Key_Right)
        equal(panel.selectedActionIndex, RadarModel.ACTIONS.copyLocal, "server arrows still select actions")
        keyClick(Qt.Key_Left, Qt.ControlModifier)
        equal(panel.selectedProjectRoot, "/work/console", "folding a selected child selects its header")
        tryCompare(list, "count", 6)
        keyClick(Qt.Key_Right, Qt.ControlModifier)
        tryCompare(list, "count", 9)
        keyClick(Qt.Key_Tab)
        equal(panel.selectedProjectRoot, "/work/tools")
        keyClick(Qt.Key_Backtab, Qt.ShiftModifier)
        equal(panel.selectedProjectRoot, "/work/console")
        keyClick(Qt.Key_Up, Qt.ControlModifier)
        equal(panel.selectedProjectRoot, "/work/atlas")
        keyClick(Qt.Key_Up, Qt.ControlModifier)
        equal(panel.selectedProjectRoot, "/work/atlas", "project jumps stop at the first project")
        for (var repeat = 0; repeat < 4; repeat++) keyClick(Qt.Key_Down, Qt.ControlModifier)
        equal(panel.selectedProjectRoot, "/work/tools", "project jumps stop at the last project")
        keyClick(Qt.Key_Up, Qt.ControlModifier)
        keyClick(Qt.Key_Up, Qt.ControlModifier)
        equal(panel.selectedProjectRoot, "/work/atlas")
        keyClick(Qt.Key_Return)
        tryCompare(list, "count", 12)
        equal(openSpy.count, 0, "Enter on a header never opens a server")
        keyClick(Qt.Key_End)
        equal(panel.selectedServer().serverId, "server-8")
        settled()
        check(list.atYEnd)
        keyClick(Qt.Key_Home)
        settled()
        check(list.atYBeginning)
      }

      function test_project_fold_all_and_auxiliary_pages() {
        groupedFixtures(9)
        panel.focusNavigation()
        wait(50)
        keyClick(Qt.Key_Left, Qt.ControlModifier | Qt.ShiftModifier)
        tryCompare(list, "count", 3)
        equal(panel.selectedProjectRoot, "/work/atlas")
        keyClick(Qt.Key_K)
        equal(panel.selectedProjectRoot, "/work/atlas")
        keyClick(Qt.Key_G, Qt.ShiftModifier)
        equal(panel.selectedProjectRoot, "/work/tools")
        keyClick(Qt.Key_J)
        equal(panel.selectedProjectRoot, "/work/tools", "folded project navigation does not wrap")
        keyClick(Qt.Key_G)
        keyClick(Qt.Key_G)
        equal(panel.selectedProjectRoot, "/work/atlas")
        keyClick(Qt.Key_Right, Qt.ControlModifier | Qt.ShiftModifier)
        tryCompare(list, "count", 12)
        panel.showDiagnostics = true
        keyClick(Qt.Key_Left, Qt.ControlModifier)
        keyClick(Qt.Key_Left, Qt.ControlModifier | Qt.ShiftModifier)
        equal(list.count, 12, "diagnostics cannot fold the hidden list")
        panel.showDiagnostics = false
        panel.showFirewallRules = true
        keyClick(Qt.Key_Left, Qt.ControlModifier)
        equal(list.count, 12)
        panel.showFirewallRules = false
        panel.selectedIndex = 0
        keyClick(Qt.Key_Delete)
        keyClick(Qt.Key_Left, Qt.ControlModifier | Qt.ShiftModifier)
        equal(list.count, 12, "confirmation owns keyboard input")
        keyClick(Qt.Key_Escape)
        equal(panel.pendingAction, "")
      }

      function test_project_vim_motions_and_fold_commands() {
        groupedFixtures(9)
        panel.focusNavigation()
        wait(50)
        keyClick(Qt.Key_L)
        equal(panel.selectedActionIndex, RadarModel.ACTIONS.copyLocal)
        keyClick(Qt.Key_H)
        equal(panel.selectedActionIndex, RadarModel.ACTIONS.open)
        keyClick(Qt.Key_Z)
        keyClick(Qt.Key_C)
        tryCompare(list, "count", 9)
        equal(panel.selectedProjectRoot, "/work/atlas")
        keyClick(Qt.Key_J, Qt.ShiftModifier)
        equal(panel.selectedProjectRoot, "/work/console")
        keyClick(Qt.Key_K, Qt.ShiftModifier)
        equal(panel.selectedProjectRoot, "/work/atlas")
        keyClick(Qt.Key_H)
        equal(list.count, 9)
        keyClick(Qt.Key_Z)
        keyClick(Qt.Key_O)
        tryCompare(list, "count", 12)
        keyClick(Qt.Key_L)
        check(panel.projectStopSelected, "l selects Stop all on a project header")
        keyClick(Qt.Key_L)
        equal(panel.selectedServer().serverId, "server-0", "l enters an expanded project")
        keyClick(Qt.Key_J)
        equal(panel.selectedServer().serverId, "server-3")
        keyClick(Qt.Key_K)
        equal(panel.selectedServer().serverId, "server-0")
        keyClick(Qt.Key_Z)
        keyClick(Qt.Key_A)
        tryCompare(list, "count", 9)
        keyClick(Qt.Key_J)
        equal(panel.selectedProjectRoot, "/work/console", "j skips folded children")
        keyClick(Qt.Key_K)
        equal(panel.selectedProjectRoot, "/work/atlas")
        keyClick(Qt.Key_Z)
        keyClick(Qt.Key_A)
        tryCompare(list, "count", 12)
        keyClick(Qt.Key_Z)
        keyClick(Qt.Key_C)
        keyClick(Qt.Key_Z)
        keyClick(Qt.Key_O)
        tryCompare(list, "count", 12)
        keyClick(Qt.Key_Z)
        keyPress(Qt.Key_Shift)
        equal(panel.pendingVimPrefix, "z", "modifier presses preserve a pending fold command")
        keyClick(Qt.Key_M, Qt.ShiftModifier)
        keyRelease(Qt.Key_Shift)
        tryCompare(list, "count", 3)
        keyClick(Qt.Key_K, Qt.ShiftModifier)
        equal(panel.selectedProjectRoot, "/work/atlas", "K stops at the first project")
        keyClick(Qt.Key_J, Qt.ShiftModifier)
        equal(panel.selectedProjectRoot, "/work/console")
        keyClick(Qt.Key_Z)
        keyClick(Qt.Key_R, Qt.ShiftModifier)
        tryCompare(list, "count", 12)
        keyClick(Qt.Key_G, Qt.ShiftModifier)
        equal(panel.selectedServer().serverId, "server-8")
        settled()
        check(list.atYEnd)
        keyClick(Qt.Key_G)
        keyClick(Qt.Key_G)
        equal(panel.selectedProjectRoot, "/work/atlas")
        settled()
        check(list.atYBeginning)
        equal(openSpy.count, 0)
        equal(stopSpy.count, 0)
      }

      function test_vim_prefix_cancellation_and_search_text() {
        groupedFixtures(9)
        panel.focusNavigation()
        wait(50)
        var closed = 0
        panel.closeRequested.connect(function() { closed++ })
        keyClick(Qt.Key_Z)
        equal(panel.pendingVimPrefix, "z")
        keyClick(Qt.Key_Escape)
        equal(panel.pendingVimPrefix, "")
        equal(closed, 0, "Escape cancels a command before closing the panel")
        keyClick(Qt.Key_G)
        keyClick(Qt.Key_J)
        equal(panel.pendingVimPrefix, "")
        equal(panel.selectedServer().serverId, "server-3", "other motions cancel an incomplete prefix")
        keyClick(Qt.Key_Z)
        panel.beginSearch()
        wait(50)
        check(panel.searchMode)
        equal(panel.pendingVimPrefix, "")
        var input = "hjklzczozazMzRggGJK"
        for (var i = 0; i < input.length; i++) {
          var letter = input.charAt(i)
          keyClick(letter.toUpperCase().charCodeAt(0),
            letter === letter.toUpperCase() ? Qt.ShiftModifier : Qt.NoModifier)
        }
        // QtTest's offscreen keyClick sends lowercase text even with Shift.
        equal(panel.query, input.toLowerCase(), "Vim commands are ordinary text during search")
        equal(Object.keys(panel.collapsedProjects).length, 0)
        equal(panel.pendingVimPrefix, "")
        panel.clearSearch()
        wait(50)
        tryCompare(list, "count", 12)
        panel.selectedIndex = 0
        keyClick(Qt.Key_K, Qt.ControlModifier)
        equal(panel.pendingAction, "stop", "the existing Ctrl+K shortcut is preserved")
        keyClick(Qt.Key_Z)
        equal(panel.pendingVimPrefix, "", "confirmation cannot begin a Vim command")
        keyClick(Qt.Key_Escape)
        panel.showDiagnostics = true
        keyClick(Qt.Key_Z)
        keyClick(Qt.Key_M, Qt.ShiftModifier)
        equal(list.count, 12)
        equal(panel.pendingVimPrefix, "")
      }

      function test_folded_list_shrinks_and_rows_keep_full_width() {
        groupedFixtures(9)
        panel.query = "Project 0"
        tryCompare(list, "count", 2)
        panel.height = Qt.binding(function() { return panel.implicitHeight })
        settled()
        var expanded = panel.height
        panel.setProjectCollapsed("/work/atlas", true)
        tryCompare(list, "count", 1)
        settled()
        check(panel.height < expanded, "folding shrinks the popup")
        check(Math.abs(list.height - list.contentHeight) < 2, "folded headers leave no minimum-height gap")
        var header = list.itemAtIndex(0)
        fuzzyCompare(header.x, 0, 0.5)
        fuzzyCompare(header.width, list.width, 0.5)
        panel.query = ""
        panel.height = 320
        settled()
        check(list.interactive)
        var row = list.itemAtIndex(0)
        fuzzyCompare(row.width, list.width, 0.5, "rows fill the viewport beside the scrollbar")
      }

      function test_project_mouse_toggle_and_live_row_updates() {
        groupedFixtures(9)
        var header = list.itemAtIndex(0).item
        equal(header.objectName, "projectHeader")
        equal(header.count, 3)
        panel.selectedIndex = 2
        equal(panel.selectedServer().serverId, "server-6")
        mouseClick(header, header.width / 2, header.height / 2)
        tryCompare(list, "count", 9)
        equal(panel.selectedProjectRoot, "/work/atlas")
        check(header.collapsed)
        check(header.selected)
        mouseClick(header, header.width / 2, header.height / 2)
        tryCompare(list, "count", 12)
        var row = list.itemAtIndex(1).item
        servers.setProperty(0, "name", "Renamed server")
        servers.setProperty(0, "memoryBytes", 123 * 1048576)
        panel.revision++
        tryVerify(function() { return row.server.name === "Renamed server" })
        equal(findChild(row, "serverMemory").text, "123 MiB")
        mouseClick(row, row.width / 2, row.height / 2)
        equal(panel.selectedServer().serverId, "server-0")
        panel.focusNavigation()
        wait(50)
        keyClick(Qt.Key_Return)
        equal(openSpy.signalArguments[0][0].serverId, "server-0")
      }

      function test_project_search_reveals_matches_and_restores_folds() {
        groupedFixtures(9)
        panel.setProjectCollapsed("/work/atlas", true)
        tryCompare(list, "count", 9)
        panel.query = "Project 3"
        tryCompare(list, "count", 2)
        check(!panel.isProjectCollapsed("/work/atlas"), "search reveals hidden matches")
        panel.focusNavigation()
        wait(50)
        keyClick(Qt.Key_Down)
        equal(panel.selectedServer().serverId, "server-3")
        keyClick(Qt.Key_Return)
        equal(openSpy.signalArguments[0][0].serverId, "server-3")
        panel.setProjectCollapsed("/work/atlas", true)
        equal(list.count, 1, "search results can also be folded")
        panel.query = "Project 6"
        equal(list.count, 2, "a new search reveals results again")
        panel.query = ""
        tryCompare(list, "count", 9)
        check(panel.isProjectCollapsed("/work/atlas"), "clearing search restores the original folds")
        panel.portFilter = "lan"
        tryCompare(list, "count", 8)
        check(!panel.isProjectCollapsed("/work/atlas"), "port filters reveal matching rows")
        panel.portFilter = "all"
        tryCompare(list, "count", 9)
        panel.beginSearch()
        wait(50)
        check(panel.searchMode)
        keyClick(Qt.Key_Right, Qt.ControlModifier)
        equal(list.count, 9, "text editing does not expand projects")
        keyClick(Qt.Key_Escape)
        wait(50)
        panel.query = "no matches"
        tryCompare(list, "count", 0)
        equal(panel.selectedServer(), null)
        equal(panel.selectedProjectRoot, "")
        panel.query = ""
        tryCompare(list, "count", 9)
        equal(panel.selectedProjectRoot, "/work/atlas", "selection never points into a folded project")
      }

      function test_project_fold_state_survives_flat_mode_and_scans() {
        groupedFixtures(9)
        panel.setProjectCollapsed("/work/atlas", true)
        panel.groupByProject = false
        tryCompare(list, "count", 9)
        equal(panel.selectedServer().serverId, "server-0")
        panel.selectedIndex = 3
        panel.groupByProject = true
        tryCompare(list, "count", 9)
        equal(panel.selectedProjectRoot, "/work/atlas")
        panel.panelActive = false
        servers.append(RadarModel.normalizeServer({ serverId: "new", projectRoot: "/work/atlas", port: 3010 }))
        panel.revision++
        wait(50)
        equal(panel.resultCount, 9)
        panel.panelActive = true
        tryCompare(panel, "resultCount", 10)
        equal(list.count, 9)
        equal(list.itemAtIndex(0).item.count, 4)
        equal(panel.selectedProjectRoot, "/work/atlas")
        for (var i = servers.count - 1; i >= 0; i--)
          if (servers.get(i).projectRoot === "/work/atlas") servers.remove(i)
        panel.revision++
        tryCompare(list, "count", 8)
        equal(panel.selectedServer().serverId, "server-1", "removed headers choose a surviving entry")
        verifyViewport()
      }

      function test_project_folds_preserve_manual_scroll_on_background_scan() {
        groupedFixtures(60)
        panel.setProjectCollapsed("/work/atlas", true)
        list.positionViewAtIndex(30, ListView.Beginning)
        settled()
        var before = list.contentY
        servers.setProperty(30, "memoryBytes", 987 * 1048576)
        panel.revision++
        settled()
        fuzzyCompare(list.contentY, before, 1)
        equal(panel.selectedProjectRoot, "/work/atlas")
        equal(list.count, 43)
        verifyViewport()
        panel.focusNavigation()
        wait(50)
        keyClick(Qt.Key_Down, Qt.ControlModifier)
        settled()
        equal(panel.selectedProjectRoot, "/work/console")
        verifyViewport()
        var path = Quickshell.env("LOCALHOST_TEST_ARTIFACTS")
        if (path) grabImage(panel).save(path + "/project-folds.png")
      }

      function test_manual_refresh_queue_keeps_cache_bypass() {
        var service = createTemporaryObject(serviceComponent, tests)
        var discovery = findChild(service, "nativeDiscovery")
        discovery.scanning = true
        discovery.scan(true)
        equal(discovery.manualScanQueued, true)
        equal(discovery.scanQueued, true)
        discovery.scan()
        equal(discovery.manualScanQueued, true, "background requests cannot clear queued manual refresh")
        discovery.currentUid = 0
        discovery.scanning = false
        discovery.scan()
        equal(discovery.bypassProbeCache, true)
        equal(discovery.manualScanQueued, false)
        discovery.scan(true)
        equal(discovery.manualScanQueued, true, "manual refresh during a forced scan schedules another forced scan")
      }

      function test_skipped_ports_survive_scan_and_merge_without_truncation() {
        var service = createTemporaryObject(serviceComponent, tests, { includeDocker: true })
        var native = findChild(service, "nativeDiscovery")
        var docker = findChild(service, "dockerDiscovery")
        var listeners = []
        for (var i = 0; i < 45; i++) listeners.push({ pid: 410, port: 4000 + i, process: "helper" })
        native.pendingListeners = listeners
        native.metadataOutput = JSON.stringify({ ok: true, processes: [] })
        native.cacheMetadata()
        equal(native.diagnostics.length, 45, "metadata exclusions survive both discovery stages")
        docker.pendingDiagnostics = []
        docker.pendingContexts = listeners.map(function(listener) {
          return { id: "container:" + listener.port, source: "docker", process: { cwd: "" },
            listener: { port: listener.port - 1000, process: "container" } }
        })
        docker.pendingSchemes = ({})
        docker.applyCandidates()
        service.publishServers()
        equal(service.diagnostics.length, 90, "both sources retain every exclusion")
        equal(service.diagnostics[0].port, 3000, "the combined list sorts by port")
        equal(service.diagnostics[89].port, 4044)
        service.includeDocker = false
        service.publishServers()
        equal(service.diagnostics.length, 45, "disabled sources leave the list")
      }

      function test_project_stop_missing_helper_finishes_and_unlocks() {
        var service = createTemporaryObject(serviceComponent, tests)
        var rows = fixtures(2)
        rows[0].pid = 2147483647
        rows[1].pid = 2147483646
        RadarModel.syncServerModel(service.servers, rows)
        var process = findChild(service, "serverActionProcess")
        function missingHelper() {
          if (process.command[1] === service.helperPath)
            process.command = ["/nonexistent/localhost-test-helper"]
        }
        process.commandChanged.connect(missingHelper)
        actionSpy.target = service
        actionSpy.clear()
        check(service.stopProject("/tmp/fixtures"))
        tryCompare(service, "actionBusy", false, 5000)
        equal(actionSpy.count, 3, "each launch failure and the batch summary are reported")
        equal(actionSpy.signalArguments[2][0], "stop-project")
        equal(actionSpy.signalArguments[2][1], false)
        check(actionSpy.signalArguments[2][2].indexOf("Project 0 (:3000)") !== -1)
        check(actionSpy.signalArguments[2][2].indexOf("Could not start") !== -1)
        equal(service.projectStopQueue.length, 0)
        equal(service.actionName, "")
        process.commandChanged.disconnect(missingHelper)
      }

      function test_project_stop_mixed_sources_keep_each_force_stop_and_can_retry() {
        var service = createTemporaryObject(serviceComponent, tests)
        var rows = fixtures(2)
        rows[0].pid = 2147483647
        rows[1].pid = 2147483646
        rows.push(RadarModel.normalizeServer(Object.assign({}, rows[0], {
          serverId: "docker-api", source: "docker", containerId: "abc123def456", port: 9000
        })))
        rows.push(RadarModel.normalizeServer(Object.assign({}, rows[0], {
          serverId: "shared-port", port: 3002
        })))
        RadarModel.syncServerModel(service.servers, rows)
        var process = findChild(service, "serverActionProcess")
        var commands = []
        var succeed = false
        function helperResponse() {
          var command = Array.from(process.command)
          if (command[1] !== service.helperPath) return
          commands.push(command)
          var successful = succeed || command[2] === "docker-action"
          var payload = successful ? { ok: true, message: "Stopped" }
            : { ok: false, error: "The server did not stop cleanly; use Force stop if needed" }
          process.command = ["python3", "-c", "print(" + JSON.stringify(JSON.stringify(payload)) + ")"]
        }
        process.commandChanged.connect(helperResponse)
        actionSpy.target = service
        actionSpy.clear()
        check(service.stopProject("/tmp/fixtures"))
        service.servers.clear()
        tryCompare(service, "actionBusy", false, 5000)
        equal(commands.length, 3, "the snapshot survives model churn and deduplicates shared ports")
        equal(commands[0][2], "process-action")
        equal(commands[0][6], String(rows[0].pid))
        equal(commands[0][8], String(rows[0].startTime))
        equal(commands[2][2], "docker-action")
        equal(commands[2][6], "abc123def456")
        equal(actionSpy.signalArguments[3][1], false)
        check(service.forceStopSourceKeys[RadarModel.memorySourceKey(rows[0])],
          "the first failed process retains Force stop: " + JSON.stringify(service.forceStopSourceKeys))
        check(service.forceStopSourceKeys[RadarModel.memorySourceKey(rows[1])],
          "both failed processes retain Force stop")
        check(service.forceStopSourceKeys[RadarModel.memorySourceKey(rows[3])],
          "another port on the same process also offers Force stop")
        succeed = true
        service.forceStop(rows[0])
        equal(service.actionBusy, true, "controls lock before the helper finishes starting")
        tryCompare(service, "actionBusy", false, 5000)
        equal(commands[3][4], "force-stop")
        check(!service.forceStopSourceKeys[RadarModel.memorySourceKey(rows[0])],
          "successful force stop clears that process's recovery state")
        check(service.forceStopSourceKeys[RadarModel.memorySourceKey(rows[1])],
          "stopping one process preserves the other's Force stop")
        RadarModel.syncServerModel(service.servers, rows)
        check(service.stopProject("/tmp/fixtures"))
        tryCompare(service, "actionBusy", false, 5000)
        equal(commands.length, 7)
        equal(actionSpy.signalArguments[8][0], "stop-project")
        equal(actionSpy.signalArguments[8][1], true)
        check(actionSpy.signalArguments[8][2].indexOf("Stopped 3/3 services") !== -1,
          "the successful retry reports its full result: " + actionSpy.signalArguments[8][2])
        equal(Object.keys(service.forceStopSourceKeys).length, 0)
        process.commandChanged.disconnect(helperResponse)
      }

      function test_live_discovery_and_verified_stop() {
        var port = Number(Quickshell.env("LOCALHOST_TEST_PORT"))
        check(port > 0, "runner provides a loopback HTTP fixture")
        var secondPort = Number(Quickshell.env("LOCALHOST_TEST_SECOND_PORT"))
        var service = createTemporaryObject(serviceComponent, tests, { alwaysIncludePorts: port + "," + secondPort, panelActive: true })
        function detected() {
          for (var i = 0; i < service.servers.count; i++) {
            var server = service.servers.get(i)
            if (server.port === port) return RadarModel.normalizeServer(server)
          }
          return null
        }
        tryVerify(function() { return detected() !== null }, 15000, "real HTTP server was discovered")
        var server = detected()
        equal(server.localUrl, "http://localhost:" + port)
        equal(server.lanAvailable, false)
        equal(server.projectRoot, Quickshell.env("LOCALHOST_TEST_PROJECT_ROOT"))
        tryVerify(function() {
          for (var i = 0; i < service.servers.count; i++)
            if (service.servers.get(i).port === secondPort) return true
          return false
        }, 5000, "two HTTP listeners from the same process are retained")
        check(server.startTime > 0)
        tryVerify(function() { return detected() && detected().memoryBytes > 0 }, 5000,
          "live process RAM was sampled independently after discovery")
        server = detected()
        check(service.systemMemory.totalBytes > service.systemMemory.availableBytes,
          "live system RAM was sampled")
        // Only the disposable fixture is eligible for this integration action.
        equal(server.pid, Number(Quickshell.env("LOCALHOST_TEST_PID")))
        var shared = []
        for (var i = 0; i < service.servers.count; i++) {
          var candidate = service.servers.get(i)
          if (candidate.pid === server.pid) shared.push(candidate)
        }
        check(shared.length >= 2, "fixture process exposes two ports")
        equal(RadarModel.memorySummary(shared).totalBytes, server.memoryBytes,
          "shared process RAM is counted once")
        tryVerify(function() {
          var refreshed = detected()
          return refreshed && RadarModel.parseMemoryHistory(refreshed.memoryHistoryJson).length >= 2
        }, 5000, "live RAM history gains samples independently of scans")
        tryCompare(service, "scanning", false, 5000)
        var failedCache = {}
        var nativeDiscovery = findChild(service, "nativeDiscovery")
        var context = nativeDiscovery.readyContexts.find(function(entry) {
          return RadarModel.contextId(entry.context) === server.serverId
        }).context
        failedCache[RadarModel.probeCacheKey(context)] = { scheme: "", attempts: 2, expiresAt: Date.now() + 15000 }
        nativeDiscovery.probeCache = failedCache
        service.servers.clear()
        service.refresh()
        tryVerify(function() { return detected() !== null }, 5000,
          "manual refresh discovers a ready server despite a cached failed probe")
        // A stale first target must not prevent the real fixture from stopping.
        // Two ports on that fixture must still produce only one stop action.
        var stale = RadarModel.normalizeServer({ serverId: "stale", pid: 2147483647,
          startTime: 1, projectRoot: server.projectRoot, localUrl: server.localUrl })
        var other = RadarModel.normalizeServer({ serverId: "other-project", pid: 2147483646,
          startTime: 1, projectRoot: "/unrelated", localUrl: server.localUrl })
        var targets = [stale, server, Object.assign({}, server, { serverId: "second-port", port: secondPort }), other]
        RadarModel.syncServerModel(service.servers, targets)
        actionSpy.target = service
        actionSpy.clear()
        check(service.stopProject(server.projectRoot))
        equal(service.actionBusy, true)
        equal(service.stopProject(server.projectRoot), false, "a second batch cannot interrupt the first")
        equal(service.runAction("stop", server), false, "individual actions cannot interrupt a batch")
        tryCompare(service, "actionBusy", false, 10000)
        equal(actionSpy.count, 3, "one failed stop, one successful stop, and one summary")
        equal(actionSpy.signalArguments[0][1], false)
        equal(actionSpy.signalArguments[1][1], true)
        equal(actionSpy.signalArguments[2][0], "stop-project")
        equal(actionSpy.signalArguments[2][1], false, "partial failures remain visible")
        check(actionSpy.signalArguments[2][2].indexOf("Stopped 1/2") !== -1)
        tryVerify(function() { return detected() === null }, 10000, "verified stop removes the server")
        check(service.systemMemory.totalBytes > 0, "system RAM remains available with no servers")
      }

      function test_docker_latency_does_not_delay_native_discovery() {
        var port = Number(Quickshell.env("LOCALHOST_TEST_PORT"))
        var service = createTemporaryObject(serviceComponent, tests, { includeDocker: true, alwaysIncludePorts: String(port) })
        tryVerify(function() {
          for (var i = 0; i < service.servers.count; i++)
            if (service.servers.get(i).port === port && service.servers.get(i).source === "process") return true
          return false
        }, 5000, "native listener is published independently")
        var docker = findChild(service, "dockerDiscovery")
        equal(docker.warnings.length, 0, "native result arrived before the slow Docker request finished")
        equal(docker.scanning, true, "Docker is still waiting while native results are usable")
        tryVerify(function() { return docker.warnings.length > 0 }, 5000)
        check(service.servers.count > 0, "Docker failure preserves native results")
      }

      function test_resource_cadence_and_history_follow_samples() {
        var service = createTemporaryObject(serviceComponent, tests)
        equal(service.nativeResourceIntervalMs, 15000)
        equal(service.dockerResourceIntervalMs, 30000)
        equal(service.dockerDiscoveryIntervalSec, 15)
        var discovery = findChild(service, "nativeDiscovery")
        var context = { listener: { pid: 410, port: 3000, process: "node", addresses: ["127.0.0.1"] },
          process: { cwd: "/work", pid: 410, startTime: 100 }, framework: { name: "Node", id: "node" } }
        discovery.readyContexts = [{ context: context, scheme: "http" }]
        service.publishServers()
        service.finishResourceSample(JSON.stringify({ ok: true, processes: [
          { pid: 410, uid: service.currentUid, startTime: 100, memoryBytes: 1048576 }
        ], containers: {}, systemMemory: { totalBytes: 10000000, availableBytes: 5000000 } }), false, 0)
        equal(RadarModel.parseMemoryHistory(service.servers.get(0).memoryHistoryJson).length, 1)
        service.publishServers()
        service.publishServers()
        equal(RadarModel.parseMemoryHistory(service.servers.get(0).memoryHistoryJson).length, 1,
          "discovery does not duplicate a stale RAM sample")
        service.panelActive = true
        equal(service.nativeResourceIntervalMs, 2000)
        equal(service.dockerResourceIntervalMs, 8000)
        equal(service.dockerDiscoveryIntervalSec, 5)
      }

      function test_independent_ram_results_preserve_identity_and_system_totals() {
        var service = createTemporaryObject(serviceComponent, tests, { includeDocker: true })
        var native = findChild(service, "nativeDiscovery")
        var docker = findChild(service, "dockerDiscovery")
        native.readyContexts = [{ scheme: "http", context: {
          listener: { pid: 410, port: 3000, process: "node", addresses: ["127.0.0.1"] },
          process: { cwd: "/work", startTime: 100 }, framework: { name: "Node", id: "node" }
        } }]
        docker.readyContexts = [{ scheme: "http", context: {
          source: "docker", containerId: "abc123def456",
          listener: { port: 8080, process: "docker", addresses: ["0.0.0.0"] },
          process: { cwd: "" }, framework: { name: "Docker", id: "docker" }
        } }]
        service.publishServers()
        equal(service.servers.count, 2)
        service.finishResourceSample(JSON.stringify({ ok: true, processes: [
          { pid: 410, uid: service.currentUid, startTime: 100, memoryBytes: 1048576 }
        ], systemMemory: { totalBytes: 10000000, availableBytes: 5000000 } }), false, 0)
        service.finishResourceSample(JSON.stringify({ ok: true, containers: { abc123def456: 2097152 } }), true, 0)
        equal(service.servers.get(0).memoryBytes, 1048576)
        equal(service.servers.get(1).memoryBytes, 2097152)
        equal(service.systemMemory.totalBytes, 10000000, "Docker sampling does not erase system totals")
        native.readyContexts[0].context.process.startTime = 101
        service.publishServers()
        equal(service.servers.get(0).memoryBytes, -1, "PID reuse drops the previous memory sample")
        service.includeDocker = false
        service.finishResourceSample(JSON.stringify({ ok: true, containers: { abc123def456: 9999999 } }), true, 0)
        equal(service.servers.count, 1, "late Docker RAM cannot restore a disabled source")
        equal(service.resourceByKey["docker:abc123def456"], undefined)
      }

      function test_failed_and_partial_ram_samples_invalidate_only_their_source() {
        var service = createTemporaryObject(serviceComponent, tests, { includeDocker: true })
        findChild(service, "nativeDiscovery").readyContexts = [{ scheme: "http", context: {
          listener: { pid: 410, port: 3000, process: "node", addresses: ["127.0.0.1"] },
          process: { cwd: "/work", startTime: 100 }, framework: { name: "Node", id: "node" }
        } }]
        findChild(service, "dockerDiscovery").readyContexts = ["abc123def456", "def456abc123"].map(function(id, index) {
          return { scheme: "http", context: {
            source: "docker", containerId: id,
            listener: { port: 8080 + index, process: "docker", addresses: ["0.0.0.0"] },
            process: { cwd: "" }, framework: { name: "Docker", id: "docker" }
          } }
        })
        service.publishServers()
        var nativeSample = JSON.stringify({ ok: true, processes: [
          { pid: 410, uid: service.currentUid, startTime: 100, memoryBytes: 1048576 }
        ], systemMemory: { totalBytes: 10000000, availableBytes: 5000000 } })
        var dockerSample = JSON.stringify({ ok: true, containers: { abc123def456: 2097152, def456abc123: 3145728 } })
        service.finishResourceSample(nativeSample, false, 0)
        service.finishResourceSample(dockerSample, true, 0)

        service.finishResourceSample(JSON.stringify({ ok: true, containers: { abc123def456: 4194304 } }), true, 0)
        equal(service.servers.get(1).memoryBytes, 4194304, "partial samples retain successful readings")
        equal(service.servers.get(2).memoryBytes, -1, "missing container readings become unavailable")
        equal(RadarModel.parseMemoryHistory(service.servers.get(2).memoryHistoryJson).length, 0)
        var rows = [service.servers.get(0), service.servers.get(1), service.servers.get(2)]
        equal(RadarModel.memoryBreakdown(rows, service.systemMemory).serverBytes, 5242880,
          "unavailable readings are excluded from the RAM total")

        var failures = [
          { raw: JSON.stringify({ ok: true, containers: {} }), code: 0 }, // Docker stats timeout.
          { raw: "invalid JSON", code: 0 },
          { raw: dockerSample, code: 1 }
        ]
        for (var i = 0; i < failures.length; i++) {
          service.finishResourceSample(dockerSample, true, 0)
          service.finishResourceSample(failures[i].raw, true, failures[i].code)
          equal(service.servers.get(1).memoryBytes, -1, "failed Docker samples invalidate previous readings")
          equal(service.servers.get(2).memoryBytes, -1)
          equal(service.servers.get(0).memoryBytes, 1048576, "Docker failures preserve native readings")
          equal(service.systemMemory.totalBytes, 10000000, "Docker failures preserve system totals")
          equal(RadarModel.parseMemoryHistory(service.servers.get(1).memoryHistoryJson).length, 0)
        }

        service.finishResourceSample(dockerSample, true, 0)
        equal(service.servers.get(1).memoryBytes, 2097152, "a later successful sample recovers")
        equal(RadarModel.parseMemoryHistory(service.servers.get(1).memoryHistoryJson).length, 1)
        service.finishResourceSample(nativeSample, false, 1)
        equal(service.servers.get(0).memoryBytes, -1, "native failures also invalidate previous readings")
        equal(service.systemMemory.totalBytes, -1)
        equal(service.servers.get(1).memoryBytes, 2097152, "native failures preserve Docker readings")
        check(service.resourceWarning !== "")
        service.finishResourceSample(nativeSample, false, 0)
        equal(service.servers.get(0).memoryBytes, 1048576)
        equal(service.systemMemory.totalBytes, 10000000)
        equal(service.resourceWarning, "")
      }

      function test_qr_canvas_pixels_and_replacement() {
        var qr = createTemporaryObject(qrComponent, tests, { x: 600, rows: ["101", "010", "111"], moduleSize: 8 })
        tryCompare(qr, "available", true)
        waitForRendering(qr)
        wait(100)
        var pixels = grabImage(qr)
        equal(pixels.width, 24)
        equal(pixels.red(4, 4), 0)
        equal(pixels.red(12, 4), 255)
        equal(pixels.red(12, 12), 0)
        qr.rows = ["000", "000", "000"]
        wait(100)
        pixels = grabImage(qr)
        equal(pixels.red(4, 4), 255, "repaint clears the previous matrix")
      }

      function test_qr_generation_reopen_and_close() {
        var overlay = createTemporaryObject(overlayComponent, tests)
        overlay.open(JSON.stringify({ name: "First", url: "http://192.168.1.2:3000" }))
        overlay.open(JSON.stringify({ name: "Second", url: "http://192.168.1.2:4000" }))
        tryVerify(function() { return overlay.showingQr }, 5000, "qrencode completes after reopening")
        equal(overlay.url, "http://192.168.1.2:4000")
        equal(overlay.error, "")
        equal(overlay.qrRows.length, overlay.qrSize)
        overlay.close()
        equal(overlay.qrSize, 0)
        overlay.open(JSON.stringify({ url: "http://192.168.1.2:5000" }))
        overlay.close()
        wait(200)
        equal(overlay.opened, false)
        equal(overlay.qrSize, 0, "late process output cannot reopen a dismissed QR")
        overlay.open("{}")
        equal(overlay.error, "No LAN URL was provided")
        equal(overlay.qrSize, 0)
        overlay.close()
      }

      function test_memory_summary_and_row_label() {
        RadarModel.syncServerModel(servers, fixtures(2))
        panel.revision++
        tryCompare(list, "count", 2)
        tryCompare(findChild(panel, "totalMemory"), "text", "16.00 GiB")
        tryCompare(findChild(panel, "trackedMemory"), "text", "30 MiB")
        var memoryBar = findChild(panel, "memoryBar")
        check(memoryBar !== null)
        var firstSegment = findChild(panel, "memorySegment")
        check(firstSegment !== null && firstSegment.width > 0)
        var otherSegment = findChild(panel, "otherMemorySegment")
        var freeSegment = findChild(panel, "freeMemorySegment")
        check(otherSegment.width > 0 && freeSegment.width > 0)
        check(Math.abs(firstSegment.width + (20 / 10) * firstSegment.width
          + otherSegment.width + freeSegment.width - memoryBar.width) < 2,
          "memory buckets fill the system RAM bar")
        waitForRendering(memoryBar)
        wait(50)
        var barPixels = grabImage(panel)
        var barOrigin = memoryBar.mapToItem(panel, 0, 0)
        var barX = Math.round(barOrigin.x)
        var barY = Math.round(barOrigin.y)
        var centerY = Math.round(barOrigin.y + memoryBar.height / 2)
        var rightX = Math.floor(barOrigin.x + memoryBar.width - 1)
        check(barPixels.red(barX, barY) !== barPixels.red(barX, centerY),
          "the colored left end follows the rounded outline")
        check(barPixels.red(rightX, barY) !== barPixels.red(rightX, centerY),
          "the right end follows the rounded outline")
        var rowMemory = findChild(panel, "serverMemory")
        check(rowMemory !== null)
        equal(rowMemory.text, "10 MiB")
        var sparkline = findChild(panel, "memorySparkline")
        check(sparkline !== null)
        equal(sparkline.samples.length, 8)
        waitForRendering(sparkline)
        var pixels = grabImage(sparkline)
        var painted = false
        for (var x = 0; x < pixels.width; x++)
          for (var y = 0; y < pixels.height; y++)
            if (pixels.alpha(x, y) > 0) painted = true
        check(painted, "sparkline has visible pixels")
        RadarModel.syncServerModel(servers, fixtures(7))
        panel.revision++
        tryCompare(list, "count", 7)
        waitForRendering(panel)
        var path = Quickshell.env("LOCALHOST_TEST_ARTIFACTS")
        if (path) grabImage(panel).save(path + "/server-panel.png")
      }

      function test_system_memory_remains_when_server_list_is_empty() {
        servers.clear()
        panel.revision++
        tryCompare(list, "count", 0)
        tryCompare(findChild(panel, "totalMemory"), "text", "16.00 GiB")
        tryCompare(findChild(panel, "trackedMemory"), "text", "—")
        waitForRendering(panel)
        check(findChild(panel, "otherMemorySegment").width > 0)
        check(findChild(panel, "freeMemorySegment").width > 0)
      }

      onCompletedChanged: if (completed) console.log("LOCALHOST_RESULT " + JSON.stringify({
        tests: executed, failed: qtest_results.failCount, skipped: qtest_results.skipCount
      }))
    }
  }
}
