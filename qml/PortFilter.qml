pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Ui

Item {
  id: root
  property string value: "all"
  property var options: []
  property color foreground: Color.popups.text
  readonly property bool popupOpen: popup.visible
  signal changed(string value)
  implicitHeight: trigger.implicitHeight
  implicitWidth: Style.space(140)

  function close() { popup.close() }
  function currentOption() {
    for (let i = 0; i < options.length; i++)
      if (options[i].value === value) return options[i]
    return { label: value, icon: "" }
  }
  function choose(index) {
    if (index < 0 || index >= options.length) return
    popup.close()
    changed(options[index].value)
  }

  Button {
    id: trigger
    objectName: "portFilterTrigger"
    anchors.fill: parent
    text: root.currentOption().label
    iconText: root.currentOption().icon
    foreground: root.foreground
    bordered: true
    focusable: true
    hasCursor: popup.visible
    leftAlign: true
    horizontalPadding: Style.space(8)
    Accessible.role: Accessible.ComboBox
    Accessible.name: "Filter servers: " + text
    onClicked: popup.visible ? popup.close() : popup.open()
    Keys.onDownPressed: popup.open()
    OpticalGlyph {
      anchors.right: parent.right
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(10)
      height: width
      text: "›"
      paintedSize: Style.space(7)
      color: root.foreground
      rotation: popup.visible ? -90 : 90
    }

    Popup {
      id: popup
      objectName: "portFilterPopup"
      parent: trigger
      y: trigger.height + Style.space(4)
      width: trigger.width
      implicitHeight: optionsColumn.implicitHeight + padding * 2
      padding: Style.space(4)
      focus: true
      // A press on the trigger belongs to its toggle handler. Closing on every
      // outside press would close here, then reopen on the trigger's release.
      closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent
      background: BorderSurface {
        color: Color.popups.background
        borderSpec: Border.controlSpec("normal", root.foreground, Color.accent)
        radius: Style.cornerRadius
      }
      onOpened: {
        optionsColumn.currentIndex = Math.max(0, root.options.findIndex(function(option) { return option.value === root.value }))
        optionsColumn.forceActiveFocus()
      }
      onClosed: trigger.forceActiveFocus()
      contentItem: ColumnLayout {
        id: optionsColumn
        property int currentIndex: 0
        spacing: Style.space(2)
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Down || event.text === "j") {
            currentIndex = Math.min(root.options.length - 1, currentIndex + 1)
          } else if (event.key === Qt.Key_Up || event.text === "k") {
            currentIndex = Math.max(0, currentIndex - 1)
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
            root.choose(currentIndex)
          } else { return }
          event.accepted = true
        }
        Repeater {
          model: root.options
          Button {
            required property var modelData
            required property int index
            objectName: "portFilterOption" + index
            Layout.fillWidth: true
            text: modelData.label
            iconText: modelData.icon
            foreground: root.foreground
            leftAlign: true
            fontSize: Style.font.caption
            horizontalPadding: Style.space(7)
            verticalPadding: Style.space(7)
            hasCursor: optionsColumn.currentIndex === index
            Accessible.role: Accessible.ListItem
            Accessible.name: modelData.label
            Accessible.selected: root.value === modelData.value
            onHovered: function(on) { if (on) optionsColumn.currentIndex = index }
            onClicked: root.choose(index)
          }
        }
      }
    }
  }
}
