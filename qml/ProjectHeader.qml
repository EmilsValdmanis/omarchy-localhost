pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Theme
import "Motion.js" as Motion
import qs.Ui

CursorSurface {
  id: header
  required property string projectRoot
  required property string name
  required property int count
  property bool collapsed: false
  property bool selected: false
  property bool stopSelected: false
  property bool actionBusy: false
  property bool stopping: false
  property bool showStopAction: true
  property string countNoun: "server"

  signal toggled()
  signal focused()
  signal stopRequested()
  signal stopFocused()
  signal navigationKey(var event)

  objectName: "projectHeader"
  implicitHeight: Style.space(30)
  hasCursor: selected && !stopSelected
  activeFocusOnTab: true
  onActiveFocusChanged: if (activeFocus) focused()
  Keys.onPressed: function(event) { header.navigationKey(event) }

  Accessible.role: Accessible.Button
  Accessible.name: name + ", " + count + " " + countNoun + (count === 1 ? "" : "s")
  Accessible.description: (projectRoot ? projectRoot + " · " : "") + (collapsed ? "Collapsed" : "Expanded")
  Accessible.checkable: true
  Accessible.checked: !collapsed
  Accessible.focusable: true
  Accessible.focused: selected && !stopSelected
  Accessible.onPressAction: toggled()

  HoverHandler { cursorShape: Qt.PointingHandCursor }
  TapHandler { onTapped: header.toggled() }

  RowLayout {
    anchors.fill: parent
    anchors.leftMargin: Style.space(8)
    anchors.rightMargin: Style.space(10)
    spacing: Style.space(8)
    PaintedGlyph {
      objectName: "projectChevron"
      Layout.preferredWidth: Style.space(12)
      Layout.preferredHeight: Style.space(12)
      Layout.alignment: Qt.AlignVCenter
      text: "›"
      paintedSize: Style.space(8)
      rotation: header.collapsed ? 0 : 90
      transformOrigin: Item.Center
      color: header.selected ? Theme.Color.accent : Qt.darker(header.foreground, 1.4)
      fontFamily: Style.font.family
      fontSize: Style.font.body
      Behavior on rotation {
        NumberAnimation {
          duration: Motion.duration(Style, 140)
          easing.type: Easing.OutCubic
        }
      }
    }
    PanelSectionHeader {
      objectName: "projectName"
      Layout.fillWidth: true
      Layout.alignment: Qt.AlignVCenter
      // Section labels reserve extra top padding for clipped list headings.
      // This row already has vertical space; center the label and count together.
      topPadding: 0
      text: header.name
      foreground: header.selected ? Theme.Color.accent : header.foreground
      elide: Text.ElideMiddle
    }
    PanelActionButton {
      objectName: "projectStopAll"
      visible: header.showStopAction
      Layout.alignment: Qt.AlignVCenter
      foreground: Theme.Color.urgent
      hoverColor: Theme.Color.urgent
      enabled: header.showStopAction && !header.actionBusy
      hasCursor: header.selected && header.stopSelected
      bordered: hasCursor
      focusable: true
      onActiveFocusChanged: if (activeFocus) header.stopFocused()
      tooltipText: header.stopping ? "Stopping project servers…" : "Stop all servers in this project"
      Accessible.role: Accessible.Button
      Accessible.name: (header.stopping ? "Stopping all servers in " : "Stop all servers in ") + header.name
      Accessible.focused: header.selected && header.stopSelected
      Accessible.onPressAction: if (enabled) header.stopRequested()
      onClicked: header.stopRequested()
      InlineIcon {
        objectName: "projectStopIcon"
        anchors.centerIn: parent
        anchors.alignWhenCentered: false
        anchors.verticalCenterOffset: countLabel.y + countLabel.height / 2 - (parent.y + parent.height / 2)
        width: Style.space(14)
        height: countLabel.implicitHeight
        label: countLabel
        text: header.stopping ? "\uf251" : "\uf04d"
        color: header.actionBusy ? Qt.darker(Theme.Color.urgent, 2) : Theme.Color.urgent
      }
    }
    Text {
      id: countLabel
      objectName: "projectCount"
      Layout.alignment: Qt.AlignVCenter
      textFormat: Text.PlainText
      text: header.count
      color: Qt.darker(header.foreground, 1.4)
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }
  }
}
