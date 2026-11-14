"""Exercise failed service subprocess starts with Quickshell's Process object."""

import unittest

from qml_runtime import OMARCHY_SHELL, QUICKSHELL, REPO, QmlRuntime, check_test_result


@unittest.skipUnless(QUICKSHELL, "Quickshell is not installed")
class ServiceProcessStartTests(unittest.TestCase):
    def test_missing_uid_route_and_resource_commands_report_failure(self):
        with QmlRuntime() as qml:
            qml.env["PATH"] = str(qml.bin)
            result = qml.run('''
import QtQuick
import QtTest
import Quickshell
import "Plugin/qml" as Plugin
ShellRoot {
  Plugin.RadarService { id: radar; includeDocker: false }
  TestCase {
    name: "MissingResourceCommands"
    when: true
    function test_commands_finish() {
      tryCompare(radar, "uidError", "Could not determine the current user")
      tryCompare(radar, "routeWarning", "LAN route information is unavailable")
      radar.currentUid = 1000
      radar.systemMemory = { totalBytes: 100, availableBytes: 50 }
      radar.sampleResources(true)
      tryCompare(radar, "resourceWarning", "RAM sampling is unavailable")
      compare(radar.systemMemory.totalBytes, -1)
    }
    onCompletedChanged: if (completed) console.log("SERVICE_TEST_RESULT " + JSON.stringify({
      tests: 1, failed: qtest_results.failCount, skipped: qtest_results.skipCount
    }))
  }
}
''')
            check_test_result(result, "SERVICE_TEST_RESULT", 1)

    def test_missing_firewall_commands_clear_pending_actions(self):
        with QmlRuntime() as qml:
            qml.env["PATH"] = str(qml.bin)
            result = qml.run('''
import QtQuick
import QtTest
import Quickshell
import "Plugin/qml" as Plugin
ShellRoot {
  Plugin.FirewallService { id: firewall }
  TestCase {
    id: tests
    name: "MissingFirewallCommands"
    when: true
    property string notice: ""
    Connections {
      target: firewall
      function onNoticeRequested(message, urgent) { tests.notice = message }
    }
    function test_commands_finish() {
      tryCompare(firewall, "rulesUnreadable", true)
      var server = { lanInterface: "eth0", lanSubnet: "192.168.1.0/24", port: 3000 }
      firewall.requestQr(server, true)
      tryCompare(tests, "notice", "Could not check LAN access")
      compare(firewall.pendingServer, null)
      compare(firewall.busy, false)
      firewall.remove({ interfaceName: "eth0", subnet: "192.168.1.0/24", port: 3000 })
      tryCompare(tests, "notice", "Could not remove the LAN access rule")
      compare(firewall.pendingRule, null)
      compare(firewall.mutationBusy, false)
      firewall.authorize(server)
      tryCompare(tests, "notice", "LAN access was not authorized")
      compare(firewall.pendingServer, null)
      compare(firewall.mutationBusy, false)
    }
    onCompletedChanged: if (completed) console.log("FIREWALL_TEST_RESULT " + JSON.stringify({
      tests: 1, failed: qtest_results.failCount, skipped: qtest_results.skipCount
    }))
  }
}
''')
            check_test_result(result, "FIREWALL_TEST_RESULT", 1)

    def test_port_choices_use_host_settings_and_report_rejected_saves(self):
        if not (OMARCHY_SHELL / "Ui").is_dir():
            self.skipTest("Omarchy shell is not installed")
        with QmlRuntime() as qml:
            qml.add_omarchy_imports(ui_overrides={"KeyboardPanel.qml": REPO / "tests/qml/KeyboardPanelStub.qml"})
            qml.env["PATH"] = str(qml.bin)
            result = qml.run('''
import QtQuick
import QtTest
import Quickshell
import "Plugin" as Plugin
ShellRoot {
  QtObject {
    id: host
    property bool vertical: false
    property int barSize: 28
    property color foreground: "white"
    property color barForeground: "white"
    property color background: "black"
    property color urgent: "red"
    property string fontFamily: "monospace"
    property bool foregroundAnimationEnabled: false
    function hideTooltip(owner) {}
    property var shell: settingsApi
  }
  QtObject {
    id: settingsApi
    property bool accepted: true
    property var saved: null
    property int calls: 0
    function updateEntryInline(id, next) {
      if (id !== "emils.localhost") throw new Error("Wrong plugin settings target")
      calls++
      saved = next
      return accepted
    }
  }
  Plugin.Widget {
    id: widget
    bar: host
    settings: ({ ignoredPorts: "3000-3010", alwaysIncludePorts: "", includeDocker: false })
  }
  TestCase {
    name: "HostPortSettings"
    when: true
    function test_host_save() {
      widget.setPortIncluded(3005, true)
      compare(settingsApi.saved.ignoredPorts, "3000-3004,3006-3010")
      compare(settingsApi.saved.alwaysIncludePorts, "3005")
      compare(settingsApi.saved.includeDocker, false)
      compare(settingsApi.calls, 1)
      compare(widget.settings.ignoredPorts, "3000-3010")
      compare(widget.noticeUrgent, false)
      verify(widget.notice.indexOf("Checking :3005") === 0)
      settingsApi.accepted = false
      widget.setPortIncluded(8000, false)
      compare(settingsApi.calls, 2)
      compare(widget.noticeUrgent, true)
      compare(widget.notice, "Could not save the port preference.")
      host.shell = null
      widget.setPortIncluded(8001, false)
      compare(widget.noticeUrgent, true)
      compare(widget.notice, "Could not save the port preference.")
      widget.setPortIncluded(0, false)
      compare(settingsApi.calls, 2)
    }
    onCompletedChanged: if (completed) console.log("HOST_SETTINGS_RESULT " + JSON.stringify({
      tests: 1, failed: qtest_results.failCount, skipped: qtest_results.skipCount
    }))
  }
}
''')
            check_test_result(result, "HOST_SETTINGS_RESULT", 1)


if __name__ == "__main__":
    unittest.main()
