"""Exercise missing executables against Quickshell's real Process object."""

import json
import shutil
import unittest

from qml_runtime import QUICKSHELL, QmlRuntime, check_test_result


@unittest.skipUnless(QUICKSHELL, "Quickshell is not installed")
class ProcessStartTests(unittest.TestCase):
    def test_missing_discovery_and_qr_executables_complete(self):
        listener = 'LISTEN 0 511 127.0.0.1:5173 0.0.0.0:* users:(("node",pid=410,fd=22))'
        payload = json.dumps({"ok": True, "processes": [{"pid": 410, "uid": 1000,
            "startTime": 991, "command": "node app.js", "cwd": "/work/app"}]})
        for stage in ("source", "metadata", "probe", "docker-limit"):
            with self.subTest(stage=stage), QmlRuntime() as qml:
                qml.env["PATH"] = str(qml.bin)
                qml.env["LOCALHOST_START_STAGE"] = stage
                if stage in ("metadata", "probe"):
                    qml.command("ss", "printf '%s\\n' '" + listener + "'\n")
                if stage in ("probe", "docker-limit"):
                    qml.command("python3", "printf '%s\\n' '" + payload + "'\n")
                if stage == "docker-limit":
                    for command in ("bash", "timeout"):
                        (qml.bin / command).symlink_to(shutil.which(command))
                    qml.command("docker", "printf '%s\\n' '[\"abc123\",\"test\",\"node\",\"0.0.0.0:3000-4000->3000-4000/tcp\",\"\",\"\",\"\"]'\n")
                    qml.command("curl", "exit 0\n")
                result = qml.run('''
import QtQuick
import QtTest
import Quickshell
import "Plugin/qml" as Plugin
ShellRoot {
  Plugin.RadarDiscovery {
    id: discovery; currentUid: 1000; intervalSec: 60
    source: Quickshell.env("LOCALHOST_START_STAGE") === "docker-limit" ? "docker" : "process"
  }
  Plugin.QrService { id: qr }
  TestCase {
    name: "MissingDiscoveryCommands"
    when: true
    function test_commands_finish() {
      discovery.scan(); discovery.scan()
      qr.open('{"url":"http://127.0.0.1:3000"}')
      tryVerify(function() { return !discovery.scanning && !discovery.scanQueued }, 5000)
      tryCompare(qr, "loading", false)
      compare(qr.error, "Could not generate the QR code")
      var stage = Quickshell.env("LOCALHOST_START_STAGE")
      if (stage === "source") verify(discovery.scanError !== "")
      else verify(discovery.warnings.length > 0)
      if (stage === "probe") verify(discovery.warnings.indexOf("Could not start HTTP probes") !== -1)
      if (stage === "docker-limit") verify(discovery.warnings.indexOf(
        "Docker discovery is incomplete: published ports exceed the discovery limit") !== -1)
    }
    onCompletedChanged: if (completed) console.log("START_TEST_RESULT " + JSON.stringify({
      tests: 1, failed: qtest_results.failCount, skipped: qtest_results.skipCount
    }))
  }
}
''')
                check_test_result(result, "START_TEST_RESULT", 1)


if __name__ == "__main__":
    unittest.main()
