import QtQuick
import qs.Commons
import qs.Commons as Theme
import "Motion.js" as Motion

Item {
  id: root
  required property Flickable view
  property color background: Theme.Color.popups.background
  Rectangle {
    objectName: "topScrollFade"
    opacity: root.view.visible && !root.view.atYBeginning ? 1 : 0
    visible: opacity > 0
    Behavior on opacity {
      NumberAnimation { duration: Motion.duration(Style, 160); easing.type: Easing.OutCubic }
    }
    anchors.top: parent.top
    width: parent.width
    height: Math.min(Style.space(14), parent.height / 3)
    gradient: Gradient {
      GradientStop { position: 0; color: root.background }
      GradientStop { position: 1; color: "transparent" }
    }
  }
  Rectangle {
    objectName: "bottomScrollFade"
    opacity: root.view.visible && !root.view.atYEnd ? 1 : 0
    visible: opacity > 0
    Behavior on opacity {
      NumberAnimation { duration: Motion.duration(Style, 160); easing.type: Easing.OutCubic }
    }
    anchors.bottom: parent.bottom
    width: parent.width
    height: Math.min(Style.space(14), parent.height / 3)
    gradient: Gradient {
      GradientStop { position: 0; color: "transparent" }
      GradientStop { position: 1; color: root.background }
    }
  }
}
