pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.Commons
import "RadarModel.js" as RadarModel

RowLayout {
  id: root
  property var server: null
  property int selectedActionIndex: 0
  property bool keyboardHints: false
  property bool forceStopAvailable: false
  property bool actionBusy: false
  property color foreground: Color.popups.text
  signal actionHovered(int actionIndex)
  signal actionTriggered(int actionIndex)
  spacing: Style.space(3)

  function available(action) {
    return RadarModel.actionEnabled(action, server)
      && (!actionBusy || (action !== RadarModel.ACTIONS.restart && action !== RadarModel.ACTIONS.stop))
  }

  function hint(action, normalHint) {
    if (!server) return "Select a server first."
    if (available(action)) return normalHint
    if (action === RadarModel.ACTIONS.qr) return RadarModel.lanUnavailableReason(server)
    if (action === RadarModel.ACTIONS.terminal || action === RadarModel.ACTIONS.project)
      return "The project directory is unavailable for this server."
    if (actionBusy) return "Another server action is in progress."
    return server.restartReason || "The restart command could not be verified."
  }

  Repeater {
    model: [
      { label: "Open", icon: "\uf08e", action: RadarModel.ACTIONS.open, tip: "Open local URL (Enter)" },
      { label: "Copy", icon: "\uf0c5", action: RadarModel.ACTIONS.copyLocal, tip: "Copy local URL (Ctrl+C)" },
      { label: "QR", icon: "\uf029", action: RadarModel.ACTIONS.qr, tip: "" }
    ]
    ToolbarAction {
      required property var modelData
      actionIndex: modelData.action
      text: modelData.label
      icon: modelData.icon
      foreground: root.foreground
      available: root.available(actionIndex)
      selected: root.server !== null && root.selectedActionIndex === actionIndex
      keyboardHint: root.keyboardHints
      hint: root.hint(actionIndex, modelData.tip)
      onHovered: root.actionHovered(actionIndex)
      onTriggered: root.actionTriggered(actionIndex)
    }
  }

  Item { Layout.fillWidth: true }

  Repeater {
    model: [
      { action: RadarModel.ACTIONS.terminal, icon: "\uf120", tip: "Open terminal here" },
      { action: RadarModel.ACTIONS.project, icon: "\uf121", tip: "Open in editor" },
      { action: RadarModel.ACTIONS.restart, icon: "\uf2f9", tip: "Restart server (Alt+R)" },
      { action: RadarModel.ACTIONS.skip, icon: "\uf05e", tip: "Skip this port without stopping it. Restore it from Skipped." },
      { action: RadarModel.ACTIONS.stop, icon: root.forceStopAvailable ? "\uf714" : "\uf04d",
        tip: root.forceStopAvailable ? "Force stop server (Delete)" : "Stop server (Delete)" }
    ]
    ToolbarAction {
      required property var modelData
      actionIndex: modelData.action
      icon: modelData.icon
      hint: root.hint(actionIndex, modelData.tip)
      foreground: actionIndex === RadarModel.ACTIONS.stop ? Color.urgent : root.foreground
      accent: actionIndex === RadarModel.ACTIONS.stop ? Color.urgent : Color.accent
      available: root.available(actionIndex)
      selected: root.server !== null && root.selectedActionIndex === actionIndex
      keyboardHint: root.keyboardHints
      onHovered: root.actionHovered(actionIndex)
      onTriggered: root.actionTriggered(actionIndex)
    }
  }

}
