import QtQuick
import QtTest
import Quickshell
import qs.Commons
import "Plugin" as Plugin
import "Plugin/RadarModel.js" as RadarModel

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
      Component { id: panelComponent; Plugin.ServerPanel { width: 500; height: 560 } }
      Component { id: qrComponent; Plugin.QrCode {} }
      Component { id: serviceComponent; Plugin.RadarService { includeDocker: false } }
      Component { id: overlayComponent; Plugin.QrService {} }

      SignalSpy { id: openSpy; signalName: "openRequested" }
      SignalSpy { id: stopSpy; signalName: "stopRequested" }

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
        for (var i = 0; i < count; i++) rows.push(RadarModel.normalizeServer({
          serverId: "server-" + i, name: "Project " + i,
          framework: "Vite", frameworkId: "vite", port: 3000 + i,
          pid: 1000 + i, startTime: 100, cwd: "/tmp/project-" + i,
          projectRoot: "/tmp/fixtures",
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
        panel = createTemporaryObject(panelComponent, tests, { servers: servers })
        check(panel !== null)
        list = findChild(panel, "serverList")
        check(list !== null)
        openSpy.target = panel
        stopSpy.target = panel
        openSpy.clear()
        stopSpy.clear()
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
        equal(panel.selectedActionIndex, 3, "skip QR for localhost-only servers")
        check(!panel.actionEnabled(3, { cwd: "" }))
        check(!panel.actionEnabled(4, { cwd: "" }))
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

        var stop = findChild(panel, "serverAction6")
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
        var rows = fixtures(6)
        for (var i = 0; i < rows.length; i++) {
          rows[i].projectRoot = i % 2 ? "/work/console" : "/work/atlas"
          rows[i].projectPath = "apps/" + rows[i].name
        }
        RadarModel.syncServerModel(servers, rows)
        panel.revision++
        tryCompare(list, "count", 6)
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
        tryCompare(list, "count", 3)
        equal(panel.projectCount, 1)
        panel.selectedIndex = 0
        equal(findChild(panel, "serverAction2").enabled, false)
        settled()
        verifyViewport()
      }

      function test_live_discovery_and_verified_stop() {
        var port = Number(Quickshell.env("LOCALHOST_TEST_PORT"))
        check(port > 0, "runner provides a loopback HTTP fixture")
        var secondPort = Number(Quickshell.env("LOCALHOST_TEST_SECOND_PORT"))
        var service = createTemporaryObject(serviceComponent, tests, { alwaysIncludePorts: port + "," + secondPort })
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
        // Only the disposable fixture is eligible for this integration action.
        equal(server.pid, Number(Quickshell.env("LOCALHOST_TEST_PID")))
        service.stop(server)
        tryVerify(function() { return detected() === null }, 10000, "verified stop removes the server")
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
        if (path) grabImage(panel).save(path + "/server-panel.png")
      }

      onCompletedChanged: if (completed) console.log("LOCALHOST_RESULT " + JSON.stringify({
        tests: executed, failed: qtest_results.failCount, skipped: qtest_results.skipCount
      }))
    }
  }
}
