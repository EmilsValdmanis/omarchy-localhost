"""Exercise failed service subprocess starts with Quickshell's Process object."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parent.parent
QUICKSHELL = shutil.which("quickshell")


@unittest.skipUnless(QUICKSHELL, "Quickshell is not installed")
class ServiceProcessStartTests(unittest.TestCase):
    def test_missing_uid_route_and_resource_commands_report_failure(self):
        with tempfile.TemporaryDirectory(prefix="localhost-service-start-") as directory:
            root = Path(directory)
            (root / "Plugin").symlink_to(REPO / "qml", target_is_directory=True)
            (root / "bin").mkdir()
            runtime = root / "runtime"
            runtime.mkdir(mode=0o700)
            (root / "shell.qml").write_text('''
import QtQuick
import Quickshell
import "Plugin" as Plugin
ShellRoot {
  Plugin.RadarService { id: radar; includeDocker: false }
  Timer {
    interval: 300; running: true
    onTriggered: {
      radar.currentUid = 1000
      radar.systemMemory = { totalBytes: 100, availableBytes: 50 }
      radar.sampleResources(true)
    }
  }
  Timer {
    interval: 1000; running: true
    onTriggered: {
      console.log("SERVICE_RESULT " + JSON.stringify({ uidError: radar.uidError,
        routeWarning: radar.routeWarning, resourceWarning: radar.resourceWarning,
        total: radar.systemMemory.totalBytes }))
      Qt.quit()
    }
  }
}
''')
            env = dict(os.environ, PATH=str(root / "bin"), QT_QPA_PLATFORM="offscreen",
                       QT_QPA_PLATFORMTHEME="", QT_QUICK_BACKEND="software", XDG_RUNTIME_DIR=str(runtime))
            env.pop("DISPLAY", None)
            env.pop("WAYLAND_DISPLAY", None)
            result = subprocess.run([QUICKSHELL, "-p", str(root), "--no-color"], env=env,
                                    capture_output=True, text=True, timeout=15)
            output = result.stdout + result.stderr
            line = next((line for line in output.splitlines() if "SERVICE_RESULT " in line), "")
            self.assertTrue(line, output)
            state = json.loads(line.split("SERVICE_RESULT ", 1)[1])
            self.assertEqual(state, {"uidError": "Could not determine the current user",
                                     "routeWarning": "LAN route information is unavailable",
                                     "resourceWarning": "RAM sampling is unavailable", "total": -1})

    def test_missing_firewall_commands_clear_pending_actions(self):
        shell = Path(os.environ.get("OMARCHY_PATH", "/usr/share/omarchy")) / "shell"
        if not (shell / "Ui").is_dir():
            self.skipTest("Omarchy shell is not installed")
        with tempfile.TemporaryDirectory(prefix="localhost-firewall-start-") as directory:
            root = Path(directory)
            (root / "Plugin").symlink_to(REPO, target_is_directory=True)
            (root / "Commons").symlink_to(shell / "Commons", target_is_directory=True)
            ui = root / "Ui"
            ui.mkdir()
            for path in (shell / "Ui").iterdir():
                if path.name != "KeyboardPanel.qml":
                    (ui / path.name).symlink_to(path, target_is_directory=path.is_dir())
            # The real panel requires a Wayland layer-shell backend. Firewall
            # process handling does not depend on window behavior.
            (ui / "KeyboardPanel.qml").write_text('''
import QtQuick
Item {
  property var anchorItem; property var bar; property var owner; property var focusTarget
  property bool open: false; property int contentWidth; property int contentHeight
  function fittedContentWidth(value, limit) { return Math.min(value, limit) }
  function fittedContentHeight(value, limit) { return Math.min(value, limit) }
}
''')
            (root / "bin").mkdir()
            runtime = root / "runtime"
            runtime.mkdir(mode=0o700)
            (root / "shell.qml").write_text('''
import QtQuick
import Quickshell
import "Plugin" as Plugin
ShellRoot {
  Plugin.Widget { id: widget }
  Timer { interval: 300; running: true; onTriggered: widget.openQr({
    lanAvailable: true, lanInterface: "eth0", lanSubnet: "192.168.1.0/24", port: 3000 }) }
  Timer { interval: 600; running: true; onTriggered: {
    console.log("CHECK_RESULT " + JSON.stringify({pending: widget.pendingQrServer, notice: widget.notice,
      unreadable: widget.firewallRulesUnreadable}))
    widget.removeFirewallRule({interfaceName: "eth0", subnet: "192.168.1.0/24", port: 3000})
  } }
  Timer { interval: 1000; running: true; onTriggered: {
    console.log("REMOVE_RESULT " + JSON.stringify({pending: widget.pendingFirewallRule, notice: widget.notice}))
    widget.pendingQrServer = {lanInterface: "eth0", lanSubnet: "192.168.1.0/24", port: 3000}
    widget.authorizeQrPort()
  } }
  Timer { interval: 1400; running: true; onTriggered: {
    console.log("ALLOW_RESULT " + JSON.stringify({pending: widget.pendingQrServer, notice: widget.notice}))
    Qt.quit()
  } }
}
''')
            env = dict(os.environ, PATH=str(root / "bin"), QT_QPA_PLATFORM="offscreen",
                       QT_QPA_PLATFORMTHEME="", QT_QUICK_BACKEND="software", XDG_RUNTIME_DIR=str(runtime))
            env.pop("DISPLAY", None)
            env.pop("WAYLAND_DISPLAY", None)
            result = subprocess.run([QUICKSHELL, "-p", str(root), "--no-color"], env=env,
                                    capture_output=True, text=True, timeout=15)
            output = result.stdout + result.stderr
            def result_for(prefix):
                line = next((line for line in output.splitlines() if prefix in line), "")
                self.assertTrue(line, output[:5000])
                return json.loads(line.split(prefix, 1)[1])
            check = result_for("CHECK_RESULT ")
            self.assertEqual(check, {"pending": None, "notice": "Could not check LAN access", "unreadable": True})
            remove = result_for("REMOVE_RESULT ")
            self.assertEqual(remove, {"pending": None, "notice": "Could not remove the LAN access rule"})
            allow = result_for("ALLOW_RESULT ")
            self.assertEqual(allow, {"pending": None, "notice": "LAN access was not authorized"})


if __name__ == "__main__":
    unittest.main()
