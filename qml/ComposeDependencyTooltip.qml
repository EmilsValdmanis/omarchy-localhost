pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Theme
import qs.Ui
import "Compose.js" as Compose

PanelToolTip {
  id: tooltip
  required property string details
  property string serviceName: ""
  objectName: "composeDependencyTooltip"
  x: parent ? (parent.width - width) / 2 : 0
  width: Math.min(implicitWidth, Style.space(232))
  padding: Style.space(8)
  text: "Docker Compose\n" + (details || "Service status unavailable")

  component Caption: Text {
    textFormat: Text.PlainText
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    color: tooltip.panelForeground
  }

  contentItem: ColumnLayout {
    spacing: Style.space(5)
    Caption {
      visible: tooltip.details === ""
      text: "Service status unavailable"
    }
    Repeater {
      objectName: "composeServiceRows"
      model: tooltip.visible ? Compose.tooltipRows(tooltip.details, tooltip.serviceName) : []
      RowLayout {
        id: dependency
        required property var modelData
        Layout.fillWidth: true
        spacing: Style.space(6)
        InlineIcon {
          label: nameLabel
          text: dependency.modelData.isOwner ? "\uf1b2" : "\uf0c1"
          color: dependency.modelData.isOwner ? Theme.Color.accent : tooltip.panelForeground
          Accessible.ignored: true
        }
        Caption {
          id: nameLabel
          objectName: "dependencyName"
          Layout.fillWidth: true
          Layout.rightMargin: Style.space(10)
          text: dependency.modelData.name
          Accessible.name: (dependency.modelData.isOwner ? "Service " : "Dependency ") + text
          wrapMode: Text.WrapAnywhere
          font.pixelSize: Style.font.bodySmall
          font.bold: dependency.modelData.isOwner
        }
        Rectangle {
          readonly property color tint: Compose.hasProblem(dependency.modelData.status)
            ? Theme.Color.urgent : (["healthy", "completed"].includes(dependency.modelData.status)
                ? Qt.hsla(0.36, 0.40, tooltip.panelForeground.hslLightness, 1) : tooltip.panelForeground)
          implicitWidth: badgeText.implicitWidth + Style.space(12)
          implicitHeight: badgeText.implicitHeight + Style.space(4)
          radius: Style.space(4)
          color: Qt.alpha(tint, 0.14)
          Caption {
            id: badgeText
            objectName: "dependencyStatus"
            anchors.centerIn: parent
            text: dependency.modelData.status
            color: parent.tint
          }
        }
      }
    }
  }
}
