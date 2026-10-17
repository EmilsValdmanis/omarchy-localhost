pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

CursorSurface {
  id: header
  required property string projectRoot
  required property string name
  required property int count
  property bool collapsed: false
  property bool selected: false
  property bool actionBusy: false
  property bool stopping: false

  signal toggled()
  signal focused()
  signal stopRequested()
  signal navigationKey(var event)

  objectName: "projectHeader"
  implicitHeight: Style.space(30)
  hasCursor: selected
  activeFocusOnTab: true
  onActiveFocusChanged: if (activeFocus) focused()
  Keys.onPressed: function(event) { header.navigationKey(event) }

  Accessible.role: Accessible.Button
  Accessible.name: name + ", " + count + " server" + (count === 1 ? "" : "s")
  Accessible.description: projectRoot + " · " + (collapsed ? "Collapsed" : "Expanded")
  Accessible.checkable: true
  Accessible.checked: !collapsed
  Accessible.focusable: true
  Accessible.focused: selected
  Accessible.onPressAction: toggled()

  HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
  TapHandler { onTapped: header.toggled() }
  PanelToolTip {
    visible: hover.hovered && !stopHover.hovered
    text: (header.collapsed ? "Expand" : "Collapse") + " " + header.projectRoot
      + " · Enter / Space · h/l fold · J/K switch project"
  }

  RowLayout {
    anchors.fill: parent
    anchors.leftMargin: Style.space(8)
    anchors.rightMargin: Style.space(10)
    spacing: Style.space(8)
    Text {
      Layout.preferredWidth: Style.space(12)
      textFormat: Text.PlainText
      text: "›"
      rotation: header.collapsed ? 0 : 90
      color: header.selected ? Color.accent : Qt.darker(header.foreground, 1.4)
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      horizontalAlignment: Text.AlignHCenter
    }
    PanelSectionHeader {
      Layout.fillWidth: true
      Layout.alignment: Qt.AlignBaseline
      // Section labels reserve extra top padding for clipped list headings.
      // This row already has vertical space; keep its label on the count's baseline.
      topPadding: 0
      text: header.name
      foreground: header.selected ? Color.accent : header.foreground
      elide: Text.ElideMiddle
    }
    Text {
      Layout.alignment: Qt.AlignBaseline
      textFormat: Text.PlainText
      text: header.count
      color: Qt.darker(header.foreground, 1.4)
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }
    PanelActionButton {
      objectName: "projectStopAll"
      iconText: header.stopping ? "\uf251" : "\uf04d"
      foreground: Color.urgent
      hoverColor: Color.urgent
      enabled: !header.actionBusy
      focusable: true
      tooltipText: header.stopping ? "Stopping all servers in " + header.projectRoot
        : "Stop all servers in " + header.projectRoot
          + " in one click, including folded or filtered servers"
      Accessible.role: Accessible.Button
      Accessible.name: (header.stopping ? "Stopping all servers in " : "Stop all servers in ") + header.name
      Accessible.onPressAction: if (enabled) header.stopRequested()
      onClicked: header.stopRequested()
      HoverHandler { id: stopHover }
    }
  }
}
