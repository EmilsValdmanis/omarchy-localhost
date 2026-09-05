import QtQuick
import Quickshell.Io
import "RadarModel.js" as RadarModel

// QR process state is independent of the Wayland overlay's window lifetime.
Item {
  id: root
  visible: false

  property bool opened: false
  property bool loading: false
  property bool expectedStop: false
  property bool pendingGenerate: false
  property string projectName: "Localhost"
  property string framework: "Development server"
  property string url: ""
  property string error: ""
  property int qrSize: 0
  property var qrRows: []

  readonly property bool showingQr: qrSize > 0 && !loading && error === ""
  function open(payloadJson) {
    close()
    var payload = {}
    try { payload = JSON.parse(payloadJson || "{}") || {} } catch (exception) {}
    projectName = String(payload.name || "Localhost")
    framework = String(payload.framework || "Development server")
    url = String(payload.url || "")
    opened = true
    if (url === "") {
      error = "No LAN URL was provided"
      return
    }
    generate()
  }

  function close() {
    opened = false
    pendingGenerate = false
    if (qrProcess.running) {
      expectedStop = true
      qrProcess.running = false
    }
    loading = false
    qrSize = 0
    qrRows = []
    error = ""
    url = ""
  }

  function generate() {
    if (qrProcess.running) {
      pendingGenerate = true
      expectedStop = true
      qrProcess.running = false
      return
    }
    pendingGenerate = false
    expectedStop = false
    loading = true
    qrProcess.command = ["qrencode", "--type", "ASCII", "--margin", "4", "--output", "-", url]
    qrProcess.running = true
  }

  function applyQr(raw) {
    var payload = RadarModel.parseQrAscii(raw)
    if (payload.size <= 0 || payload.rows.length !== payload.size) {
      qrSize = 0
      qrRows = []
      error = "Could not read the QR code"
      return
    }
    qrRows = payload.rows
    qrSize = payload.size
    error = ""
  }

  Process {
    id: qrProcess

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (root.opened && !root.expectedStop) root.applyQr(text)
    }

    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (root.expectedStop) return
        var detail = String(text || "").trim()
        if (detail !== "") root.error = detail
      }
    }

    onExited: function(exitCode) {
      root.loading = false
      if (root.expectedStop) {
        root.expectedStop = false
        if (root.pendingGenerate && root.opened) root.generate()
        return
      }
      if (exitCode !== 0 && root.error === "") root.error = "Could not generate the QR code"
    }
  }
}
