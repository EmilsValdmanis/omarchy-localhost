"""Exercise missing executables against Quickshell's real Process object."""

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
class ProcessStartTests(unittest.TestCase):
    def test_missing_discovery_and_qr_executables_complete(self):
        listener = 'LISTEN 0 511 127.0.0.1:5173 0.0.0.0:* users:(("node",pid=410,fd=22))'
        payload = json.dumps({"ok": True, "processes": [{"pid": 410, "uid": 1000,
            "startTime": 991, "command": "node app.js", "cwd": "/work/app"}]})
        for stage in ("source", "metadata", "probe", "docker-limit"):
            with self.subTest(stage=stage), tempfile.TemporaryDirectory(prefix="localhost-start-") as directory:
                root = Path(directory)
                (root / "Plugin").symlink_to(REPO / "qml", target_is_directory=True)
                binaries = root / "bin"
                binaries.mkdir()
                runtime = root / "runtime"
                runtime.mkdir(mode=0o700)
                if stage in ("metadata", "probe"):
                    ss = binaries / "ss"
                    ss.write_text("#!/bin/sh\nprintf '%s\\n' '" + listener + "'\n")
                    ss.chmod(0o755)
                if stage in ("probe", "docker-limit"):
                    python = binaries / "python3"
                    python.write_text("#!/bin/sh\nprintf '%s\\n' '" + payload + "'\n")
                    python.chmod(0o755)
                if stage == "docker-limit":
                    (binaries / "bash").symlink_to(shutil.which("bash"))
                    (binaries / "timeout").symlink_to(shutil.which("timeout"))
                    docker = binaries / "docker"
                    docker.write_text("#!/bin/sh\nprintf '%s\\n' '[\"abc123\",\"test\",\"node\",\"0.0.0.0:3000-4000->3000-4000/tcp\",\"\",\"\",\"\"]'\n")
                    docker.chmod(0o755)
                    curl = binaries / "curl"
                    curl.write_text("#!/bin/sh\nexit 0\n")
                    curl.chmod(0o755)
                qml = '''
import QtQuick
import Quickshell
import "Plugin" as Plugin
ShellRoot {
  Plugin.RadarDiscovery { id: discovery; currentUid: 1000; intervalSec: 60 }
  Plugin.QrService { id: qr }
  Component.onCompleted: {
    discovery.scan(); discovery.scan()
    qr.open('{"url":"http://127.0.0.1:3000"}')
  }
  Timer {
    interval: 1200; running: true
    onTriggered: {
      console.log("START_RESULT " + JSON.stringify({ scanning: discovery.scanning,
        error: discovery.scanError, warnings: discovery.warnings,
        loading: qr.loading, qrError: qr.error }))
      Qt.quit()
    }
  }
}
'''
                if stage == "docker-limit":
                    qml = qml.replace('id: discovery; currentUid:', 'id: discovery; source: "docker"; currentUid:')
                (root / "shell.qml").write_text(qml)
                env = dict(os.environ, PATH=str(binaries), QT_QPA_PLATFORM="offscreen",
                    QT_QPA_PLATFORMTHEME="", QT_QUICK_BACKEND="software", XDG_RUNTIME_DIR=str(runtime))
                env.pop("DISPLAY", None)
                env.pop("WAYLAND_DISPLAY", None)
                result = subprocess.run([QUICKSHELL, "-p", str(root), "--no-color"],
                    env=env, capture_output=True, text=True, timeout=15, check=True)
                output = result.stdout + result.stderr
                line = next((line for line in output.splitlines() if "START_RESULT " in line), "")
                self.assertTrue(line, output)
                state = json.loads(line.split("START_RESULT ", 1)[1])
                self.assertFalse(state["scanning"], output)
                self.assertFalse(state["loading"], output)
                self.assertEqual(state["qrError"], "Could not generate the QR code")
                if stage == "source":
                    self.assertTrue(state["error"], output)
                else:
                    self.assertTrue(state["warnings"], output)
                if stage == "probe":
                    self.assertIn("Could not start HTTP probes", state["warnings"])
                if stage == "docker-limit":
                    self.assertIn("Docker discovery is incomplete: published ports exceed the discovery limit", state["warnings"])


if __name__ == "__main__":
    unittest.main()
