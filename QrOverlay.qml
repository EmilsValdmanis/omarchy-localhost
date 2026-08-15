import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons

Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  property bool opened: false
  property bool loading: false
  property bool expectedStop: false
  property string projectName: "Localhost"
  property string framework: "Development server"
  property string url: ""
  property string error: ""
  property int qrSize: 0
  property var qrRows: []

  readonly property color onScrim: "#ffffff"
  readonly property color onScrimDim: Qt.rgba(1, 1, 1, 0.58)
  readonly property color onScrimUrgent: "#ff7070"
  readonly property bool showingQr: qrSize > 0 && !loading && error === ""
  readonly property string backendPath: manifest && manifest.__sourceDir
    ? String(manifest.__sourceDir) + "/scripts/radar.py"
    : decodeURIComponent(String(Qt.resolvedUrl("scripts/radar.py")).replace(/^file:\/\//, ""))

  function open(payloadJson) {
    var payload = {}
    try { payload = JSON.parse(payloadJson || "{}") || {} } catch (exception) {}
    projectName = String(payload.name || "Localhost")
    framework = String(payload.framework || "Development server")
    url = String(payload.url || "")
    error = ""
    qrSize = 0
    qrRows = []
    opened = true
    if (url === "") {
      error = "No LAN URL was provided"
      return
    }
    generate()
    Qt.callLater(function() {
      if (root.opened) keyCatcher.forceActiveFocus()
    })
  }

  function close() {
    opened = false
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

  function dismiss() {
    if (shell && typeof shell.hide === "function")
      shell.hide((manifest && manifest.id) || "emils.localhost")
    else close()
  }

  function generate() {
    if (qrProcess.running) {
      expectedStop = true
      qrProcess.running = false
    }
    expectedStop = false
    loading = true
    qrProcess.command = ["python3", backendPath, "qr", url]
    qrProcess.running = true
  }

  function applyQr(raw) {
    try {
      var payload = JSON.parse(String(raw || "{}"))
      var rows = Array.isArray(payload.rows) ? payload.rows : []
      var size = Number(payload.size || 0)
      if (size <= 0 || rows.length !== size) throw new Error("invalid matrix")
      qrRows = rows
      qrSize = size
      error = ""
    } catch (exception) {
      qrSize = 0
      qrRows = []
      error = "Could not read the QR code"
    }
  }

  Process {
    id: qrProcess

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (!root.expectedStop) root.applyQr(text)
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
      if (root.expectedStop) return
      if (exitCode !== 0 && root.error === "") root.error = "Could not generate the QR code"
    }
  }

  PanelWindow {
    visible: root.opened
    anchors { top: true; right: true; bottom: true; left: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "emils-localhost-qr"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    Rectangle {
      anchors.fill: parent
      color: Qt.rgba(0.025, 0.03, 0.035, 0.86)
      opacity: root.opened ? 1 : 0

      Behavior on opacity {
        NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
      }

      MouseArea {
        anchors.fill: parent
        onClicked: root.dismiss()
      }
    }

    Item {
      id: keyCatcher
      anchors.fill: parent
      focus: true
      Keys.onEscapePressed: root.dismiss()

      Item {
        anchors.centerIn: parent
        width: content.implicitWidth
        height: content.implicitHeight
        opacity: root.opened ? 1 : 0
        scale: root.opened ? 1 : 0.96

        Behavior on opacity {
          NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
        }
        Behavior on scale {
          NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
        }

        MouseArea { anchors.fill: parent; onClicked: function(mouse) { mouse.accepted = true } }

        ColumnLayout {
          id: content
          anchors.fill: parent
          spacing: Style.space(14)

          Text {
            Layout.alignment: Qt.AlignHCenter
            Layout.maximumWidth: Style.space(420)
            text: root.projectName.toUpperCase()
            color: root.onScrim
            font.family: Style.font.family
            font.pixelSize: Style.font.heading
            font.bold: true
            font.letterSpacing: 1.6
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignHCenter
          }

          Text {
            Layout.alignment: Qt.AlignHCenter
            text: root.framework + "  ·  AVAILABLE ON LAN"
            color: Color.accent
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            font.bold: true
            font.letterSpacing: 0.7
          }

          Item { Layout.preferredHeight: Style.space(2) }

          Rectangle {
            id: qrCanvas
            readonly property int moduleSize: root.qrSize > 0
              ? Math.max(5, Math.floor(Style.space(280) / root.qrSize))
              : 0

            visible: root.showingQr
            Layout.alignment: Qt.AlignHCenter
            width: root.qrSize * moduleSize
            height: width
            color: "white"
            radius: Style.cornerRadius

            Grid {
              anchors.fill: parent
              columns: root.qrSize

              Repeater {
                model: root.qrSize * root.qrSize

                Rectangle {
                  required property int index
                  readonly property int rowIndex: Math.floor(index / root.qrSize)
                  readonly property int columnIndex: index % root.qrSize
                  width: qrCanvas.moduleSize
                  height: qrCanvas.moduleSize
                  color: root.qrRows[rowIndex].charAt(columnIndex) === "1" ? "#101214" : "transparent"
                }
              }
            }
          }

          Text {
            visible: root.loading
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredHeight: Style.space(280)
            verticalAlignment: Text.AlignVCenter
            text: "Generating QR code…"
            color: root.onScrimDim
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }

          Text {
            visible: root.error !== ""
            Layout.alignment: Qt.AlignHCenter
            Layout.maximumWidth: Style.space(360)
            Layout.preferredHeight: Style.space(100)
            verticalAlignment: Text.AlignVCenter
            text: root.error
            color: root.onScrimUrgent
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            wrapMode: Text.Wrap
            horizontalAlignment: Text.AlignHCenter
          }

          Text {
            visible: root.showingQr
            Layout.alignment: Qt.AlignHCenter
            Layout.maximumWidth: Style.space(440)
            text: root.url
            color: root.onScrim
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            elide: Text.ElideMiddle
            horizontalAlignment: Text.AlignHCenter

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: Quickshell.execDetached(["wl-copy", root.url])
            }
          }

          Text {
            visible: root.showingQr
            Layout.alignment: Qt.AlignHCenter
            text: "Same Wi-Fi network required"
            color: root.onScrimDim
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
          }

          Text {
            Layout.alignment: Qt.AlignHCenter
            text: "ESC TO CLOSE"
            color: Qt.rgba(1, 1, 1, 0.34)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            font.letterSpacing: 1
          }
        }
      }
    }
  }
}
