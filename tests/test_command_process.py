"""Check command completion, cancellation and reuse with real subprocesses."""

import sys
import unittest

from qml_runtime import QUICKSHELL, QmlRuntime, check_test_result


@unittest.skipUnless(QUICKSHELL, "Quickshell is not installed")
class CommandProcessTests(unittest.TestCase):
    def test_failed_start_streams_cancel_and_immediate_restarts(self):
        with QmlRuntime() as qml:
            qml.env["LOCALHOST_PYTHON"] = sys.executable
            result = qml.run('''
import QtQuick
import QtTest
import Quickshell
import "Plugin/qml" as Plugin
ShellRoot {
  Plugin.CommandProcess {
    id: command
    onCompleted: function(exitCode, failedToStart, canceled) {
      tests.results.push({ code: exitCode, failed: failedToStart, canceled: canceled,
        output: output.trim(), error: errorOutput })
      var count = tests.results.length
      if (count === 1) start([Quickshell.env("LOCALHOST_PYTHON"), "-c",
        "import sys; print('good'); print('error', file=sys.stderr)"])
      else if (count === 2) start([Quickshell.env("LOCALHOST_PYTHON"), "-c", "import time; time.sleep(30)"])
      else if (count < 20) start([Quickshell.env("LOCALHOST_PYTHON"), "-c", "print('latest')"])
    }
  }
  TestCase {
    id: tests
    name: "CommandProcessLifecycle"
    when: true
    property var results: []
    function test_lifecycle() {
      verify(command.start(["/nonexistent/localhost-command"]))
      tryVerify(function() { return results.length >= 2 && command.processId > 0 })
      compare(command.start(["/nonexistent/should-not-replace-a-running-command"]), false)
      command.cancel()
      tryVerify(function() { return results.length >= 20 }, 10000)
      compare(results.length, 20, "each launch completes exactly once")
      compare(command.busy, false)
      compare(results[0].failed, true)
      compare(results[0].output, "")
      compare(results[0].error, "")
      compare(results[1].code, 0)
      compare(results[1].failed, false)
      compare(results[1].canceled, false)
      compare(results[1].output, "good")
      compare(results[1].error, "error")
      compare(results[2].canceled, true)
      for (var i = 3; i < results.length; i++) {
        compare(results[i].code, 0)
        compare(results[i].failed, false)
        compare(results[i].canceled, false)
        compare(results[i].output, "latest")
        compare(results[i].error, "", "stderr from a previous command is cleared")
      }
    }
    onCompletedChanged: if (completed) console.log("COMMAND_TEST_RESULT " + JSON.stringify({
      tests: 1, failed: qtest_results.failCount, skipped: qtest_results.skipCount
    }))
  }
}
''')
            check_test_result(result, "COMMAND_TEST_RESULT", 1)


if __name__ == "__main__":
    unittest.main()
