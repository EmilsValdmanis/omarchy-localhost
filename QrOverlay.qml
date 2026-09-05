import QtQuick
import Quickshell
import Quickshell.Wayland

Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  readonly property bool opened: qr.opened
  readonly property bool loading: qr.loading
  readonly property string projectName: qr.projectName
  readonly property string framework: qr.framework
  readonly property string url: qr.url
  readonly property string error: qr.error
  readonly property int qrSize: qr.qrSize
  readonly property var qrRows: qr.qrRows
  readonly property bool showingQr: qr.showingQr

  QrService { id: qr }

  function open(payloadJson) {
    qr.open(payloadJson)
    Qt.callLater(function() {
      if (root.opened) keyCatcher.forceActiveFocus()
    })
  }

  function close() { qr.close() }

  function dismiss() {
    if (shell && typeof shell.hide === "function")
      shell.hide((manifest && manifest.id) || "emils.localhost")
    else close()
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

        QrContent {
          id: content
          anchors.fill: parent
          qrState: qr
          onCopyRequested: Quickshell.execDetached(["wl-copy", root.url])
        }
      }
    }
  }
}
