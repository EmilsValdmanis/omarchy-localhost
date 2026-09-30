pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "RadarModel.js" as RadarModel

RowLayout {
  id: root
  property var server: null
  property int selectedActionIndex: 0
  property bool forceStopAvailable: false
  property color foreground: Color.popups.text
  signal actionHovered(int actionIndex)
  signal actionTriggered(int actionIndex)
  spacing: Style.space(3)

  Repeater {
    model: ["Open", "Copy local", "Copy LAN", "QR"]
    Button {
      required property int index
      required property string modelData
      objectName: "serverAction" + index
      text: modelData
      bordered: index === 0
      foreground: root.foreground
      enabled: RadarModel.actionEnabled(index, root.server)
      hasCursor: root.server !== null && root.selectedActionIndex === index
      fontSize: Style.font.caption
      horizontalPadding: Style.space(9)
      verticalPadding: Style.space(5)
      tooltipText: index === RadarModel.ACTIONS.qr ? "Share a LAN QR code"
        : (index === RadarModel.ACTIONS.copyLan ? "Copy LAN URL (Ctrl+Shift+C)"
        : (index === RadarModel.ACTIONS.copyLocal ? "Copy local URL (Ctrl+C)" : "Open local URL (Enter)"))
      onHovered: function(on) { if (on) root.actionHovered(index) }
      onClicked: root.actionTriggered(index)
    }
  }

  Item { Layout.fillWidth: true }

  Repeater {
    model: [
      { icon: "\uf120", tip: "Open terminal here" },
      { icon: "\uf121", tip: "Open in editor" },
      { icon: "\uf2f9", tip: "Restart server (Alt+R)" },
      { icon: root.forceStopAvailable ? "\uf714" : "\uf04d",
        tip: root.forceStopAvailable ? "Force stop server" : "Stop server (Delete)" }
    ]
    PanelActionButton {
      required property int index
      required property var modelData
      objectName: "serverAction" + (index + 4)
      iconText: modelData.icon
      tooltipText: index === 2 && root.server && !RadarModel.actionEnabled(RadarModel.ACTIONS.restart, root.server)
        ? root.server.restartReason : modelData.tip
      foreground: index === 3 ? Color.urgent : root.foreground
      hoverColor: index === 3 ? Color.urgent : Color.accent
      enabled: RadarModel.actionEnabled(index + 4, root.server)
      hasCursor: root.server !== null && root.selectedActionIndex === index + 4
      bordered: hasCursor
      onHovered: function(on) { if (on) root.actionHovered(index + 4) }
      onClicked: root.actionTriggered(index + 4)
    }
  }
}
