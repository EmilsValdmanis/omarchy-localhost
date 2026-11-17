pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Theme
import "Actions.js" as Actions

RowLayout {
  id: root
  property var server: null
  property int selectedActionIndex: 0
  property bool keyboardHints: false
  property bool forceStopAvailable: false
  property bool actionBusy: false
  property color foreground: Theme.Color.popups.text
  signal actionHovered(int actionIndex)
  signal actionTriggered(int actionIndex)
  spacing: Style.space(3)

  function available(action) {
    return Actions.actionEnabled(action, server, actionBusy)
  }

  function hint(action, normalHint) {
    if (!server) return "Select a server first."
    if (action === Actions.ACTIONS.skip && server.serviceKey)
      return "Skip service " + server.serviceName + " across port changes. Restore it from Skipped."
    if (available(action)) return normalHint
    if (action === Actions.ACTIONS.open || action === Actions.ACTIONS.copyLocal)
      return server.hint || "No local URL is available."
    if (action === Actions.ACTIONS.qr) return Actions.lanUnavailableReason(server)
    if (action === Actions.ACTIONS.terminal || action === Actions.ACTIONS.project)
      return "The project directory is unavailable for this server."
    if (actionBusy) return "Another server action is in progress."
    return server.restartReason || "The restart command could not be verified."
  }

  Repeater {
    model: Actions.primary
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
    model: Actions.secondary
    ToolbarAction {
      required property var modelData
      actionIndex: modelData.action
      icon: actionIndex === Actions.ACTIONS.stop && root.forceStopAvailable ? "\uf714" : modelData.icon
      hint: root.hint(actionIndex, actionIndex === Actions.ACTIONS.stop && root.forceStopAvailable
        ? "Force stop server" : modelData.tip)
      foreground: actionIndex === Actions.ACTIONS.stop ? Theme.Color.urgent : root.foreground
      accent: actionIndex === Actions.ACTIONS.stop ? Theme.Color.urgent : Theme.Color.accent
      available: root.available(actionIndex)
      selected: root.server !== null && root.selectedActionIndex === actionIndex
      keyboardHint: root.keyboardHints
      onHovered: root.actionHovered(actionIndex)
      onTriggered: root.actionTriggered(actionIndex)
    }
  }

}
