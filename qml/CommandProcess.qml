import QtQuick
import Quickshell.Io

Process {
  id: root
  readonly property bool busy: awaitingCompletion
  property bool awaitingCompletion: false
  property bool completionQueued: false
  property bool cancelRequested: false
  property int completionExitCode: 0
  property bool completionFailedToStart: false
  property string output: ""
  property string errorOutput: ""

  signal completed(int exitCode, bool failedToStart, bool canceled)

  function start(args) {
    if (busy) return false
    output = ""
    errorOutput = ""
    cancelRequested = false
    if (args !== undefined) command = args
    awaitingCompletion = true
    running = true
    return true
  }

  function cancel() {
    if (!busy) return
    cancelRequested = true
    running = false
  }

  function finish(exitCode, failedToStart) {
    if (!awaitingCompletion || completionQueued) return
    completionQueued = true
    completionExitCode = exitCode
    completionFailedToStart = failedToStart
    // Complete after terminal Process signals and stream collectors settle, so
    // a caller may start its next command from the completion handler safely.
    completionTimer.start()
  }

  property Timer completionTimer: Timer {
    interval: 0
    onTriggered: {
      var canceled = root.cancelRequested
      root.awaitingCompletion = false
      root.completionQueued = false
      root.completed(root.completionExitCode, root.completionFailedToStart, canceled)
    }
  }

  stdout: StdioCollector {
    waitForEnd: true
    onStreamFinished: root.output = String(text || "")
  }
  stderr: StdioCollector {
    waitForEnd: true
    onStreamFinished: root.errorOutput = String(text || "").trim()
  }
  onExited: function(exitCode) { finish(exitCode, false) }
  // FailedToStart emits runningChanged without exited in Quickshell 0.3.1.
  onRunningChanged: if (!running && awaitingCompletion) finish(1, true)
}
