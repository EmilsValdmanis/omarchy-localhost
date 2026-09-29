pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "RadarModel.js" as RadarModel

Item {
  id: root

  property var servers: null
  property int revision: 0
  property var systemMemory: ({ totalBytes: -1, availableBytes: -1 })
  property bool panelActive: true
  property string lanIp: ""
  property string notice: ""
  property bool noticeUrgent: false
  property string scanError: ""
  property var warnings: []
  property var diagnostics: []
  property string scanSummary: ""
  property bool scanning: false
  property var firewallRules: []
  property bool firewallBusy: false
  property string forceStopServerId: ""

  property string query: ""
  property bool groupByProject: true
  property var groups: ({})
  property string portFilter: "all"
  readonly property var portFilterOptions: [
    { value: "all", label: "All ports" },
    { value: "dev", label: "Dev ports" },
    { value: "lan", label: "LAN ready" },
    { value: "docker", label: "Docker" }
  ]
  readonly property bool searchMode: searchField.activeFocus
  property int selectedIndex: 0
  property int selectedActionIndex: 0
  property bool showFirewallRules: false
  property bool showDiagnostics: false
  property var pendingServer: null
  property var pendingFirewallRule: null
  property string pendingAction: ""

  property alias keyboardFocusTarget: keyCatcher

  signal closeRequested()
  signal refreshRequested()
  signal openRequested(var server)
  signal copyRequested(var server)
  signal qrRequested(var server)
  signal terminalRequested(var server)
  signal projectRequested(var server)
  signal restartRequested(var server)
  signal stopRequested(var server)
  signal forceStopRequested(var server)
  signal firewallAuthorizationConfirmed(var server)
  signal firewallAuthorizationCanceled()
  signal firewallRemovalConfirmed(var rule)

  readonly property color foreground: Color.popups.text
  readonly property color dim: Qt.darker(foreground, 1.4)
  readonly property int panelWidth: Style.space(460)
  readonly property int serverCount: servers ? servers.count : 0
  readonly property int resultCount: filteredModel.count
  readonly property int actionCount: 7
  readonly property var currentServer: selectedServer()
  readonly property int projectCount: Object.keys(groups).length
  readonly property real cardInset: Style.space(2)
  readonly property int listHeight: Math.min(serverList.contentHeight, Style.space(450))
  readonly property bool hasDiagnostics: scanError !== "" || warnings.length > 0
  readonly property bool resultsFiltered: query.trim() !== "" || portFilter !== "all"
  readonly property bool compactMemory: height < Style.space(400)
  readonly property var memoryStats: summarizeMemory()
  readonly property color otherMemoryColor: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.32)
  readonly property color freeMemoryColor: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.12)

  implicitWidth: panelWidth
  implicitHeight: panelLayout.implicitHeight

  function summarizeMemory() {
    var currentRevision = revision
    var rows = []
    if (servers) for (var index = 0; index < servers.count; index++) rows.push(servers.get(index))
    return RadarModel.memoryBreakdown(rows, systemMemory)
  }

  function colorForSource(index) {
    if (index === 0) return Color.accent
    var hue = Color.accent.hslHue
    return Qt.hsla(((hue < 0 ? 0.48 : hue) + index * 0.137) % 1, 0.52, 0.68, 1)
  }

  function colorForServer(server) {
    var key = RadarModel.memorySourceKey(server)
    for (var index = 0; index < memoryStats.sources.length; index++)
      if (memoryStats.sources[index].key === key) return colorForSource(index)
    return dim
  }

  function labelForSource(source) {
    var name = source.name.replace(/^@[^/]+\//, "")
    var duplicates = 0
    for (var index = 0; index < memoryStats.sources.length; index++)
      if (memoryStats.sources[index].name.replace(/^@[^/]+\//, "") === name) duplicates++
    return name + (duplicates > 1 ? " :" + source.port : "")
  }

  function portFilterLabel() {
    for (var index = 0; index < portFilterOptions.length; index++)
      if (portFilterOptions[index].value === portFilter)
        return portFilterOptions[index].label
    return "All ports"
  }

  function rebuildFilteredModel() {
    if (!panelActive) return
    var previous = selectedServer()
    var previousId = previous ? previous.serverId : ""
    var needle = query.trim().toLowerCase()
    var filtered = []
    if (servers) {
      for (var index = 0; index < servers.count; index++) {
        var server = servers.get(index)
        if (RadarModel.matchesSearch(server, needle, portFilter)) filtered.push(server)
      }
    }
    filtered.sort(function(a, b) { return RadarModel.compareServers(a, b, root.groupByProject) })
    groups = RadarModel.projectGroups(filtered)
    RadarModel.syncServerModel(filteredModel, filtered)
    var nextIndex = Math.min(selectedIndex, Math.max(0, filteredModel.count - 1))
    for (var i = 0; i < filteredModel.count; i++) {
      if (filteredModel.get(i).serverId === previousId) {
        nextIndex = i
        break
      }
    }
    selectedIndex = nextIndex
    normalizeSelectedAction(1)
  }

  function selectedServer() {
    if (selectedIndex < 0 || selectedIndex >= filteredModel.count) return null
    return RadarModel.normalizeServer(filteredModel.get(selectedIndex))
  }

  function ensureSelectedVisible() {
    Qt.callLater(positionSelection)
  }

  function positionSelection() {
    if (filteredModel.count > 0 && panelActive)
      serverList.positionViewAtIndex(selectedIndex, ListView.Contain)
  }

  function select(delta) {
    if (!filteredModel.count || showDiagnostics || showFirewallRules) return
    selectedIndex = (selectedIndex + delta + filteredModel.count) % filteredModel.count
    normalizeSelectedAction(delta < 0 ? -1 : 1)
    ensureSelectedVisible()
  }

  function actionEnabled(actionIndex, server) {
    return RadarModel.actionEnabled(actionIndex, server)
  }

  function normalizeSelectedAction(direction) {
    var server = selectedServer()
    if (!server) {
      selectedActionIndex = 0
      return
    }
    if (actionEnabled(selectedActionIndex, server)) return
    for (var step = 0; step < actionCount; step++) {
      selectedActionIndex = (selectedActionIndex + direction + actionCount) % actionCount
      if (actionEnabled(selectedActionIndex, server)) return
    }
  }

  function selectAction(delta) {
    if (showDiagnostics || showFirewallRules) return
    var server = selectedServer()
    if (!server) return
    for (var step = 0; step < actionCount; step++) {
      selectedActionIndex = (selectedActionIndex + delta + actionCount) % actionCount
      if (actionEnabled(selectedActionIndex, server)) return
    }
  }

  function setActionCursor(rowIndex, actionIndex) {
    selectedIndex = rowIndex
    selectedActionIndex = actionIndex
  }

  function navigateBack() {
    if (showDiagnostics || showFirewallRules) {
      showDiagnostics = false
      showFirewallRules = false
      focusNavigation()
    } else if (searchMode) {
      focusNavigation()
    } else if (query) {
      clearSearch()
    } else if (portFilter !== "all") {
      portFilter = "all"
      focusNavigation()
    } else {
      closeRequested()
    }
  }

  function activateSelected() {
    if (showDiagnostics || showFirewallRules) return
    activateAction(selectedActionIndex, selectedServer())
  }

  function activateAction(actionIndex, selected) {
    if (!actionEnabled(actionIndex, selected)) return
    if (actionIndex === 0) openRequested(selected)
    else if (actionIndex === 1) copyRequested(selected)
    else if (actionIndex === 2) qrRequested(selected)
    else if (actionIndex === 3) terminalRequested(selected)
    else if (actionIndex === 4) projectRequested(selected)
    else if (actionIndex === 5) restartRequested(selected)
    else if (actionIndex === 6)
      requestStop(selected, selected.serverId === forceStopServerId && selected.source !== "docker")
  }

  function beginSearch() {
    if (showDiagnostics || showFirewallRules) return
    Qt.callLater(function() { searchField.forceActiveFocus() })
  }

  function focusNavigation() {
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function clearSearch() {
    query = ""
    searchField.text = ""
    focusNavigation()
  }

  function requestStop(server, force) {
    if (!server) return
    pendingServer = server
    pendingFirewallRule = null
    pendingAction = force ? "force-stop" : "stop"
    confirmDialog.message = force
      ? "Force stop " + server.name + "? Unsaved work may be lost."
      : (server.source === "docker"
        ? "Stop Docker service " + server.name + " on :" + server.port + "?"
        : "Stop " + server.name + " on :" + server.port + "?")
    confirmDialog.confirmText = force ? "Force stop" : "Stop"
    confirmDialog.selectedIndex = 0
    confirmDialog.opened = true
  }

  function requestFirewallAuthorization(server) {
    if (!server) return
    pendingServer = server
    pendingFirewallRule = null
    pendingAction = "authorize-firewall"
    confirmDialog.message = "Allow devices on the local network to reach :" + server.port
      + "? This creates a persistent UFW rule limited to " + root.lanIp + "'s subnet."
    confirmDialog.confirmText = "Allow"
    confirmDialog.selectedIndex = 0
    confirmDialog.opened = true
  }

  function requestFirewallRemoval(rule) {
    if (!rule) return
    pendingServer = null
    pendingFirewallRule = rule
    pendingAction = "remove-firewall"
    confirmDialog.message = "Remove Localhost's LAN access rule for :" + rule.port
      + " on " + rule.subnet + "?"
    confirmDialog.confirmText = "Remove"
    confirmDialog.selectedIndex = 0
    confirmDialog.opened = true
  }

  function cancelPendingAction() {
    var canceledAction = pendingAction
    confirmDialog.opened = false
    pendingServer = null
    pendingFirewallRule = null
    pendingAction = ""
    if (canceledAction === "authorize-firewall") firewallAuthorizationCanceled()
  }

  function confirmPendingAction() {
    var action = pendingAction
    var server = pendingServer
    var rule = pendingFirewallRule
    confirmDialog.opened = false
    pendingServer = null
    pendingFirewallRule = null
    pendingAction = ""
    if (action === "force-stop") forceStopRequested(server)
    else if (action === "stop") stopRequested(server)
    else if (action === "authorize-firewall") firewallAuthorizationConfirmed(server)
    else if (action === "remove-firewall") firewallRemovalConfirmed(rule)
  }

  function handleSearchKey(event) {
    if (confirmDialog.opened) {
      if (confirmDialog.handleKey(event)) event.accepted = true
      return
    }
    var control = (event.modifiers & Qt.ControlModifier) !== 0
    var alternate = (event.modifiers & Qt.AltModifier) !== 0
    var plainNavigation = !searchMode && event.modifiers === Qt.NoModifier
    if (event.key === Qt.Key_Escape) {
      navigateBack()
      event.accepted = true
    } else if (plainNavigation
               && (event.key === Qt.Key_Left || event.key === Qt.Key_H)) {
      selectAction(-1)
      event.accepted = true
    } else if (event.key === Qt.Key_Up || (control && event.key === Qt.Key_P)
               || (plainNavigation && event.key === Qt.Key_K)) {
      select(-1)
      event.accepted = true
    } else if (event.key === Qt.Key_Down || (control && event.key === Qt.Key_N)
               || (plainNavigation && event.key === Qt.Key_J)) {
      select(1)
      event.accepted = true
    } else if (plainNavigation
               && (event.key === Qt.Key_Right || event.key === Qt.Key_L)) {
      selectAction(1)
      event.accepted = true
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      activateSelected()
      event.accepted = true
    } else if (plainNavigation && event.key === Qt.Key_Slash) {
      beginSearch()
      event.accepted = true
    } else if (control && event.key === Qt.Key_R) {
      refreshRequested()
      event.accepted = true
    } else if (alternate && event.key === Qt.Key_R) {
      var restart = selectedServer()
      if (restart) restartRequested(restart)
      event.accepted = true
    } else if (event.key === Qt.Key_Delete || (control && event.key === Qt.Key_K && query === "")) {
      var stopped = selectedServer()
      if (stopped) requestStop(stopped, stopped.serverId === forceStopServerId && stopped.source !== "docker")
      event.accepted = true
    } else if (control && event.key === Qt.Key_C && searchField.selectedText.length === 0) {
      var copied = selectedServer()
      if (copied) copyRequested(copied)
      event.accepted = true
    }
  }

  onRevisionChanged: Qt.callLater(rebuildFilteredModel)
  onServersChanged: Qt.callLater(rebuildFilteredModel)
  onPanelActiveChanged: if (panelActive) Qt.callLater(rebuildFilteredModel)
  onGroupByProjectChanged: { rebuildFilteredModel(); ensureSelectedVisible() }
  onQueryChanged: { rebuildFilteredModel(); ensureSelectedVisible() }
  onPortFilterChanged: { rebuildFilteredModel(); ensureSelectedVisible() }
  Component.onCompleted: rebuildFilteredModel()

  ListModel { id: filteredModel }

  Item {
    id: keyCatcher
    anchors.fill: parent
    z: -1
    focus: true
    Keys.onPressed: function(event) { root.handleSearchKey(event) }
  }

  ColumnLayout {
    id: panelLayout
    anchors.fill: parent
    spacing: Style.space(6)

    RowLayout {
      Layout.fillWidth: true
      spacing: Style.space(8)

      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(1)

        PanelSectionHeader {
          text: "LOCALHOST"
          foreground: root.foreground
          fontSize: Style.font.heading
        }

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: (root.resultsFiltered
              ? root.resultCount + " of " + root.serverCount + " servers"
              : root.serverCount + " server" + (root.serverCount === 1 ? "" : "s"))
            + (root.groupByProject ? " · " + root.projectCount + " project" + (root.projectCount === 1 ? "" : "s") : "")
          color: root.dim
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      PanelActionButton {
        objectName: "groupToggle"
        iconText: "\uf07b"
        tooltipText: root.groupByProject ? "Grouped by project · click to sort by port" : "Group by project"
        foreground: root.foreground
        bordered: root.groupByProject
        onClicked: { root.groupByProject = !root.groupByProject; root.focusNavigation() }
      }

      PanelActionButton {
        visible: root.scanSummary !== "" || root.diagnostics.length > 0
        iconText: "\uf05a"
        tooltipText: root.showDiagnostics ? "Hide discovery details" : "Show discovery details"
        foreground: root.foreground
        bordered: root.showDiagnostics
        onClicked: {
          root.showDiagnostics = !root.showDiagnostics
          if (root.showDiagnostics) root.showFirewallRules = false
          root.focusNavigation()
        }
      }

      PanelActionButton {
        visible: root.firewallRules.length > 0
        iconText: "󰒘"
        tooltipText: root.showFirewallRules ? "Hide LAN access rules" : "Manage LAN access rules"
        foreground: root.foreground
        bordered: root.showFirewallRules
        onClicked: {
          root.showFirewallRules = !root.showFirewallRules
          if (root.showFirewallRules) root.showDiagnostics = false
          root.focusNavigation()
        }
      }

      PanelActionButton {
        iconText: "\uf2f9"
        tooltipText: "Refresh servers (Ctrl+R)"
        foreground: root.foreground
        onClicked: root.refreshRequested()
      }
    }

    RowLayout {
      visible: !root.showFirewallRules && !root.showDiagnostics
      Layout.fillWidth: true
      spacing: Style.space(6)

      TextField {
        id: searchField
        Layout.fillWidth: true
        placeholderText: "Search projects or ports…"
        foreground: root.foreground
        text: root.query
        onTextChanged: {
          if (root.query !== text) root.query = text
        }
        onPressed: root.beginSearch()
        Keys.onPressed: function(event) { root.handleSearchKey(event) }
      }

      Dropdown {
        id: portFilterDropdown
        Layout.preferredWidth: Style.space(116)
        Layout.preferredHeight: searchField.implicitHeight
        showLabel: false
        rowHeight: searchField.implicitHeight
        popupRowHeight: Style.space(30)
        options: root.portFilterOptions
        value: root.portFilter
        foreground: root.foreground
        onChanged: function(value) {
          root.portFilter = value
          root.focusNavigation()
        }
      }
    }

    BorderSurface {
      visible: !root.showFirewallRules && !root.showDiagnostics
      Layout.fillWidth: true
      Layout.preferredHeight: root.compactMemory ? Style.space(68)
        : Style.space(108)
          + (root.memoryStats.sources.length ? sourceLabels.childrenRect.height + Style.space(7) : 0)
      color: Style.hoverFillFor(root.foreground, Color.accent)
      borderSpec: Border.controlSpec("normal", root.foreground, Color.accent)
      radius: Style.cornerRadius

      ColumnLayout {
        anchors.fill: parent
        anchors.margins: Style.space(root.compactMemory ? 7 : 10)
        spacing: Style.space(root.compactMemory ? 4 : 7)

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(8)

          ColumnLayout {
            spacing: Style.space(1)
            PanelSectionHeader { text: "SYSTEM RAM"; foreground: root.foreground }
            Text {
              objectName: "totalMemory"
              textFormat: Text.PlainText
              text: RadarModel.formatMemory(root.memoryStats.totalBytes)
              color: root.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.title
              font.bold: true
            }
          }

          Item { Layout.fillWidth: true }

          ColumnLayout {
            spacing: Style.space(1)
            PanelSectionHeader {
              text: root.memoryStats.unmeasured
                ? "SERVERS  " + root.memoryStats.measured + "/"
                  + (root.memoryStats.measured + root.memoryStats.unmeasured)
                : "SERVERS"
              foreground: root.foreground
            }
            Text {
              objectName: "trackedMemory"
              textFormat: Text.PlainText
              text: root.memoryStats.measured
                ? RadarModel.formatMemory(root.memoryStats.serverBytes) : "—"
              color: Color.accent
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              font.bold: true
            }
          }
        }

        Rectangle {
          id: memoryBar
          objectName: "memoryBar"
          Layout.fillWidth: true
          Layout.preferredHeight: Style.space(9)
          radius: height / 2
          color: root.freeMemoryColor
          border.width: Math.max(1, Style.spacing.hairline)
          border.color: root.dim

          Row {
            anchors.fill: parent
            Repeater {
              model: root.memoryStats.sources
              Rectangle {
                id: sourceSegment
                required property var modelData
                required property int index
                objectName: "memorySegment"
                width: root.memoryStats.totalBytes > 0
                  ? memoryBar.width * modelData.barBytes / root.memoryStats.totalBytes : 0
                height: memoryBar.height
                color: root.colorForSource(index)
                HoverHandler { id: segmentHover }
                PanelToolTip {
                  visible: segmentHover.hovered
                  text: sourceSegment.modelData.name + " · :" + sourceSegment.modelData.port
                    + " · " + RadarModel.formatMemory(sourceSegment.modelData.bytes)
                }
              }
            }
            Rectangle {
              objectName: "otherMemorySegment"
              width: root.memoryStats.totalBytes > 0
                ? memoryBar.width * root.memoryStats.otherBytes / root.memoryStats.totalBytes : 0
              height: memoryBar.height
              color: root.otherMemoryColor
              HoverHandler { id: otherHover }
              PanelToolTip {
                visible: otherHover.hovered
                text: "Other apps and system · " + RadarModel.formatMemory(root.memoryStats.otherBytes)
              }
            }
            Rectangle {
              objectName: "freeMemorySegment"
              width: root.memoryStats.totalBytes > 0
                ? memoryBar.width * root.memoryStats.availableBytes / root.memoryStats.totalBytes : 0
              height: memoryBar.height
              color: root.freeMemoryColor
              HoverHandler { id: freeHover }
              PanelToolTip {
                visible: freeHover.hovered
                text: "Free / available · " + RadarModel.formatMemory(root.memoryStats.availableBytes)
              }
            }
          }
        }

        RowLayout {
          visible: !root.compactMemory
          Layout.fillWidth: true
          spacing: Style.space(7)
          Rectangle {
            Layout.preferredWidth: Style.space(5); Layout.preferredHeight: Style.space(5)
            radius: width / 2; color: Color.accent
          }
          Text {
            textFormat: Text.PlainText
            text: "Servers " + (root.memoryStats.measured
              ? RadarModel.formatMemory(root.memoryStats.serverBytes) : "—")
            color: root.dim
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
          Rectangle {
            Layout.preferredWidth: Style.space(5); Layout.preferredHeight: Style.space(5)
            radius: width / 2; color: root.otherMemoryColor
          }
          Text {
            textFormat: Text.PlainText
            text: (root.memoryStats.unmeasured ? "Other + unknown " : "Other apps ")
              + RadarModel.formatMemory(root.memoryStats.otherBytes)
            color: root.dim
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
          Rectangle {
            Layout.preferredWidth: Style.space(5); Layout.preferredHeight: Style.space(5)
            radius: width / 2; color: root.freeMemoryColor
          }
          Text {
            textFormat: Text.PlainText
            text: "Free " + RadarModel.formatMemory(root.memoryStats.availableBytes)
            color: root.dim
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
          Item { Layout.fillWidth: true }
        }

        Flow {
          id: sourceLabels
          visible: !root.compactMemory && root.memoryStats.sources.length > 0
          Layout.fillWidth: true
          Layout.preferredHeight: childrenRect.height
          spacing: Style.space(6)

          Repeater {
            model: root.memoryStats.sources.slice(0, 8)
            Row {
              id: sourceLabel
              required property var modelData
              required property int index
              objectName: "memorySourceChip"
              spacing: Style.space(3)
              Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(5)
                height: Style.space(5)
                radius: width / 2
                color: root.colorForSource(sourceLabel.index)
              }
              Text {
                textFormat: Text.PlainText
                width: Math.min(implicitWidth, Style.space(95))
                text: root.labelForSource(sourceLabel.modelData)
                color: root.dim
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
              }
            }
          }
          Text {
            visible: root.memoryStats.sources.length > 8
            textFormat: Text.PlainText
            text: "+" + (root.memoryStats.sources.length - 8) + " more"
            color: root.dim
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
        }
      }
    }

    PanelSeparator {
      Layout.fillWidth: true
      foreground: root.foreground
    }

    BorderSurface {
      visible: root.hasDiagnostics
      Layout.fillWidth: true
      Layout.preferredHeight: diagnosticText.implicitHeight + Style.space(14)
      color: Style.hoverFillFor(root.foreground, root.scanError ? Color.urgent : Color.accent)
      borderSpec: Border.controlSpec("normal", root.foreground, Color.accent)
      radius: Style.cornerRadius

      Text {
        textFormat: Text.PlainText
        id: diagnosticText
        anchors.fill: parent
        anchors.margins: Style.space(7)
        text: root.scanError || root.warnings.join("\n")
        maximumLineCount: 3
        elide: Text.ElideRight
        color: root.scanError ? Color.urgent : root.dim
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        wrapMode: Text.Wrap
      }
    }

    PanelScrollArea {
      objectName: "firewallList"
      visible: root.showFirewallRules
      Layout.fillWidth: true
      spacing: Style.space(6)

      PanelSectionHeader {
        Layout.fillWidth: true
        text: "LAN ACCESS RULES"
        foreground: root.foreground
      }

      Repeater {
        model: root.firewallRules

        CursorSurface {
          id: firewallRow
          required property var modelData
          Layout.fillWidth: true
          Layout.preferredHeight: Style.space(38)
          bordered: true
          foreground: root.foreground

          RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Style.space(10)
            anchors.rightMargin: Style.space(8)
            spacing: Style.space(8)

            Text {
              textFormat: Text.PlainText
              text: ":" + firewallRow.modelData.port
              color: root.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              font.bold: true
            }

            Text {
              textFormat: Text.PlainText
              Layout.fillWidth: true
              text: firewallRow.modelData.subnet + (firewallRow.modelData.interfaceName ? "  ·  " + firewallRow.modelData.interfaceName : "")
              color: root.dim
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }

            Button {
              text: "Remove"
              tooltipText: "Remove this LAN access rule"
              foreground: Color.urgent
              accent: Color.urgent
              bordered: true
              fontSize: Style.font.caption
              horizontalPadding: Style.space(8)
              verticalPadding: Style.space(4)
              enabled: !root.firewallBusy
              onClicked: root.requestFirewallRemoval(firewallRow.modelData)
            }
          }
        }
      }
    }

    PanelScrollArea {
      objectName: "diagnosticList"
      visible: root.showDiagnostics
      Layout.fillWidth: true
      spacing: Style.space(6)

      Text {
        textFormat: Text.PlainText
        Layout.fillWidth: true
        text: root.scanSummary || "DISCOVERY DETAILS"
        color: root.dim
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        font.bold: true
        font.letterSpacing: 0.5
        elide: Text.ElideRight
      }

      Repeater {
        model: root.diagnostics.slice(0, 8)

        BorderSurface {
          id: diagnosticItem
          required property var modelData
          Layout.fillWidth: true
          Layout.preferredHeight: diagnosticRow.implicitHeight + Style.space(12)
          color: "transparent"
          borderSpec: Border.controlSpec("normal", root.foreground, Color.accent)
          radius: Style.cornerRadius

          RowLayout {
            id: diagnosticRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Style.space(9)
            anchors.rightMargin: Style.space(9)
            spacing: Style.space(8)

            Text {
              textFormat: Text.PlainText
              text: ":" + diagnosticItem.modelData.port
              color: root.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              font.bold: true
            }
            Text {
              textFormat: Text.PlainText
              Layout.preferredWidth: Style.space(90)
              text: diagnosticItem.modelData.process
              color: root.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }
            Text {
              textFormat: Text.PlainText
              Layout.fillWidth: true
              text: diagnosticItem.modelData.reason
              color: root.dim
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }
          }
        }
      }

      Text {
        textFormat: Text.PlainText
        visible: root.diagnostics.length > 8
        Layout.fillWidth: true
        text: "+ " + (root.diagnostics.length - 8) + " more skipped listeners"
        color: root.dim
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        horizontalAlignment: Text.AlignHCenter
      }
    }

    Item {
      visible: !root.showFirewallRules && !root.showDiagnostics
      Layout.fillWidth: true
      Layout.fillHeight: true
      Layout.minimumHeight: 0
      Layout.preferredHeight: root.resultCount > 0 ? Math.max(Style.space(80), root.listHeight) : Style.space(120)

      ListView {
        id: serverList
        objectName: "serverList"
        anchors.fill: parent
        visible: root.resultCount > 0
        model: filteredModel
        clip: true
        spacing: Style.space(2)
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        currentIndex: root.selectedIndex
        highlightFollowsCurrentItem: false
        reuseItems: true

        ScrollBar.vertical: ScrollBar {
          id: serverScrollBar
          policy: ScrollBar.AsNeeded
        }

        section.property: root.groupByProject ? "projectRoot" : ""
        section.criteria: ViewSection.FullString
        section.delegate: Item {
          id: groupHeader
          required property string section
          readonly property var group: root.groups[section] || { name: "Project", count: 0 }
          width: serverList.width
          height: Style.space(28)
          RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Style.space(8)
            anchors.rightMargin: Style.space(10)
            spacing: Style.space(8)
            PanelSectionHeader {
              Layout.fillWidth: true
              text: groupHeader.group.name
              foreground: root.foreground
              elide: Text.ElideMiddle
            }
            Text {
              textFormat: Text.PlainText
              text: groupHeader.group.count
              color: root.dim
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }
          }
        }

        delegate: ServerRow {
          required property var model
          server: RadarModel.normalizeServer(model)
          x: root.cardInset
          width: serverList.width - root.cardInset * 2
            - (serverScrollBar.visible ? serverScrollBar.width + Style.space(4) : 0)
          height: implicitHeight
          selected: index === root.selectedIndex
          foreground: root.foreground
          memoryColor: root.colorForServer(server)
          onRowSelected: { root.selectedIndex = index; root.focusNavigation() }
          onOpenRequested: { root.selectedIndex = index; root.activateAction(0, server) }
        }
      }


      Column {
        visible: root.resultCount === 0
        anchors.centerIn: parent
        width: parent.width
        spacing: Style.space(6)

        Text {
          textFormat: Text.PlainText
          width: parent.width
          text: root.query
            ? "No projects match “" + root.query + "” in " + root.portFilterLabel().toLowerCase()
            : (root.portFilter !== "all"
              ? "No servers match “" + root.portFilterLabel() + "”"
              : (root.scanning ? "Looking for development servers…" : "No development servers found"))
          color: root.foreground
          opacity: 0.75
          font.family: Style.font.family
          font.pixelSize: Style.font.title
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.Wrap
        }

        Text {
          textFormat: Text.PlainText
          visible: !root.query && root.portFilter === "all" && !root.scanning
          width: parent.width
          text: "Start a server or press Ctrl+R to scan again."
          color: root.dim
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          horizontalAlignment: Text.AlignHCenter
        }
      }
    }

    PanelSeparator {
      visible: !root.showFirewallRules && !root.showDiagnostics && root.resultCount > 0
      Layout.fillWidth: true
      foreground: root.foreground
    }

    ServerActions {
      visible: !root.showFirewallRules && !root.showDiagnostics && root.resultCount > 0
      Layout.fillWidth: true
      server: root.currentServer
      selectedActionIndex: root.selectedActionIndex
      forceStopAvailable: !!server && server.serverId === root.forceStopServerId && server.source !== "docker"
      foreground: root.foreground
      onActionHovered: function(actionIndex) { root.selectedActionIndex = actionIndex }
      onActionTriggered: function(actionIndex) { root.activateAction(actionIndex, root.currentServer) }
    }

    Text {
      textFormat: Text.PlainText
      visible: root.notice !== ""
      Layout.fillWidth: true
      text: root.notice
      maximumLineCount: 3
      elide: Text.ElideRight
      color: root.noticeUrgent ? Color.urgent : root.dim
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      wrapMode: Text.Wrap
      horizontalAlignment: Text.AlignHCenter
    }

    Text {
      textFormat: Text.PlainText
      Layout.fillWidth: true
      text: "↑↓ select · ←→ action · enter run · / search"
      color: root.dim
      opacity: 0.66
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      horizontalAlignment: Text.AlignHCenter
      elide: Text.ElideRight
    }
  }

  ConfirmDialog {
    id: confirmDialog
    anchors.fill: parent
    z: 100
    background: Color.popups.background
    foreground: root.foreground
    selectedText: Color.accent
    fontFamily: Style.font.family
    onCanceled: root.cancelPendingAction()
    onConfirmed: root.confirmPendingAction()
  }

}
