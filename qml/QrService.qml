import QtQuick
import "Qr.js" as Qr

// QR process state is independent of the Wayland overlay's window lifetime.
Item {
  id: root
  visible: false

  property bool opened: false
  property bool loading: false
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
    qrProcess.cancel()
    loading = false
    qrSize = 0
    qrRows = []
    error = ""
    url = ""
  }

  function generate() {
    loading = true
    error = ""
    if (qrProcess.busy) {
      pendingGenerate = true
      qrProcess.cancel()
      return
    }
    pendingGenerate = false
    qrProcess.start(["qrencode", "--type", "ASCII", "--margin", "4", "--output", "-", url])
  }

  function applyQr(raw) {
    var payload = Qr.parseQrAscii(raw)
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

  CommandProcess {
    id: qrProcess
    onCompleted: function(exitCode, failedToStart, canceled) {
      if (root.pendingGenerate && root.opened) { root.generate(); return }
      if (canceled || !root.opened) return
      root.loading = false
      if (exitCode === 0) root.applyQr(output)
      else root.error = errorOutput || "Could not generate the QR code"
    }
  }
}
