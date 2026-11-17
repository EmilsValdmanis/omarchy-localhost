import QtQuick
import qs.Commons
import qs.Commons as Theme
import "Compose.js" as Compose

Rectangle {
  required property string dependencyStates
  objectName: "composeProblemDot"
  visible: Compose.hasProblem(dependencyStates)
  anchors.top: parent.top
  anchors.right: parent.right
  width: Style.space(8)
  height: width
  radius: width / 2
  color: Theme.Color.urgent
  border.width: 1
  border.color: Theme.Color.popups.background
  Accessible.ignored: true
}
