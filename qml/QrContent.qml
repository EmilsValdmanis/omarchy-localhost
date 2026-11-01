import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

Item {
  id: root
  required property var qrState
  readonly property string projectName: qrState.projectName
  readonly property string url: qrState.url
  readonly property string error: qrState.error
  readonly property int qrSize: qrState.qrSize
  readonly property var qrRows: qrState.qrRows
  readonly property bool loading: qrState.loading
  readonly property bool showingQr: qrState.showingQr
  // The overlay keeps a dark scrim even when the desktop uses a light theme.
  readonly property color foreground: "#ffffff"
  readonly property color muted: Qt.rgba(1, 1, 1, 0.65)
  property bool copied: false
  signal copyRequested()
  signal closeRequested()
  signal retryRequested()

  implicitWidth: Style.space(340)
  implicitHeight: content.implicitHeight

  function copyUrl() {
    if (!url) return
    copyRequested()
    copied = true
    copiedTimer.restart()
  }
  onUrlChanged: { copied = false; copiedTimer.stop() }
  Timer { id: copiedTimer; interval: 1800; onTriggered: root.copied = false }

  Keys.onPressed: function(event) {
    if (event.key === Qt.Key_Escape) {
      root.closeRequested()
      event.accepted = true
    } else if (event.key === Qt.Key_C && (event.modifiers & Qt.ControlModifier)) {
      root.copyUrl()
      event.accepted = true
    }
  }

  ColumnLayout {
    id: content
    anchors.fill: parent
    spacing: Style.space(14)

    Item {
      Layout.fillWidth: true
      implicitHeight: titleRow.implicitHeight
      RowLayout {
        id: titleRow
        anchors.centerIn: parent
        width: Math.min(projectLabel.implicitWidth + Style.space(28), parent.width)
        spacing: Style.space(8)
        InlineIcon {
          Layout.preferredWidth: Style.space(20)
          label: projectLabel
          text: "\uf029"
          color: root.foreground
          paintedSize: Style.space(16)
        }
        Text {
          id: projectLabel
          objectName: "qrProjectName"
          Layout.fillWidth: true
          text: root.projectName
          textFormat: Text.PlainText
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          font.bold: true
          color: root.foreground
          elide: Text.ElideMiddle
        }
      }
    }

    QrCode {
      id: code
      objectName: "sharingQrCode"
      visible: root.showingQr
      Layout.alignment: Qt.AlignHCenter
      rows: root.qrRows
      moduleSize: root.qrSize > 0
        ? Math.max(1, Math.floor(Math.min(Style.space(280), root.width) / root.qrSize)) : 1
    }

    Text {
      visible: root.loading
      Layout.fillWidth: true
      Layout.preferredHeight: Style.space(240)
      text: "Generating QR code…"
      color: root.muted
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      horizontalAlignment: Text.AlignHCenter
      verticalAlignment: Text.AlignVCenter
    }

    RowLayout {
      visible: root.error !== ""
      Layout.fillWidth: true
      spacing: Style.space(8)
      OpticalGlyph {
        Layout.preferredWidth: Style.space(18)
        Layout.preferredHeight: Style.space(18)
        text: "\uf071"
        color: Color.urgent
        paintedSize: Style.space(14)
      }
      Text {
        Layout.fillWidth: true
        text: root.error
        textFormat: Text.PlainText
        color: Color.urgent
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        wrapMode: Text.WordWrap
      }
      Button {
        objectName: "retryQr"
        iconText: "\uf2f9"
        foreground: root.foreground
        enabled: root.url !== "" && !root.loading
        tooltipText: "Retry QR generation"
        focusable: true
        Accessible.name: "Retry QR generation"
        onClicked: root.retryRequested()
      }
    }

    RowLayout {
      visible: root.url !== ""
      Layout.alignment: Qt.AlignHCenter
      Layout.fillWidth: false
      Layout.preferredWidth: Math.min(urlText.implicitWidth + copyButton.implicitWidth + spacing, root.width)
      Layout.maximumWidth: Layout.preferredWidth
      spacing: Style.space(6)
      Text {
        id: urlText
        objectName: "qrLanUrl"
        Layout.fillWidth: true
        text: root.url
        textFormat: Text.PlainText
        color: root.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        elide: Text.ElideMiddle
        HoverHandler { id: urlHover }
        PanelToolTip {
          visible: urlHover.hovered && urlText.truncated
          text: root.url
          width: Math.min(implicitWidth, Style.space(320))
        }
      }
      Button {
        id: copyButton
        objectName: "copyQrLan"
        iconText: root.copied ? "\uf00c" : "\uf0c5"
        foreground: root.foreground
        fontSize: Style.font.caption
        horizontalPadding: Style.space(7)
        verticalPadding: Style.space(5)
        tooltipText: "Copy LAN URL (Ctrl+C)"
        focusable: true
        Accessible.name: "Copy LAN URL"
        onClicked: root.copyUrl()
      }
    }

  }
}
