import QtQuick
import qs.Commons
import qs.Commons as Theme
import qs.Ui

// An enabled hover surface around a possibly disabled action. The panel's
// keyboard cursor can inspect it without making the action executable.
Item {
  id: root
  property int actionIndex: 0
  property string text: ""
  property string icon: ""
  property string hint: ""
  property bool available: true
  property bool selected: false
  property bool keyboardHint: false
  property color foreground: Theme.Color.popups.text
  property color accent: Theme.Color.accent
  signal hovered()
  signal triggered()

  implicitHeight: button.implicitHeight
  implicitWidth: text ? button.implicitWidth : button.implicitHeight
  Button {
    id: button
    objectName: "serverAction" + root.actionIndex
    anchors.fill: parent
    text: root.text
    iconText: root.icon
    foreground: root.foreground
    accent: root.accent
    enabled: root.available
    opacity: enabled ? 1 : (root.selected ? 0.65 : 0.35)
    hasCursor: root.selected
    fontSize: Style.font.caption
    horizontalPadding: Style.space(7)
    verticalPadding: Style.space(5)
    Accessible.role: Accessible.Button
    Accessible.name: root.text || root.hint
    Accessible.description: root.hint
    Accessible.focused: root.selected && root.keyboardHint
    onClicked: root.triggered()
  }
  HoverHandler {
    id: hover
    onHoveredChanged: if (hovered && root.available) root.hovered()
  }
  PanelToolTip {
    objectName: "disabledActionTip" + root.actionIndex
    visible: root.visible && root.hint !== "" && (hover.hovered || (root.selected && root.keyboardHint))
    delay: root.selected && root.keyboardHint ? 0 : 400
    text: root.hint
    width: Math.min(implicitWidth, Style.space(300))
  }
}
