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
  objectName: "composeDependencyTooltip"
  x: 0
  width: Style.space(232)
  padding: Style.space(12)
  text: "Compose dependencies\n" + (details || "No declared dependencies")

  component Caption: Text {
    textFormat: Text.PlainText
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    color: tooltip.panelForeground
  }

  contentItem: ColumnLayout {
    spacing: Style.space(5)
    Caption {
      text: "Compose dependencies"
      font.pixelSize: Style.font.body
      font.bold: true
      Layout.bottomMargin: Style.space(2)
    }
    Caption {
      visible: tooltip.details === ""
      text: "No declared dependencies"
    }
    Repeater {
      model: tooltip.visible ? Compose.tooltipRows(tooltip.details) : []
      RowLayout {
        id: dependency
        required property var modelData
        Layout.fillWidth: true
        spacing: Style.space(12)
        Caption {
          objectName: "dependencyName"
          Layout.fillWidth: true
          text: dependency.modelData.name
          wrapMode: Text.WrapAnywhere
          font.pixelSize: Style.font.bodySmall
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
