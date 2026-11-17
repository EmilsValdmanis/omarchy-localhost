pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Theme
import qs.Ui
import "Actions.js" as Actions
import "Diagnostics.js" as Diagnostics
import "ListModelSync.js" as ListModelSync
import "Memory.js" as Memory
import "ProjectList.js" as ProjectList
import "Servers.js" as Servers
import "Sources.js" as Sources

Item {
  id: root

  property var servers: null
  property int revision: 0
  property var systemMemory: ({ totalBytes: -1, availableBytes: -1 })
  property bool panelActive: true
  property string lanIp: ""
  property string notice: ""
  property bool noticeUrgent: false
  property var failedRestart: null
  property string scanError: ""
  property var warnings: []
  property var diagnostics: []
  property var includedPorts: ({})
  property var skippedGroupOverrides: ({})
  property string selectedSkippedGroup: ""
  readonly property var skippedGroups: Diagnostics.skippedPortGroups(diagnostics)
  readonly property bool hasManualSkips: skippedGroups.manual.length > 0
  readonly property var skippedGroupState: ({
    manual: skippedGroupOverrides.manual === true,
    automatic: skippedGroupOverrides.automatic === undefined ? hasManualSkips : skippedGroupOverrides.automatic
  })
  property string scanSummary: ""
  property bool scanning: false
  property var firewallRules: []
  property bool firewallBusy: false
  property string forceStopServerId: ""
  property bool actionBusy: false
  property string stoppingProjectRoot: ""

  property string query: ""
  property bool groupByProject: true
  property var groups: ({})
  property var collapsedProjects: ({})
  property var filteredCollapsedProjects: ({})
  property string selectedProjectRoot: ""
  property bool projectStopSelected: false
  property string pendingVimPrefix: ""
  property int entryRevision: 0
  property int filteredRevision: 0
  readonly property int selectedEntryIndex: selectionEntryIndex()
  property string portFilter: "all"
  readonly property var portFilterOptions: [
    { value: "all", label: "All ports", icon: "\uf1e6" },
    { value: "dev", label: "Dev ports", icon: "\uf121" },
    { value: "lan", label: "LAN ready", icon: "\uf1e0" },
    { value: "docker", label: "Docker", icon: "\uf308" }
  ]
  readonly property bool searchMode: searchField.activeFocus
  property int selectedIndex: 0
  property int selectedActionIndex: 0
  property bool showActionHint: false
  property bool showFirewallRules: false
  property bool showDiagnostics: false
  property var pendingServer: null
  property var pendingFirewallRule: null
  property string pendingAction: ""

  property alias keyboardFocusTarget: keyCatcher

  signal closeRequested()
  signal refreshRequested()
  signal includePortRequested(int port)
  signal skipPortRequested(int port)
  signal skipServiceRequested(var server)
  signal restoreServiceRequested(string key, string name)
  signal openRequested(var server)
  signal copyRequested(var server)
  signal copyLanRequested(var server)
  signal qrRequested(var server)
  signal terminalRequested(var server)
  signal projectRequested(var server)
  signal restartRequested(var server)
  signal openRestartLogRequested(string path)
  signal dismissRestartFailureRequested()
  signal stopRequested(var server)
  signal projectStopRequested(string projectRoot)
  signal forceStopRequested(var server)
  signal firewallAuthorizationConfirmed(var server)
  signal firewallAuthorizationCanceled()
  signal firewallRemovalConfirmed(var rule)

  readonly property color foreground: Theme.Color.popups.text
  readonly property color dim: Qt.darker(foreground, 1.4)
  readonly property int panelWidth: Style.space(460)
  readonly property int serverCount: servers ? servers.count : 0
  readonly property int resultCount: filteredModel.count
  readonly property var actionOrder: Actions.visibleOrder
  readonly property var currentServer: selectedServer()
  readonly property int projectCount: Object.keys(groups).length
  readonly property real scrollBarGap: Style.space(2)
  readonly property int listHeight: Math.min(serverList.contentHeight, Style.space(450))
  readonly property bool hasDiagnostics: scanError !== "" || warnings.length > 0
  readonly property bool resultsFiltered: hasResultFilter()
  readonly property var memoryStats: summarizeMemory()
  readonly property color otherMemoryColor: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.32)
  readonly property color freeMemoryColor: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.12)

  implicitWidth: panelWidth
  implicitHeight: panelLayout.implicitHeight

  function toggleSkippedGroup(group, keepFocus) {
    selectedSkippedGroup = group
    var next = Object.assign({}, skippedGroupOverrides)
    next[group] = !skippedGroupState[group]
    skippedGroupOverrides = next
    if (keepFocus) Qt.callLater(function() {
      var index = group === "manual" ? 0 : 1 + (root.skippedGroupState.manual ? 0 : root.skippedGroups.manual.length)
      discoveryList.positionViewAtIndex(index, ListView.Contain)
      var entry = discoveryList.itemAtIndex(index)
      if (entry && entry.item) entry.item.forceActiveFocus()
    })
  }

  function rebuildSkippedModel() {
    ListModelSync.sync(skippedModel, Diagnostics.skippedPortEntries(skippedGroups, skippedGroupState), "entryId", Diagnostics.skippedEntriesEqual)
  }

  onSkippedGroupsChanged: Qt.callLater(rebuildSkippedModel)
  onSkippedGroupStateChanged: Qt.callLater(rebuildSkippedModel)

  onHasManualSkipsChanged: {
    var next = Object.assign({}, skippedGroupOverrides)
    delete next.automatic
    skippedGroupOverrides = next
  }

  function summarizeMemory() {
    var currentRevision = revision
    var rows = []
    if (servers) for (let index = 0; index < servers.count; index++) rows.push(servers.get(index))
    return Memory.memoryBreakdown(rows, systemMemory)
  }

  function colorForSource(key) {
    var hue = Theme.Color.accent.hslHue
    return Qt.hsla(((hue < 0 ? 0.48 : hue) + Sources.colorOffset(key)) % 1, 0.52, 0.68, 1)
  }

  function colorForServer(server) {
    return colorForSource(Sources.key(server))
  }

  function portFilterLabel() {
    for (let index = 0; index < portFilterOptions.length; index++)
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
    var activeServers = []
    if (servers) {
      for (let index = 0; index < servers.count; index++) {
        let server = servers.get(index)
        activeServers.push(server)
        if (Servers.matchesSearch(server, needle, portFilter)) filtered.push(server)
      }
    }
    filtered.sort(function(a, b) { return Servers.compareServers(a, b, root.groupByProject) })
    groups = Servers.projectGroups(filtered, activeServers)
    if (Servers.syncServerModel(filteredModel, filtered)) filteredRevision++
    if (ListModelSync.sync(projectModel, ProjectList.entriesFor(filtered, groups, groupByProject, projectCollapseState()), "entryId", ProjectList.entriesEqual))
      entryRevision++
    var nextIndex = Math.min(selectedIndex, Math.max(0, filteredModel.count - 1))
    if (nextIndex < 0) nextIndex = 0
    for (let i = 0; i < filteredModel.count; i++) {
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
      let next = filteredModel.get(nextIndex)
      if (groupByProject && isProjectCollapsed(next.projectRoot)) selectProject(next.projectRoot)
    }
    normalizeSelectedAction()
  }

  function selectedServer() {
    if (selectedProjectRoot) return null
    if (selectedIndex < 0 || selectedIndex >= filteredModel.count) return null
    return Servers.normalizeServer(filteredModel.get(selectedIndex))
  }

  function selectionEntryIndex() {
    var currentEntries = entryRevision
    var server = selectedServer()
    var id = selectedProjectRoot ? "project:" + selectedProjectRoot : (server ? "server:" + server.serverId : "")
    for (let i = 0; i < projectModel.count; i++)
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
    pendingVimPrefix = ""
    projectStopSelected = false
    selectedIndex = -1
    selectedProjectRoot = projectRoot
    normalizeSelectedAction()
    ensureSelectedVisible()
  }

  function selectEntry(index) {
    if (index < 0 || index >= projectModel.count) return
    showActionHint = false
    pendingVimPrefix = ""
    var entry = projectModel.get(index)
    if (entry.projectHeader) selectProject(entry.projectRoot)
    else {
      selectedProjectRoot = ""
      selectedIndex = entry.serverIndex
      normalizeSelectedAction()
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
    for (let projectRoot in groups) {
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
    for (let i = 0; i < projectModel.count; i++)
      if (projectModel.get(i).projectHeader) roots.push(projectModel.get(i).projectRoot)
    if (!roots.length) return
    var current = roots.indexOf(selectedProject())
    if (current < 0) current = delta < 0 ? 0 : -1
    selectProject(roots[Math.max(0, Math.min(roots.length - 1, current + delta))])
  }

  function navigateHorizontal(delta) {
    if (!selectedProjectRoot) { selectAction(delta); return }
    if (showDiagnostics || showFirewallRules) return
    if (delta < 0) {
      if (projectStopSelected) projectStopSelected = false
      else setProjectCollapsed(selectedProjectRoot, true)
    } else if (!projectStopSelected && !actionBusy) {
      projectStopSelected = true
    } else {
      if (isProjectCollapsed(selectedProjectRoot)) setProjectCollapsed(selectedProjectRoot, false)
      if (selectedEntryIndex + 1 < projectModel.count && !projectModel.get(selectedEntryIndex + 1).projectHeader)
        selectEntry(selectedEntryIndex + 1)
    }
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
    selectEntry(Math.max(0, Math.min(projectModel.count - 1, selectedEntryIndex + delta)))
    normalizeSelectedAction()
    ensureSelectedVisible()
  }

  function actionEnabled(actionIndex, server) {
    return Actions.actionEnabled(actionIndex, server, actionBusy)
  }

  function normalizeSelectedAction() {
    var server = selectedServer()
    if (!server) {
      selectedActionIndex = 0
      return
    }
    if (actionOrder.indexOf(selectedActionIndex) < 0) selectedActionIndex = actionOrder[0]
  }

  function selectAction(delta) {
    if (showDiagnostics || showFirewallRules) return
    var server = selectedServer()
    if (!server) return
    showActionHint = true
    var position = actionOrder.indexOf(selectedActionIndex)
    if (position < 0) { normalizeSelectedAction(); return }
    selectedActionIndex = actionOrder[(position + delta + actionOrder.length) % actionOrder.length]
  }

  function navigateBack() {
    if (showDiagnostics || showFirewallRules) {
      showDiagnostics = false
      showFirewallRules = false
      focusNavigation()
    } else if (searchMode) {
      focusNavigation()
    } else if (projectStopSelected) {
      projectStopSelected = false
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
    if (selectedProjectRoot) {
      if (projectStopSelected) stopProject(selectedProjectRoot)
      else toggleProject(selectedProjectRoot)
      return
    }
    activateAction(selectedActionIndex, selectedServer())
  }

  function stopProject(projectRoot) {
    if (actionBusy || showDiagnostics || showFirewallRules || confirmDialog.opened) return
    if (groupByProject && groups[projectRoot]) projectStopRequested(projectRoot)
  }

  function activateAction(actionIndex, selected) {
    if (!actionEnabled(actionIndex, selected)) return
    if (actionIndex === Actions.ACTIONS.open) openRequested(selected)
    else if (actionIndex === Actions.ACTIONS.copyLocal) copyRequested(selected)
    else if (actionIndex === Actions.ACTIONS.copyLan) copyLanRequested(selected)
    else if (actionIndex === Actions.ACTIONS.qr) qrRequested(selected)
    else if (actionIndex === Actions.ACTIONS.terminal) terminalRequested(selected)
    else if (actionIndex === Actions.ACTIONS.project) projectRequested(selected)
    else if (actionIndex === Actions.ACTIONS.restart) restartRequested(selected)
    else if (actionIndex === Actions.ACTIONS.skip) {
      if (selected.serviceKey) skipServiceRequested(selected)
      else skipPortRequested(selected.port)
    }
    else if (actionIndex === Actions.ACTIONS.stop)
      requestStop(selected, selected.serverId === forceStopServerId && selected.source !== "docker")
  }

  function beginSearch() {
    if (showDiagnostics || showFirewallRules) return
    pendingVimPrefix = ""
    projectStopSelected = false
    Qt.callLater(function() { searchField.forceActiveFocus() })
  }

  function focusNavigation() {
    pendingVimPrefix = ""
    Qt.callLater(function() {
      if (!portFilterDropdown.popupOpen)
        keyCatcher.forceActiveFocus()
    })
  }

  function clearSearch() {
    query = ""
    searchField.text = ""
    focusNavigation()
  }

  function requestStop(server, force) {
    if (!server || actionBusy) return
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

  function handleVimKey(event) {
    // Pressing Shift between z and M/R is part of the command, not its suffix.
    if (event.key === Qt.Key_Shift || event.key === Qt.Key_Control
        || event.key === Qt.Key_Alt || event.key === Qt.Key_Meta || event.key === Qt.Key_AltGr)
      return false
    var prefix = pendingVimPrefix
    pendingVimPrefix = ""
    if (searchMode || showDiagnostics || showFirewallRules) return false
    var plain = event.modifiers === Qt.NoModifier
    var shifted = event.modifiers === Qt.ShiftModifier
    if (prefix && event.key === Qt.Key_Escape) return true
    if (prefix === "z" && groupByProject) {
      if (plain && (event.key === Qt.Key_C || event.key === Qt.Key_O)) {
        setProjectCollapsed(selectedProject(), event.key === Qt.Key_C)
        return true
      }
      if (plain && event.key === Qt.Key_A) {
        toggleProject(selectedProject())
        return true
      }
      if (shifted && (event.key === Qt.Key_M || event.key === Qt.Key_R)) {
        setAllProjectsCollapsed(event.key === Qt.Key_M)
        return true
      }
    }
    if (prefix === "g" && plain && event.key === Qt.Key_G) {
      selectEntry(0)
      return true
    }
    if (plain && (event.key === Qt.Key_G || (groupByProject && event.key === Qt.Key_Z))) {
      pendingVimPrefix = event.key === Qt.Key_G ? "g" : "z"
      return true
    }
    if (shifted && event.key === Qt.Key_G) {
      selectEntry(projectModel.count - 1)
      return true
    }
    if (groupByProject && shifted && (event.key === Qt.Key_J || event.key === Qt.Key_K)) {
      selectAdjacentProject(event.key === Qt.Key_K ? -1 : 1)
      return true
    }
    return false
  }

  function handleSearchKey(event) {
    if (portFilterDropdown.popupOpen) return
    if (confirmDialog.opened) {
      pendingVimPrefix = ""
      if (confirmDialog.handleKey(event)) event.accepted = true
      return
    }
      if (!searchMode) keyCatcher.forceActiveFocus()
    if (handleVimKey(event)) {
      event.accepted = true
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
    } else if (!searchMode && !control && !alternate && (groupByProject || failedRestart)
               && (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab)) {
      const backwards = event.key === Qt.Key_Backtab || shift
      const previousProject = selectedProjectRoot
      selectAdjacentProject(backwards ? -1 : 1)
      if (failedRestart && selectedProjectRoot === previousProject)
        (backwards ? dismissFailure : openLog).forceActiveFocus(Qt.TabFocusReason)
      event.accepted = true
    } else if (plainNavigation && (event.key === Qt.Key_Home || event.key === Qt.Key_End)) {
      selectEntry(event.key === Qt.Key_Home ? 0 : projectModel.count - 1)
      event.accepted = true
    } else if (plainNavigation && event.key === Qt.Key_Space && selectedProjectRoot) {
      if (projectStopSelected) stopProject(selectedProjectRoot)
      else toggleProject(selectedProjectRoot)
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
      let restart = selectedServer()
      if (actionEnabled(Actions.ACTIONS.restart, restart)) restartRequested(restart)
      event.accepted = true
    } else if (event.key === Qt.Key_Delete || (control && event.key === Qt.Key_K && query === "")) {
      let stopped = selectedServer()
      if (stopped) requestStop(stopped, stopped.serverId === forceStopServerId && stopped.source !== "docker")
      event.accepted = true
    } else if (control && event.key === Qt.Key_C && searchField.selectedText.length === 0) {
      let copied = selectedServer()
      let shareOverLan = (event.modifiers & Qt.ShiftModifier) !== 0
      if (actionEnabled(shareOverLan ? Actions.ACTIONS.copyLan : Actions.ACTIONS.copyLocal, copied)) {
        if (shareOverLan) copyLanRequested(copied)
        else copyRequested(copied)
      }
      event.accepted = true
    }
  }

  onRevisionChanged: Qt.callLater(rebuildFilteredModel)
  onServersChanged: Qt.callLater(rebuildFilteredModel)
  onPanelActiveChanged: { showActionHint = false; if (!panelActive) { portFilterDropdown.close() }; pendingVimPrefix = ""; projectStopSelected = false; if (panelActive) Qt.callLater(rebuildFilteredModel) }
  onSearchModeChanged: { showActionHint = false; pendingVimPrefix = ""; projectStopSelected = false }
  onSelectedProjectRootChanged: projectStopSelected = false
  onActionBusyChanged: if (actionBusy) projectStopSelected = false
  onShowDiagnosticsChanged: { showActionHint = false; projectStopSelected = false; portFilterDropdown.close() }
  onShowFirewallRulesChanged: { showActionHint = false; projectStopSelected = false; portFilterDropdown.close() }
  onGroupByProjectChanged: { rebuildFilteredModel(); ensureSelectedVisible() }
  onSelectedIndexChanged: { showActionHint = false; if (selectedIndex >= 0) selectedProjectRoot = "" }
  onQueryChanged: { filteredCollapsedProjects = ({}); rebuildFilteredModel(); ensureSelectedVisible() }
  onPortFilterChanged: { filteredCollapsedProjects = ({}); rebuildFilteredModel(); ensureSelectedVisible() }
  Component.onCompleted: { rebuildFilteredModel(); rebuildSkippedModel() }

  ListModel { id: filteredModel }
  ListModel { id: projectModel }
  ListModel { id: skippedModel }

  Shortcut {
    sequence: "Ctrl+L"
    enabled: root.panelActive && !!root.failedRestart && !confirmDialog.opened && !portFilterDropdown.popupOpen
    onActivated: root.openRestartLogRequested(root.failedRestart.logPath)
  }

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

      RowLayout {
        id: viewTabs
        Layout.fillWidth: true
        spacing: Style.space(3)
        Repeater {
          model: [
            { label: "Servers", icon: "\uf233" },
            { label: "Skipped", icon: "\uf05e" },
            { label: "Access", icon: "󰒘" }
          ]
          Button {
            required property int index
            required property var modelData
            objectName: "headerView" + index
            text: modelData.label
            iconText: modelData.icon
            foreground: root.foreground
            selected: index === (root.showDiagnostics ? 1 : (root.showFirewallRules ? 2 : 0))
            focusable: true
            fontSize: Style.font.caption
            horizontalPadding: Style.space(8)
            verticalPadding: Style.space(7)
            Accessible.role: Accessible.PageTab
            Accessible.name: modelData.label
            Accessible.selected: selected
            onClicked: {
              root.showDiagnostics = index === 1
              root.showFirewallRules = index === 2
              root.focusNavigation()
            }

          }
        }
        Item { Layout.fillWidth: true }
      }

      Button {
        objectName: "refreshServers"
        Layout.preferredHeight: viewTabs.implicitHeight
        Layout.preferredWidth: viewTabs.implicitHeight
        fontSize: Style.font.caption
        horizontalPadding: Style.space(8)
        verticalPadding: Style.space(7)
        iconText: "\uf2f9"
        tooltipText: "Refresh servers (Ctrl+R)"
        foreground: root.foreground
        focusable: true
        Accessible.name: "Refresh servers"
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
        placeholderText: "Search projects, branches or ports…"
        foreground: root.foreground
        text: root.query
        onTextChanged: {
          if (root.query !== text) root.query = text
        }
        onPressed: root.beginSearch()
        Keys.onPressed: function(event) { root.handleSearchKey(event) }
      }

      PortFilter {
        id: portFilterDropdown
        objectName: "portFilter"
        Layout.preferredWidth: Style.space(140)
        Layout.preferredHeight: searchField.implicitHeight
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
      id: memoryOverview
      objectName: "memoryOverview"
      visible: !root.showFirewallRules && !root.showDiagnostics
      Layout.fillWidth: true
      Layout.preferredHeight: memoryLayout.implicitHeight + Style.space(16)
      color: Style.controlFill(false, false, root.foreground, Theme.Color.accent)
      borderSpec: Border.controlSpec("normal", root.foreground, Theme.Color.accent)
      radius: Style.cornerRadius

      ColumnLayout {
        id: memoryLayout
        anchors.fill: parent
        anchors.margins: Style.space(8)
        spacing: Style.space(6)

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(6)
          InlineIcon {
            Layout.preferredWidth: Style.space(14)
            label: serversMemoryLabel
            text: "\uf233"
            color: root.dim
            paintedSize: Style.space(12)
          }
          Text {
            id: serversMemoryLabel
            text: "Servers"
            color: root.dim
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }
          Text {
            objectName: "trackedMemory"
            text: root.memoryStats.measured ? Memory.formatMemory(root.memoryStats.serverBytes) : "—"
            color: root.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }
          Item { Layout.fillWidth: true }
          InlineIcon {
            Layout.preferredWidth: Style.space(14)
            label: systemMemoryLabel
            text: "\uf108"
            color: root.dim
            paintedSize: Style.space(12)
          }
          Text {
            id: systemMemoryLabel
            text: "System"
            color: root.dim
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }
          Text {
            objectName: "totalMemory"
            text: Memory.formatMemory(root.memoryStats.totalBytes)
            color: root.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            Accessible.name: "Total system RAM: " + text
          }
        }

        Rectangle {
          id: memoryBar
          objectName: "memoryBar"
          Layout.fillWidth: true
          Layout.preferredHeight: Style.space(9)
          radius: height / 2
          color: root.memoryStats.totalBytes > 0 ? "transparent" : root.freeMemoryColor
          border.width: Math.max(1, Style.spacing.hairline)
          border.color: root.dim
          readonly property int hoveredSegment: {
            if (!root.panelActive || !visible || width <= 0) return -1
            if (!barHover.hovered) return -1
            var fraction = barHover.point.position.x / width
            var end = 0
            for (let index = 0; index < memoryCanvas.segments.length; index++) {
              end += memoryCanvas.segments[index].fraction
              if (fraction < end) return index
            }
            return -1
          }
          HoverHandler { id: barHover }

          Canvas {
            id: memoryCanvas
            anchors.fill: parent
            anchors.margins: memoryBar.border.width
            antialiasing: true
            property var segments: {
              var stats = root.memoryStats
              var parts = stats.sources.map(function(source) {
                return { fraction: stats.totalBytes > 0 ? source.barBytes / stats.totalBytes : 0,
                  color: root.colorForSource(source.key) }
              })
              parts.push({ fraction: stats.totalBytes > 0 ? stats.otherBytes / stats.totalBytes : 0,
                color: root.otherMemoryColor })
              parts.push({ fraction: stats.totalBytes > 0 ? stats.availableBytes / stats.totalBytes : 0,
                color: "transparent" })
              return parts
            }
            property int hoveredSegment: memoryBar.hoveredSegment
            onHoveredSegmentChanged: requestPaint()
            onSegmentsChanged: requestPaint()
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            onPaint: {
              var context = getContext("2d")
              context.clearRect(0, 0, width, height)
              if (width <= 0 || height <= 0) return
              var radius = Math.min(width, height) / 2
              context.save()
              context.beginPath()
              context.moveTo(radius, 0)
              context.lineTo(width - radius, 0)
              context.arc(width - radius, radius, radius, -Math.PI / 2, Math.PI / 2)
              context.lineTo(radius, height)
              context.arc(radius, radius, radius, Math.PI / 2, Math.PI * 1.5)
              context.closePath()
              context.clip()
              var offset = 0
              for (let index = 0; index < segments.length; index++) {
                let segmentWidth = width * segments[index].fraction
                context.globalAlpha = hoveredSegment < 0 || hoveredSegment === index ? 1 : 0.25
                context.fillStyle = String(hoveredSegment === index && index === segments.length - 1
                  ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.3)
                  : root.freeMemoryColor)
                context.fillRect(offset, 0, segmentWidth, height)
                context.fillStyle = String(segments[index].color)
                context.fillRect(offset, 0, segmentWidth, height)
                offset += segmentWidth
              }
              context.restore()
            }
          }

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
                color: "transparent"
                HoverHandler { id: segmentHover }
                PanelToolTip {
                  visible: segmentHover.hovered
                  text: sourceSegment.modelData.name + " · :" + sourceSegment.modelData.port
                    + " · " + Memory.formatMemory(sourceSegment.modelData.bytes)
                }
              }
            }
            Rectangle {
              objectName: "otherMemorySegment"
              width: root.memoryStats.totalBytes > 0
                ? memoryBar.width * root.memoryStats.otherBytes / root.memoryStats.totalBytes : 0
              height: memoryBar.height
              color: "transparent"
              HoverHandler { id: otherHover }
              PanelToolTip {
                visible: otherHover.hovered
                text: "Other apps and system · " + Memory.formatMemory(root.memoryStats.otherBytes)
              }
            }
            Rectangle {
              objectName: "freeMemorySegment"
              width: root.memoryStats.totalBytes > 0
                ? memoryBar.width * root.memoryStats.availableBytes / root.memoryStats.totalBytes : 0
              height: memoryBar.height
              color: "transparent"
              HoverHandler { id: freeHover }
              PanelToolTip {
                visible: freeHover.hovered
                text: "Free / available · " + Memory.formatMemory(root.memoryStats.availableBytes)
              }
            }
          }
        }
      }
    }

    RowLayout {
      visible: !root.showFirewallRules && !root.showDiagnostics
      Layout.fillWidth: true
      spacing: Style.space(8)
      Text {
        Layout.fillWidth: true
        text: (root.resultsFiltered ? root.resultCount + " of " + root.serverCount + " servers"
          : root.serverCount + " server" + (root.serverCount === 1 ? "" : "s"))
          + (root.groupByProject ? " · " + root.projectCount + " project" + (root.projectCount === 1 ? "" : "s") : "")
        color: root.dim
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
      Button {
        objectName: "groupToggle"
        text: "Group"
        iconText: root.groupByProject ? "\uf14a" : "\uf096"
        foreground: root.dim
        focusable: true
        fontSize: Style.font.caption
        horizontalPadding: Style.space(3)
        verticalPadding: Style.space(3)
        Accessible.role: Accessible.CheckBox
        Accessible.name: "Group by project"
        Accessible.checkable: true
        Accessible.checked: root.groupByProject
        onClicked: { root.groupByProject = !root.groupByProject; root.focusNavigation() }
      }
    }

    BorderSurface {
      visible: root.hasDiagnostics
      Layout.fillWidth: true
      Layout.preferredHeight: diagnosticText.implicitHeight + Style.space(14)
      color: Style.hoverFillFor(root.foreground, root.scanError ? Theme.Color.urgent : Theme.Color.accent)
      borderSpec: Border.controlSpec("normal", root.foreground, Theme.Color.accent)
      radius: Style.cornerRadius

      Text {
        textFormat: Text.PlainText
        id: diagnosticText
        anchors.fill: parent
        anchors.margins: Style.space(7)
        text: root.scanError || root.warnings.join("\n")
        maximumLineCount: 3
        elide: Text.ElideRight
        color: root.scanError ? Theme.Color.urgent : root.dim
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        wrapMode: Text.Wrap
      }
    }

    PanelScrollArea {
      id: accessList
      objectName: "firewallList"
      visible: root.showFirewallRules
      scrollBarGap: root.scrollBarGap
      model: root.firewallRules
      emptyText: "No LAN access rules yet.\nShare a server with QR to set up access."
      header: Item {
        width: accessList.viewportWidth
        height: accessSummary.implicitHeight + Style.space(8)
        Text {
          id: accessSummary
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.leftMargin: Style.space(8)
          anchors.rightMargin: Style.space(6)
          text: root.firewallRules.length + " LAN access rule" + (root.firewallRules.length === 1 ? "" : "s")
          color: root.dim
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
      }
      delegate: DetailRow {
        required property var modelData
        objectName: "accessRow"
        width: accessList.viewportWidth
        title: ":" + modelData.port
        detail: modelData.subnet + (modelData.interfaceName ? " · " + modelData.interfaceName : "")
        icon: "\uf0e8"
        foreground: root.foreground
        removable: true
        actionBusy: root.firewallBusy
        onRemoveRequested: root.requestFirewallRemoval(modelData)
      }
    }

    PanelScrollArea {
      id: discoveryList
      objectName: "diagnosticList"
      visible: root.showDiagnostics
      scrollBarGap: root.scrollBarGap
      model: skippedModel
      emptyText: root.scanning ? "Checking local ports…" : "No skipped ports in the latest scan."
      header: Item {
        width: discoveryList.viewportWidth
        height: discoverySummary.implicitHeight + Style.space(8)
        Text {
          id: discoverySummary
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.leftMargin: Style.space(8)
          anchors.rightMargin: Style.space(6)
          text: root.diagnostics.length + " skipped " + (root.diagnostics.length === 1 ? "entry" : "entries")
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          color: root.dim
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
      }
      delegate: Loader {
        id: skippedEntry
        required property var model
        width: discoveryList.viewportWidth
        height: item ? (item as Item).implicitHeight : 0
        sourceComponent: model.kind === "header" ? skippedHeaderComponent : skippedPortComponent

        Component {
          id: skippedHeaderComponent
          ProjectHeader {
            objectName: "skippedGroupHeader"
            projectRoot: ""
            name: skippedEntry.model.name
            count: skippedEntry.model.count
            countNoun: "item"
            collapsed: skippedEntry.model.collapsed
            showStopAction: false
            selected: root.selectedSkippedGroup === skippedEntry.model.groupId
            foreground: root.foreground
            onFocused: root.selectedSkippedGroup = skippedEntry.model.groupId
            onToggled: root.toggleSkippedGroup(skippedEntry.model.groupId, true)
            onNavigationKey: function(event) {
              if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space
                  || event.key === Qt.Key_Left || event.key === Qt.Key_Right) {
                event.accepted = true
                if ((event.key !== Qt.Key_Left && event.key !== Qt.Key_Right)
                    || (event.key === Qt.Key_Left && !collapsed) || (event.key === Qt.Key_Right && collapsed))
                  root.toggleSkippedGroup(skippedEntry.model.groupId, true)
              }
            }
          }
        }
        Component {
          id: skippedPortComponent
          DetailRow {
            readonly property var diagnostic: ({
              port: skippedEntry.model ? skippedEntry.model.port : 0,
              process: skippedEntry.model ? skippedEntry.model.process : "",
              reason: skippedEntry.model ? skippedEntry.model.reason : "",
              serviceKey: skippedEntry.model ? skippedEntry.model.serviceKey : "",
              detail: skippedEntry.model ? skippedEntry.model.detail : ""
            })
            readonly property var explanation: Diagnostics.skippedPortPresentation(diagnostic.reason)
            objectName: "discoveryRow"
            serviceRule: !!diagnostic.serviceKey
            title: serviceRule ? diagnostic.process : ":" + diagnostic.port
            detail: serviceRule ? diagnostic.detail : explanation.text
            wrapDetail: true
            trailingText: serviceRule ? "" : diagnostic.process || "Unknown process"
            icon: explanation.icon
            foreground: root.foreground
            includable: true
            manuallySkipped: serviceRule || diagnostic.reason === Diagnostics.REASONS.ignored
            included: root.includedPorts[diagnostic.port] === true && !manuallySkipped
            includeAvailable: diagnostic.reason !== Diagnostics.REASONS.metadataUnavailable
            includeHint: serviceRule ? "Restore this service on any port."
              : !includeAvailable ? "Process details are unavailable; refresh after the process can be inspected."
              : (included ? "Already included in detection. It must respond to HTTP or HTTPS to appear in Servers."
                : (manuallySkipped ? "Remove this port from your skipped ports and check it again."
                  : "Check this port even if normally excluded. It must respond to HTTP or HTTPS."))
            onIncludeRequested: {
              if (serviceRule) root.restoreServiceRequested(diagnostic.serviceKey, diagnostic.process)
              else root.includePortRequested(diagnostic.port)
            }
          }
        }
      }
    }

    Item {
      visible: !root.showFirewallRules && !root.showDiagnostics
      Layout.fillWidth: true
      Layout.fillHeight: true
      Layout.minimumHeight: 0
      Layout.preferredHeight: root.resultCount > 0 ? root.listHeight : Style.space(120)

      ListView {
        id: serverList
        objectName: "serverList"
        anchors.fill: parent
        anchors.rightMargin: serverScrollBar.width + root.scrollBarGap
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

        ScrollBar.vertical: ListScrollBar {
          id: serverScrollBar
          objectName: "serverScrollBar"
          parent: serverList.parent
          x: parent.width - width
          y: serverList.y
          height: serverList.height
          foreground: root.foreground
        }

        delegate: Loader {
          id: entryDelegate
          required property int index
          required property var model
          readonly property int serverIndex: model.serverIndex
          readonly property bool selected: index === root.selectedEntryIndex
          width: serverList.width
          height: item ? (item as Item).implicitHeight : 0
          sourceComponent: model.projectHeader ? projectHeaderComponent : serverRowComponent

          Component {
            id: projectHeaderComponent
            ProjectHeader {
              projectRoot: entryDelegate.model.projectRoot
              name: entryDelegate.model.name
              branch: entryDelegate.model.branch
              count: entryDelegate.model.count
              collapsed: entryDelegate.model.collapsed
              selected: entryDelegate.selected
              stopSelected: entryDelegate.selected && root.projectStopSelected
              stopHint: Actions.projectStopHint(root.groups[projectRoot])
              actionBusy: root.actionBusy
              stopping: root.stoppingProjectRoot === projectRoot
              foreground: root.foreground
              onToggled: root.toggleProject(projectRoot)
              onFocused: root.selectProject(projectRoot)
              onStopFocused: {
                root.selectProject(projectRoot)
                root.projectStopSelected = true
              }
              onStopRequested: root.stopProject(projectRoot)
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
                  ? Servers.normalizeServer(filteredModel.get(index)) : Servers.normalizeServer({})
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

      ListEdgeFades { anchors.fill: serverList; view: serverList }

      Column {
        visible: root.resultCount === 0
        anchors.centerIn: serverList
        width: serverList.width
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

    ServerActions {
      id: serverActions
      visible: !root.showFirewallRules && !root.showDiagnostics && root.resultCount > 0
      Layout.fillWidth: true
      server: root.currentServer
      selectedActionIndex: root.selectedActionIndex
      keyboardHints: root.showActionHint && root.panelActive
      forceStopAvailable: !!server && server.serverId === root.forceStopServerId && server.source !== "docker"
      actionBusy: root.actionBusy
      foreground: root.foreground
      onActionHovered: function(actionIndex) { root.showActionHint = false; root.selectedActionIndex = actionIndex }
      onActionTriggered: function(actionIndex) { root.activateAction(actionIndex, root.currentServer) }
    }

    Rectangle {
      id: restartFailure
      objectName: "restartFailureNotice"
      Layout.fillWidth: true
      implicitHeight: failureRow.implicitHeight + Style.space(14)
      visible: !!root.failedRestart
      radius: Style.cornerRadius
      color: Qt.alpha(Theme.Color.urgent, 0.07)
      border.color: Qt.alpha(Theme.Color.urgent, 0.28)
      RowLayout {
        id: failureRow
        anchors.fill: parent
        anchors.margins: Style.space(7)
        spacing: Style.space(7)
        ColumnLayout {
          Layout.fillWidth: true
          spacing: Style.space(2)
          Text {
            Layout.fillWidth: true
            text: root.failedRestart ? "Restart failed · " + root.failedRestart.label : ""
            textFormat: Text.PlainText
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            font.bold: true
            color: Theme.Color.urgent
            wrapMode: Text.Wrap
          }
          Text {
            Layout.fillWidth: true
            text: root.failedRestart ? root.failedRestart.message : ""
            textFormat: Text.PlainText
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            color: root.foreground
            wrapMode: Text.Wrap
          }
        }
        Button {
          id: openLog
          objectName: "openRestartLog"
          text: "Open log"
          iconText: "\uf121"
          focusable: true
          foreground: root.foreground
          fontSize: Style.font.caption
          horizontalPadding: Style.space(7)
          verticalPadding: Style.space(5)
          tooltipText: "Open restart log in editor (Ctrl+L)"
          Accessible.name: tooltipText
          onClicked: if (root.failedRestart) root.openRestartLogRequested(root.failedRestart.logPath)
        }
        PanelActionButton {
          id: dismissFailure
          objectName: "dismissRestartFailure"
          iconText: "\uf00d"
          focusable: true
          tooltipText: "Dismiss restart failure"
          Accessible.name: tooltipText
          onClicked: {
            root.dismissRestartFailureRequested()
            root.focusNavigation()
          }
        }
      }
    }

    Text {
      id: footerStatus
      objectName: "footerStatus"
      textFormat: Text.PlainText
      Layout.fillWidth: true
      text: root.notice !== "" ? root.notice.replace(/[\r\n]+/g, " ") : (root.showDiagnostics || root.showFirewallRules ? "Ctrl+R refresh · Esc back" : (root.selectedProjectRoot
        ? (root.projectStopSelected
          ? "enter stop all · ← / h back · j/k select · esc cancel"
          : "→ / l stop all · space fold · zc/zo fold · J/K project")
        : (root.groupByProject
          ? "↑↓ / j/k select · zc/zo fold · J/K project · / search"
          : "↑↓ select · ←→ action · enter run · / search")))
      color: root.notice !== "" && root.noticeUrgent ? Theme.Color.urgent : root.dim
      opacity: root.notice !== "" ? 1 : 0.66
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      horizontalAlignment: Text.AlignHCenter
      elide: Text.ElideRight
      maximumLineCount: 1
      wrapMode: Text.NoWrap
      HoverHandler { id: noticeHover }
      PanelToolTip {
        visible: noticeHover.hovered && root.notice !== "" && footerStatus.truncated
        text: root.notice
        width: Math.min(implicitWidth, Style.space(360))
      }
    }
  }

  ConfirmDialog {
    id: confirmDialog
    anchors.fill: parent
    z: 100
    background: Theme.Color.popups.background
    foreground: root.foreground
    selectedText: Theme.Color.accent
    fontFamily: Style.font.family
    onCanceled: root.cancelPendingAction()
    onConfirmed: root.confirmPendingAction()
  }

}
