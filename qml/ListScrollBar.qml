import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Commons as Theme

// The containing list reserves this track; it never overlays a row or leaves
// the panel's pointer bounds. Only the thumb is visually narrow.
ScrollBar {
  id: root
  property color foreground: Theme.Color.popups.text
  width: Style.space(10)
  padding: 0
  minimumSize: Math.min(1, Style.space(24) / Math.max(1, height))
  policy: ScrollBar.AsNeeded
  interactive: true
  visible: size < 1
  contentItem: Item {
    Rectangle {
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      width: Style.space(3)
      radius: width / 2
      color: root.foreground
      opacity: root.pressed || root.hovered ? 0.65 : 0.3
    }
  }
}
