import QtQuick
import QtQuick.Layouts
import qs.Commons

ColumnLayout {
  id: root

  required property var qrState
  readonly property string projectName: qrState.projectName
  readonly property string framework: qrState.framework
  readonly property string url: qrState.url
  readonly property string error: qrState.error
  readonly property int qrSize: qrState.qrSize
  readonly property var qrRows: qrState.qrRows
  readonly property bool loading: qrState.loading
  readonly property bool showingQr: qrState.showingQr
  readonly property color onScrim: "#ffffff"
  readonly property color onScrimDim: Qt.rgba(1, 1, 1, 0.58)
  readonly property color onScrimUrgent: "#ff7070"
  signal copyRequested()
  spacing: Style.space(14)

  Text {
    textFormat: Text.PlainText
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
    textFormat: Text.PlainText
    Layout.alignment: Qt.AlignHCenter
    text: root.framework + "  ·  AVAILABLE ON LAN"
    color: Color.accent
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    font.bold: true
    font.letterSpacing: 0.7
  }

  Item { Layout.preferredHeight: Style.space(2) }

  QrCode {
    visible: root.showingQr
    Layout.alignment: Qt.AlignHCenter
    rows: root.qrRows
    moduleSize: root.qrSize > 0
      ? Math.max(1, Math.floor(Style.space(280) / root.qrSize)) : 1
  }

  Text {
    textFormat: Text.PlainText
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
    textFormat: Text.PlainText
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
    textFormat: Text.PlainText
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
      onClicked: root.copyRequested()
    }
  }

  Text {
    textFormat: Text.PlainText
    visible: root.showingQr
    Layout.alignment: Qt.AlignHCenter
    text: "Same Wi-Fi network required"
    color: root.onScrimDim
    font.family: Style.font.family
    font.pixelSize: Style.font.bodySmall
  }

  Text {
    textFormat: Text.PlainText
    Layout.alignment: Qt.AlignHCenter
    text: "ESC TO CLOSE"
    color: Qt.rgba(1, 1, 1, 0.34)
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    font.letterSpacing: 1
  }
}
