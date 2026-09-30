pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "RadarModel.js" as RadarModel
import "ProjectList.js" as ProjectList

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
  property var collapsedProjects: ({})
  property var filteredCollapsedProjects: ({})
  property string selectedProjectRoot: ""
  property int entryRevision: 0
  property int filteredRevision: 0
  readonly property int selectedEntryIndex: selectionEntryIndex()
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
  property bool memoryExpanded: false
  property var pendingServer: null
  property var pendingFirewallRule: null
  property string pendingAction: ""

  property alias keyboardFocusTarget: keyCatcher

  signal closeRequested()
  signal refreshRequested()
  signal openRequested(var server)
  signal copyRequested(var server)
  signal copyLanRequested(var server)
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
  readonly property int actionCount: 8
  readonly property var currentServer: selectedServer()
  readonly property int projectCount: Object.keys(groups).length
  readonly property real cardInset: Style.space(2)
  readonly property int listHeight: Math.min(serverList.contentHeight, Style.space(450))
  readonly property bool hasDiagnostics: scanError !== "" || warnings.length > 0
  readonly property bool resultsFiltered: hasResultFilter()
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

  function colorForSource(key) {
    var hue = Color.accent.hslHue
    return Qt.hsla(((hue < 0 ? 0.48 : hue) + RadarModel.sourceColorOffset(key)) % 1, 0.52, 0.68, 1)
  }

  function colorForServer(server) {
    return colorForSource(RadarModel.memorySourceKey(server))
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
    var previousRoot = selectedProjectRoot || (previous ? previous.projectRoot : "")
    var previousHeader = selectedProjectRoot !== ""
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
    if (RadarModel.syncServerModel(filteredModel, filtered)) filteredRevision++
    if (ProjectList.syncEntries(projectModel, ProjectList.entriesFor(filtered, groups, groupByProject, projectCollapseState())))
      entryRevision++
    var nextIndex = Math.min(selectedIndex, Math.max(0, filteredModel.count - 1))
    if (nextIndex < 0) nextIndex = 0
    for (var i = 0; i < filteredModel.count; i++) {
      if (filteredModel.get(i).serverId === previousId
          || (!groupByProject && previousHeader && filteredModel.get(i).projectRoot === previousRoot)) {
        nextIndex = i
        break
      }
    }
    if (!filteredModel.count) {
      selectedIndex = -1
      selectedProjectRoot = ""
    } else if (groupByProject && groups[previousRoot] && (previousHeader || isProjectCollapsed(previousRoot))) {
      selectedIndex = -1
      selectedProjectRoot = previousRoot
    } else {
      selectedProjectRoot = ""
      selectedIndex = nextIndex
      var next = filteredModel.get(nextIndex)
      if (groupByProject && isProjectCollapsed(next.projectRoot)) selectProject(next.projectRoot)
    }
    normalizeSelectedAction(1)
  }

  function selectedServer() {
    if (selectedProjectRoot) return null
    if (selectedIndex < 0 || selectedIndex >= filteredModel.count) return null
    return RadarModel.normalizeServer(filteredModel.get(selectedIndex))
  }

  function selectionEntryIndex() {
    var currentEntries = entryRevision
    var server = selectedServer()
    var id = selectedProjectRoot ? "project:" + selectedProjectRoot : (server ? "server:" + server.serverId : "")
    for (var i = 0; i < projectModel.count; i++)
      if (projectModel.get(i).entryId === id) return i
    return -1
  }

  function hasResultFilter() {
    return query.trim() !== "" || portFilter !== "all"
  }

  // Read the filter inputs directly: their change handlers can run before
  // derived property bindings update. New searches must reveal their matches.
  function projectCollapseState() {
    return hasResultFilter() ? filteredCollapsedProjects : collapsedProjects
  }

  function isProjectCollapsed(projectRoot) {
    return projectCollapseState()[projectRoot] === true
  }

  function selectProject(projectRoot) {
    if (!groupByProject || !groups[projectRoot]) return
    selectedIndex = -1
    selectedProjectRoot = projectRoot
    normalizeSelectedAction(1)
    ensureSelectedVisible()
  }

  function selectEntry(index) {
    if (index < 0 || index >= projectModel.count) return
    var entry = projectModel.get(index)
    if (entry.projectHeader) selectProject(entry.projectRoot)
    else {
      selectedProjectRoot = ""
      selectedIndex = entry.serverIndex
      normalizeSelectedAction(1)
      ensureSelectedVisible()
    }
  }

  function selectedProject() {
    var server = selectedServer()
    return selectedProjectRoot || (server ? server.projectRoot : "")
  }

  function setProjectCollapsed(projectRoot, collapsed) {
    if (!groupByProject || !groups[projectRoot] || showDiagnostics || showFirewallRules) return
    selectProject(projectRoot)
    var next = Object.assign(Object.create(null), projectCollapseState())
    if (collapsed) next[projectRoot] = true
    else delete next[projectRoot]
    if (hasResultFilter()) filteredCollapsedProjects = next
    else collapsedProjects = next
    rebuildFilteredModel()
    ensureSelectedVisible()
  }

  function toggleProject(projectRoot) {
    setProjectCollapsed(projectRoot, !isProjectCollapsed(projectRoot))
    focusNavigation()
  }

  function setAllProjectsCollapsed(collapsed) {
    if (!groupByProject || !projectModel.count || showDiagnostics || showFirewallRules) return
    var current = selectedProject()
    var next = Object.assign(Object.create(null), projectCollapseState())
    for (var projectRoot in groups) {
      if (collapsed) next[projectRoot] = true
      else delete next[projectRoot]
    }
    selectProject(current)
    if (hasResultFilter()) filteredCollapsedProjects = next
    else collapsedProjects = next
    rebuildFilteredModel()
    ensureSelectedVisible()
  }

  function selectAdjacentProject(delta) {
    if (!groupByProject || showDiagnostics || showFirewallRules) return
    var roots = []
    for (var i = 0; i < projectModel.count; i++)
      if (projectModel.get(i).projectHeader) roots.push(projectModel.get(i).projectRoot)
    if (!roots.length) return
    var current = roots.indexOf(selectedProject())
    if (current < 0) current = delta < 0 ? 0 : -1
    selectProject(roots[(current + delta + roots.length) % roots.length])
  }

  function navigateHorizontal(delta) {
    if (!selectedProjectRoot) { selectAction(delta); return }
    if (showDiagnostics || showFirewallRules) return
    if (delta < 0) setProjectCollapsed(selectedProjectRoot, true)
    else if (isProjectCollapsed(selectedProjectRoot)) setProjectCollapsed(selectedProjectRoot, false)
    else if (selectedEntryIndex + 1 < projectModel.count && !projectModel.get(selectedEntryIndex + 1).projectHeader)
      selectEntry(selectedEntryIndex + 1)
  }

  function ensureSelectedVisible() {
    Qt.callLater(positionSelection)
  }

  function positionSelection() {
    if (selectedEntryIndex >= 0 && panelActive)
      serverList.positionViewAtIndex(selectedEntryIndex, ListView.Contain)
  }

  function select(delta) {
    if (!projectModel.count || showDiagnostics || showFirewallRules) return
    selectEntry((selectedEntryIndex + delta + projectModel.count) % projectModel.count)
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
    if (selectedProjectRoot) { toggleProject(selectedProjectRoot); return }
    activateAction(selectedActionIndex, selectedServer())
  }

  function activateAction(actionIndex, selected) {
    if (!actionEnabled(actionIndex, selected)) return
    if (actionIndex === RadarModel.ACTIONS.open) openRequested(selected)
    else if (actionIndex === RadarModel.ACTIONS.copyLocal) copyRequested(selected)
    else if (actionIndex === RadarModel.ACTIONS.copyLan) copyLanRequested(selected)
    else if (actionIndex === RadarModel.ACTIONS.qr) qrRequested(selected)
    else if (actionIndex === RadarModel.ACTIONS.terminal) terminalRequested(selected)
    else if (actionIndex === RadarModel.ACTIONS.project) projectRequested(selected)
    else if (actionIndex === RadarModel.ACTIONS.restart) restartRequested(selected)
    else if (actionIndex === RadarModel.ACTIONS.stop)
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
      + "? This creates a persistent UFW rule limited to " + server.lanSubnet + " on " + server.lanInterface + "."
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
    var shift = (event.modifiers & Qt.ShiftModifier) !== 0
    var plainNavigation = !searchMode && event.modifiers === Qt.NoModifier
    if (event.key === Qt.Key_Escape) {
      navigateBack()
      event.accepted = true
    } else if (!searchMode && control && groupByProject
               && (event.key === Qt.Key_Left || event.key === Qt.Key_Right)) {
      if (shift) setAllProjectsCollapsed(event.key === Qt.Key_Left)
      else setProjectCollapsed(selectedProject(), event.key === Qt.Key_Left)
      event.accepted = true
    } else if (control && groupByProject && (event.key === Qt.Key_Up || event.key === Qt.Key_Down)) {
      selectAdjacentProject(event.key === Qt.Key_Up ? -1 : 1)
      event.accepted = true
    } else if (!searchMode && !control && !alternate && groupByProject
               && (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab)) {
      selectAdjacentProject(event.key === Qt.Key_Backtab || shift ? -1 : 1)
      event.accepted = true
    } else if (plainNavigation && (event.key === Qt.Key_Home || event.key === Qt.Key_End)) {
      selectEntry(event.key === Qt.Key_Home ? 0 : projectModel.count - 1)
      event.accepted = true
    } else if (plainNavigation && event.key === Qt.Key_Space && selectedProjectRoot) {
      toggleProject(selectedProjectRoot)
      event.accepted = true
    } else if (plainNavigation
               && (event.key === Qt.Key_Left || event.key === Qt.Key_H)) {
      navigateHorizontal(-1)
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
      navigateHorizontal(1)
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
      if (actionEnabled(RadarModel.ACTIONS.restart, restart)) restartRequested(restart)
      event.accepted = true
    } else if (event.key === Qt.Key_Delete || (control && event.key === Qt.Key_K && query === "")) {
      var stopped = selectedServer()
      if (stopped) requestStop(stopped, stopped.serverId === forceStopServerId && stopped.source !== "docker")
      event.accepted = true
    } else if (control && event.key === Qt.Key_C && searchField.selectedText.length === 0) {
      var copied = selectedServer()
      var shareOverLan = (event.modifiers & Qt.ShiftModifier) !== 0
      if (actionEnabled(shareOverLan ? RadarModel.ACTIONS.copyLan : RadarModel.ACTIONS.copyLocal, copied)) {
        if (shareOverLan) copyLanRequested(copied)
        else copyRequested(copied)
      }
      event.accepted = true
    } else if (control && event.key === Qt.Key_M) {
      memoryExpanded = !memoryExpanded
      event.accepted = true
    }
  }

  onRevisionChanged: Qt.callLater(rebuildFilteredModel)
  onServersChanged: Qt.callLater(rebuildFilteredModel)
  onPanelActiveChanged: if (panelActive) Qt.callLater(rebuildFilteredModel)
  onGroupByProjectChanged: { rebuildFilteredModel(); ensureSelectedVisible() }
  onSelectedIndexChanged: if (selectedIndex >= 0) selectedProjectRoot = ""
  onQueryChanged: { filteredCollapsedProjects = ({}); rebuildFilteredModel(); ensureSelectedVisible() }
  onPortFilterChanged: { filteredCollapsedProjects = ({}); rebuildFilteredModel(); ensureSelectedVisible() }
  Component.onCompleted: rebuildFilteredModel()

  ListModel { id: filteredModel }
  ListModel { id: projectModel }

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
      objectName: "memoryOverview"
      visible: !root.showFirewallRules && !root.showDiagnostics
      Layout.fillWidth: true
      Layout.preferredHeight: !root.memoryExpanded ? memoryLayout.implicitHeight + Style.space(14)
        : (root.compactMemory ? Style.space(68) : Style.space(108)
          + (root.memoryStats.sources.length ? sourceLabels.childrenRect.height + Style.space(7) : 0))
      color: Style.hoverFillFor(root.foreground, Color.accent)
      borderSpec: Border.controlSpec("normal", root.foreground, Color.accent)
      radius: Style.cornerRadius

      ColumnLayout {
        id: memoryLayout
        anchors.fill: parent
        anchors.margins: Style.space(!root.memoryExpanded || root.compactMemory ? 7 : 10)
        spacing: Style.space(root.compactMemory ? 4 : 7)

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(8)

          ColumnLayout {
            visible: root.memoryExpanded
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

          Text {
            objectName: "memorySummary"
            visible: !root.memoryExpanded
            Layout.fillWidth: true
            textFormat: Text.PlainText
            text: "RAM · " + (root.memoryStats.measured ? RadarModel.formatMemory(root.memoryStats.serverBytes) : "—")
              + " servers · " + RadarModel.formatMemory(root.memoryStats.availableBytes) + " free"
            color: root.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }

          Item { visible: root.memoryExpanded; Layout.fillWidth: true }

          ColumnLayout {
            visible: root.memoryExpanded
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

          Button {
            objectName: "memoryToggle"
            text: root.memoryExpanded ? "Less" : "Details"
            foreground: root.foreground
            fontSize: Style.font.caption
            horizontalPadding: Style.space(7)
            verticalPadding: Style.space(3)
            tooltipText: (root.memoryExpanded ? "Hide" : "Show") + " RAM details (Ctrl+M)"
            onClicked: root.memoryExpanded = !root.memoryExpanded
          }
        }

        Rectangle {
          id: memoryBar
          visible: root.memoryExpanded
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
                color: root.colorForSource(modelData.key)
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
          visible: root.memoryExpanded && !root.compactMemory
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
          visible: root.memoryExpanded && !root.compactMemory && root.memoryStats.sources.length > 0
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
                color: root.colorForSource(sourceLabel.modelData.key)
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
        model: projectModel
        clip: true
        spacing: Style.space(2)
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        currentIndex: root.selectedEntryIndex
        highlightFollowsCurrentItem: false
        reuseItems: true

        ScrollBar.vertical: ScrollBar {
          id: serverScrollBar
          policy: ScrollBar.AsNeeded
        }

        delegate: Loader {
          id: entryDelegate
          required property int index
          required property var model
          readonly property int serverIndex: model.serverIndex
          readonly property bool selected: index === root.selectedEntryIndex
          x: root.cardInset
          width: serverList.width - root.cardInset * 2
            - (serverScrollBar.visible ? serverScrollBar.width + Style.space(4) : 0)
          height: item ? (item as Item).implicitHeight : 0
          sourceComponent: model.projectHeader ? projectHeaderComponent : serverRowComponent

          Component {
            id: projectHeaderComponent
            ProjectHeader {
              projectRoot: entryDelegate.model.projectRoot
              name: entryDelegate.model.name
              count: entryDelegate.model.count
              collapsed: entryDelegate.model.collapsed
              selected: entryDelegate.selected
              foreground: root.foreground
              onToggled: root.toggleProject(projectRoot)
              onFocused: root.selectProject(projectRoot)
              onNavigationKey: function(event) { root.handleSearchKey(event) }
            }
          }
          Component {
            id: serverRowComponent
            ServerRow {
              index: entryDelegate.serverIndex
              server: {
                var currentRevision = root.filteredRevision
                return index >= 0 && index < filteredModel.count
                  ? RadarModel.normalizeServer(filteredModel.get(index)) : RadarModel.normalizeServer({})
              }
              selected: entryDelegate.selected
              foreground: root.foreground
              memoryColor: root.colorForServer(server)
              onRowSelected: { root.selectedIndex = index; root.selectedProjectRoot = ""; root.focusNavigation() }
              onOpenRequested: { root.selectedIndex = index; root.selectedProjectRoot = ""; root.activateAction(0, server) }
            }
          }
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
      text: root.selectedProjectRoot
        ? "↑↓ select · ←→ fold · enter / space toggle · ctrl+↑↓ project"
        : (root.groupByProject
          ? "↑↓ select · ←→ action · ctrl+← fold · ctrl+↑↓ project"
          : "↑↓ select · ←→ action · enter run · / search")
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
