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
      Component { id: serviceComponent; PluginUi.RadarService { includeDocker: false } }
      Component { id: overlayComponent; PluginUi.QrService {} }

      SignalSpy { id: openSpy; signalName: "openRequested" }
      SignalSpy { id: stopSpy; signalName: "stopRequested" }
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

      function test_keyboard_navigation_actions_and_confirmation() {
        panel.focusNavigation()
        wait(50)
        keyClick(Qt.Key_K)
        settled()
        equal(panel.selectedIndex, 49)
        check(list.atYEnd)
        keyClick(Qt.Key_J)
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
        equal(panel.selectedActionIndex, RadarModel.ACTIONS.terminal, "skip LAN copy and QR for localhost-only servers")
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

      function test_local_and_lan_copy_actions_and_shortcuts() {
        panel.selectedIndex = 0
        var local = findChild(panel, "serverAction1")
        var lan = findChild(panel, "serverAction2")
        equal(local.text, "Copy local")
        equal(lan.text, "Copy LAN")
        mouseClick(local, local.width / 2, local.height / 2)
        equal(copySpy.count, 1)
        equal(copySpy.signalArguments[0][0].localUrl, "http://localhost:3000")
        mouseClick(lan, lan.width / 2, lan.height / 2)
        equal(copyLanSpy.count, 1)
        equal(copyLanSpy.signalArguments[0][0].lanUrl, "http://192.168.1.2:3000")
        panel.focusNavigation()
        keyClick(Qt.Key_C, Qt.ControlModifier)
        equal(copySpy.count, 2)
        keyClick(Qt.Key_C, Qt.ControlModifier | Qt.ShiftModifier)
        equal(copyLanSpy.count, 2)
        panel.selectedIndex = 1
        equal(lan.enabled, false)
        keyClick(Qt.Key_C, Qt.ControlModifier | Qt.ShiftModifier)
        equal(copyLanSpy.count, 2, "LAN copy is disabled for a loopback-only server")
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
        keyClick(Qt.Key_L)
        tryCompare(list, "count", 9)
        equal(panel.selectedProjectRoot, "/work/console", "right expands before entering")
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
        equal(panel.selectedProjectRoot, "/work/tools", "project jumps wrap")
        keyClick(Qt.Key_Down, Qt.ControlModifier)
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
        equal(panel.selectedProjectRoot, "/work/tools")
        keyClick(Qt.Key_J)
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
        keyClick(Qt.Key_L)
        tryCompare(list, "count", 12)
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
        equal(panel.selectedProjectRoot, "/work/tools", "K wraps to the last project")
        keyClick(Qt.Key_J, Qt.ShiftModifier)
        equal(panel.selectedProjectRoot, "/work/atlas")
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
        failedCache[server.serverId] = { scheme: "", attempts: 2, expiresAt: Date.now() + 15000 }
        findChild(service, "nativeDiscovery").probeCache = failedCache
        service.servers.clear()
        service.refresh()
        tryVerify(function() { return detected() !== null }, 5000,
          "manual refresh discovers a ready server despite a cached failed probe")
        service.stop(server)
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

      function test_visual_capture() {
        RadarModel.syncServerModel(servers, fixtures(7))
        panel.revision++
        wait(200)
        var path = Quickshell.env("LOCALHOST_TEST_ARTIFACTS")
        if (path) {
          grabImage(panel).save(path + "/server-panel.png")
        }
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
        var barPixels = grabImage(memoryBar)
        check(barPixels.red(0, 0) !== barPixels.red(0, Math.floor(barPixels.height / 2)),
          "the colored left end follows the rounded outline")
        check(barPixels.red(barPixels.width - 1, 0)
          !== barPixels.red(barPixels.width - 1, Math.floor(barPixels.height / 2)),
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
