import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Theme
import qs.Ui

CursorSurface {
  id: root
  property string title: ""
  property string detail: ""
  property string icon: ""
  property string trailingText: ""
  property bool wrapDetail: false
  property bool removable: false
  property bool includable: false
  property bool included: false
  property bool manuallySkipped: false
  property bool includeAvailable: true
  property string includeHint: ""
  property bool actionBusy: false
  signal removeRequested()
  signal includeRequested()

  implicitHeight: Math.max(labels.implicitHeight, Style.space(28)) + Style.space(14)
  Accessible.role: Accessible.StaticText
  Accessible.name: title + (trailingText ? ", " + trailingText : "") + ", " + detail

  TextMetrics {
    id: portMetrics
    font: titleText.font
    text: ":65535"
  }
  // Keep the measuring control logically visible: Button omits its label's
  // width when hidden. It cannot paint, take focus or receive pointer events.
  Button {
    id: includeSizeHint
    opacity: 0
    enabled: false
    Accessible.ignored: true
    text: "Included"
    iconText: "\uf00c"
    fontSize: Style.font.caption
    horizontalPadding: Style.space(7)
    verticalPadding: Style.space(5)
    focusable: true
  }

  RowLayout {
    anchors.fill: parent
    anchors.leftMargin: Style.space(8)
    anchors.rightMargin: Style.space(6)
    spacing: Style.space(9)
    PaintedGlyph {
      Layout.preferredWidth: Style.space(22)
      Layout.preferredHeight: Style.space(24)
      text: root.icon
      paintedSize: Style.space(16)
      color: Qt.darker(root.foreground, 1.4)
    }
    ColumnLayout {
      id: labels
      Layout.fillWidth: true
      spacing: Style.space(1)
      RowLayout {
        Layout.fillWidth: true
        spacing: Style.space(9)
        Text {
          id: titleText
          objectName: "detailTitle"
          Layout.alignment: Qt.AlignBaseline
          Layout.fillWidth: root.trailingText === ""
          Layout.preferredWidth: root.trailingText !== "" ? Math.ceil(portMetrics.advanceWidth) : implicitWidth
          text: root.title
          textFormat: Text.PlainText
          color: root.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          font.bold: true
          elide: Text.ElideRight
        }
        Text {
          id: trailingLabel
          objectName: "detailProcess"
          Layout.alignment: Qt.AlignBaseline
          Layout.fillWidth: true
          visible: root.trailingText !== ""
          text: root.trailingText
          textFormat: Text.PlainText
          color: Qt.darker(root.foreground, 1.4)
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }
      }
      Text {
        id: detailText
        Layout.fillWidth: true
        text: root.detail
        textFormat: Text.PlainText
        color: Qt.darker(root.foreground, 1.4)
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        wrapMode: root.wrapDetail ? Text.WordWrap : Text.NoWrap
        maximumLineCount: root.wrapDetail ? 2 : 1
        elide: Text.ElideRight
      }
    }
    Item {
      visible: root.includable
      implicitWidth: includeSizeHint.implicitWidth
      implicitHeight: includeButton.implicitHeight
      Button {
        id: includeButton
        objectName: "includePort"
        anchors.fill: parent
        text: root.included ? "Included" : (root.manuallySkipped ? "Unskip" : "Include")
        iconText: root.included ? "\uf00c" : (root.manuallySkipped ? "\uf0e2" : "\uf067")
        leftAlign: true
        foreground: root.foreground
        fontSize: Style.font.caption
        horizontalPadding: Style.space(7)
        verticalPadding: Style.space(5)
        enabled: root.includeAvailable && !root.included
        opacity: enabled ? 1 : 0.5
        focusable: true
        Accessible.name: text + " port " + root.title
        onClicked: root.includeRequested()
      }
      HoverHandler { id: includeHover }
      PanelToolTip {
        visible: includeHover.hovered && root.includeHint !== ""
        text: root.includeHint
        width: Math.min(implicitWidth, Style.space(300))
      }
    }
    Button {
      objectName: "removeRule"
      visible: root.removable
      text: "Remove"
      iconText: "\uf1f8"
      foreground: Theme.Color.urgent
      accent: Theme.Color.urgent
      fontSize: Style.font.caption
      horizontalPadding: Style.space(7)
      verticalPadding: Style.space(5)
      enabled: !root.actionBusy
      opacity: enabled ? 1 : 0.35
      focusable: true
      Accessible.name: "Remove LAN access rule for " + root.title
      onClicked: root.removeRequested()
    }
  }
  HoverHandler { id: rowHover }
  PanelToolTip {
    visible: rowHover.hovered && !includeHover.hovered && (titleText.truncated || detailText.truncated || trailingLabel.truncated)
    text: root.title + (root.trailingText ? " · " + root.trailingText : "") + "\n" + root.detail
    width: Math.min(implicitWidth, Style.space(360))
  }
}
