import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Ui

Item {
  id: root

  property var servers: null
  property int revision: 0
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
  readonly property color dim: Qt.darker(foreground, 1.45)
  readonly property int panelWidth: Style.space(500)
  readonly property int serverCount: servers ? servers.count : 0
  readonly property int resultCount: filteredModel.count
  readonly property int actionCount: 7
  readonly property real cardInset: Style.space(2)
  readonly property int listHeight: Math.min(serverList.contentHeight, Style.space(450))
  readonly property bool hasDiagnostics: scanError !== "" || warnings.length > 0

  implicitWidth: panelWidth
  implicitHeight: panelLayout.implicitHeight

  function serverObject(row) {
    if (!row) return null
    return {
      serverId: String(row.serverId || ""),
      name: String(row.name || "Development server"),
      framework: String(row.framework || "Dev server"),
      frameworkId: String(row.frameworkId || "server"),
      pid: Number(row.pid || 0),
      startTime: Number(row.startTime || 0),
      source: String(row.source || "process"),
      containerId: String(row.containerId || ""),
      port: Number(row.port || 0),
      cwd: String(row.cwd || ""),
      localUrl: String(row.localUrl || ""),
      lanUrl: String(row.lanUrl || ""),
      lanAvailable: row.lanAvailable === true,
      hint: String(row.hint || "")
    }
  }

  function matches(server, needle) {
    if (!needle) return true
    var haystack = [
      server.name, server.framework, server.frameworkId, server.port,
      server.cwd, server.localUrl, server.lanUrl, server.source,
      server.containerId
    ].join(" ").toLowerCase()
    return haystack.indexOf(needle) !== -1
  }

  function serversEqual(left, right) {
    return left.serverId === right.serverId
      && left.name === right.name
      && left.framework === right.framework
      && left.frameworkId === right.frameworkId
      && Number(left.pid) === Number(right.pid)
      && Number(left.startTime) === Number(right.startTime)
      && left.source === right.source
      && left.containerId === right.containerId
      && Number(left.port) === Number(right.port)
      && left.cwd === right.cwd
      && left.localUrl === right.localUrl
      && left.lanUrl === right.lanUrl
      && left.lanAvailable === right.lanAvailable
      && left.hint === right.hint
  }

  function filteredIndex(serverId) {
    for (var index = 0; index < filteredModel.count; index++)
      if (filteredModel.get(index).serverId === serverId) return index
    return -1
  }

  function rebuildFilteredModel() {
    var previous = selectedServer()
    var previousId = previous ? previous.serverId : ""
    var needle = query.trim().toLowerCase()
    var incoming = {}
    var filtered = []
    if (servers) {
      for (var index = 0; index < servers.count; index++) {
        var server = serverObject(servers.get(index))
        if (matches(server, needle)) {
          incoming[server.serverId] = true
          filtered.push(server)
        }
      }
    }

    for (var oldIndex = filteredModel.count - 1; oldIndex >= 0; oldIndex--)
      if (!incoming[filteredModel.get(oldIndex).serverId]) filteredModel.remove(oldIndex)

    for (var targetIndex = 0; targetIndex < filtered.length; targetIndex++) {
      var next = filtered[targetIndex]
      var currentIndex = filteredIndex(next.serverId)
      if (currentIndex === -1) {
        filteredModel.insert(targetIndex, next)
      } else {
        if (currentIndex !== targetIndex) filteredModel.move(currentIndex, targetIndex, 1)
        if (!serversEqual(filteredModel.get(targetIndex), next))
          filteredModel.set(targetIndex, next)
      }
    }

    selectedIndex = 0
    if (previousId) {
      for (var nextIndex = 0; nextIndex < filteredModel.count; nextIndex++) {
        if (filteredModel.get(nextIndex).serverId === previousId) {
          selectedIndex = nextIndex
          break
        }
      }
    }
    normalizeSelectedAction(1)
    ensureSelectedVisible()
  }

  function selectedServer() {
    if (selectedIndex < 0 || selectedIndex >= filteredModel.count) return null
    return serverObject(filteredModel.get(selectedIndex))
  }

  function ensureSelectedVisible() {
    Qt.callLater(function() {
      if (filteredModel.count > 0)
        serverList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
    })
  }

  function select(delta) {
    if (!filteredModel.count) return
    selectedIndex = (selectedIndex + delta + filteredModel.count) % filteredModel.count
    normalizeSelectedAction(delta < 0 ? -1 : 1)
    ensureSelectedVisible()
  }

  function actionEnabled(actionIndex, server) {
    return !!server && (actionIndex !== 2 || server.lanAvailable)
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
    } else {
      closeRequested()
    }
  }

  function activateSelected() {
    if (showDiagnostics || showFirewallRules) return
    var selected = selectedServer()
    if (!actionEnabled(selectedActionIndex, selected)) return
    if (selectedActionIndex === 0) openRequested(selected)
    else if (selectedActionIndex === 1) copyRequested(selected)
    else if (selectedActionIndex === 2) qrRequested(selected)
    else if (selectedActionIndex === 3) terminalRequested(selected)
    else if (selectedActionIndex === 4) projectRequested(selected)
    else if (selectedActionIndex === 5) restartRequested(selected)
    else if (selectedActionIndex === 6)
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
    rebuildFilteredModel()
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

  onRevisionChanged: rebuildFilteredModel()
  onQueryChanged: rebuildFilteredModel()
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
    spacing: Style.space(10)

    RowLayout {
      Layout.fillWidth: true
      spacing: Style.space(8)

      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          text: "LOCALHOST"
          color: root.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.heading
          font.bold: true
          font.letterSpacing: 1.2
        }

        Text {
          Layout.fillWidth: true
          text: root.serverCount + " server" + (root.serverCount === 1 ? "" : "s")
            + (root.lanIp ? "  ·  " + root.lanIp : "")
          color: root.dim
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
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

    TextField {
      id: searchField
      visible: !root.showFirewallRules && !root.showDiagnostics
      Layout.fillWidth: true
      placeholderText: "Search projects, frameworks, ports, or paths…"
      foreground: root.foreground
      text: root.query
      onTextChanged: {
        if (root.query !== text) root.query = text
      }
      onPressed: root.beginSearch()
      Keys.onPressed: function(event) { root.handleSearchKey(event) }
    }

    Rectangle {
      Layout.fillWidth: true
      height: Math.max(1, Style.spacing.hairline)
      color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.14)
    }

    BorderSurface {
      visible: root.hasDiagnostics
      Layout.fillWidth: true
      Layout.preferredHeight: diagnosticText.implicitHeight + Style.space(14)
      color: Style.hoverFillFor(root.foreground, root.scanError ? Color.urgent : Color.accent)
      borderSpec: Border.controlSpec("normal", root.foreground, Color.accent)
      radius: Style.cornerRadius

      Text {
        id: diagnosticText
        anchors.fill: parent
        anchors.margins: Style.space(7)
        text: root.scanError || root.warnings.join("\n")
        color: root.scanError ? Color.urgent : root.dim
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        wrapMode: Text.Wrap
      }
    }

    ColumnLayout {
      visible: root.showFirewallRules
      Layout.fillWidth: true
      spacing: Style.space(6)

      Text {
        Layout.fillWidth: true
        text: "LAN ACCESS RULES"
        color: root.dim
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        font.bold: true
        font.letterSpacing: 0.8
      }

      Repeater {
        model: root.firewallRules

        CursorSurface {
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
              text: ":" + modelData.port
              color: root.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              font.bold: true
            }

            Text {
              Layout.fillWidth: true
              text: modelData.subnet + (modelData.interfaceName ? "  ·  " + modelData.interfaceName : "")
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
              onClicked: root.requestFirewallRemoval(modelData)
            }
          }
        }
      }
    }

    ColumnLayout {
      visible: root.showDiagnostics
      Layout.fillWidth: true
      spacing: Style.space(6)

      Text {
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
              text: ":" + modelData.port
              color: root.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              font.bold: true
            }
            Text {
              Layout.preferredWidth: Style.space(90)
              text: modelData.process
              color: root.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }
            Text {
              Layout.fillWidth: true
              text: modelData.reason
              color: root.dim
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }
          }
        }
      }

      Text {
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
      Layout.preferredHeight: root.resultCount > 0 ? Math.max(Style.space(80), root.listHeight) : Style.space(120)

      ListView {
        id: serverList
        anchors.fill: parent
        visible: root.resultCount > 0
        model: filteredModel
        clip: true
        spacing: Style.space(8)
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        currentIndex: root.selectedIndex

        ScrollBar.vertical: ScrollBar {
          id: serverScrollBar
          policy: serverList.contentHeight > serverList.height
            ? ScrollBar.AlwaysOn
            : ScrollBar.AlwaysOff
          width: Style.space(8)
          padding: Style.space(2)
          interactive: true

          contentItem: Rectangle {
            implicitWidth: Style.space(3)
            implicitHeight: Style.space(32)
            radius: width / 2
            color: root.foreground
            opacity: serverScrollBar.pressed
              ? 0.82
              : (serverScrollBar.hovered ? 0.64 : 0.46)
          }

          background: Item {}
        }

        delegate: Item {
          id: cardWrapper
          required property int index
          required property string serverId
          required property string name
          required property string framework
          required property string frameworkId
          required property int pid
          required property double startTime
          required property string source
          required property string containerId
          required property int port
          required property string cwd
          required property string localUrl
          required property string lanUrl
          required property bool lanAvailable
          required property string hint

          width: serverList.width
            - (serverScrollBar.visible ? serverScrollBar.width + Style.space(4) : 0)
          height: serverCard.implicitHeight

          ServerRow {
            id: serverCard
            x: root.cardInset
            width: parent.width - root.cardInset * 2
            index: cardWrapper.index
            serverId: cardWrapper.serverId
            name: cardWrapper.name
            framework: cardWrapper.framework
            frameworkId: cardWrapper.frameworkId
            pid: cardWrapper.pid
            startTime: cardWrapper.startTime
            source: cardWrapper.source
            containerId: cardWrapper.containerId
            port: cardWrapper.port
            cwd: cardWrapper.cwd
            localUrl: cardWrapper.localUrl
            lanUrl: cardWrapper.lanUrl
            lanAvailable: cardWrapper.lanAvailable
            hint: cardWrapper.hint
          }
        }
      }

      MouseArea {
        anchors.fill: parent
        z: 100
        acceptedButtons: Qt.NoButton
        hoverEnabled: false
        onWheel: function(wheel) {
          if (!serverList.interactive) return
          var pixelDelta = wheel.pixelDelta.y
          var distance = pixelDelta !== 0 ? -pixelDelta * 1.5 : -wheel.angleDelta.y * 1.25
          var maximum = Math.max(0, serverList.contentHeight - serverList.height)
          serverList.cancelFlick()
          serverList.contentY = Math.max(0, Math.min(maximum, serverList.contentY + distance))
          wheel.accepted = true
        }
      }

      Column {
        visible: root.resultCount === 0
        anchors.centerIn: parent
        width: parent.width
        spacing: Style.space(6)

        Text {
          width: parent.width
          text: root.query ? "No projects match “" + root.query + "”" : (root.scanning ? "Looking for development servers…" : "No development servers found")
          color: root.foreground
          opacity: 0.75
          font.family: Style.font.family
          font.pixelSize: Style.font.title
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.Wrap
        }

        Text {
          visible: !root.query && !root.scanning
          width: parent.width
          text: "Start a server or press Ctrl+R to scan again."
          color: root.dim
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          horizontalAlignment: Text.AlignHCenter
        }
      }
    }

    Text {
      visible: root.notice !== ""
      Layout.fillWidth: true
      text: root.notice
      color: root.noticeUrgent ? Color.urgent : root.dim
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      wrapMode: Text.Wrap
      horizontalAlignment: Text.AlignHCenter
    }

    Text {
      Layout.fillWidth: true
      text: "j/k card  ·  h/l action  ·  enter run  ·  / search"
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

  component ServerRow: CursorSurface {
    id: row
    required property int index
    required property string serverId
    required property string name
    required property string framework
    required property string frameworkId
    required property int pid
    required property double startTime
    required property string source
    required property string containerId
    required property int port
    required property string cwd
    required property string localUrl
    required property string lanUrl
    required property bool lanAvailable
    required property string hint

    readonly property var server: root.serverObject(row)
    readonly property string effectiveUrl: lanAvailable ? lanUrl : localUrl
    readonly property color statusDotColor: lanAvailable ? Color.accent : Color.urgent
    readonly property color statusTextColor: lanAvailable ? Color.accent : root.dim
    readonly property string statusTooltip: lanAvailable
      ? row.hint
      : "Bound to localhost only.\nStart with --host / 0.0.0.0 to use it from another device."
    readonly property bool forceStopAvailable: row.serverId === root.forceStopServerId && row.source !== "docker"
    readonly property var frameworkIcons: ({
      next: "", vite: "", svelte: "", astro: "", nuxt: "",
      angular: "", react: "", vue: "", solid: "", qwik: "",
      remix: "", gatsby: "", ember: "", eleventy: "", expo: "",
      electron: "", tauri: "", webpack: "", storybook: "",
      cloudflare: "", azure: "", firebase: "", supabase: "",
      graphql: "", prisma: "", bun: "", deno: "", node: "", docker: "",
      express: "", nestjs: "", adonis: "", python: "",
      django: "", fastapi: "", flask: "", streamlit: "",
      jupyter: "", ruby: "", rails: "", php: "", laravel: "",
      symfony: "", wordpress: "", elixir: "", phoenix: "",
      rust: "", go: "", java: "", spring: "", quarkus: "",
      dotnet: "", grafana: "", prometheus: ""
    })
    readonly property bool hasFrameworkIcon: !!frameworkIcons[frameworkId]
    readonly property string frameworkIcon: hasFrameworkIcon
      ? frameworkIcons[frameworkId]
      : (framework.length ? framework.charAt(0).toUpperCase() : "?")

    hasCursor: index === root.selectedIndex
    bordered: true
    foreground: root.foreground
    borderSpec: Border.flat(
      hasCursor
        ? Style.hoverBorderFor(root.foreground, Color.accent)
        : Style.normalBorderFor(root.foreground, Color.accent),
      Math.max(1, hasCursor ? Style.hoverBorderWidth : Style.normalBorderWidth))
    implicitHeight: rowContent.implicitHeight + Style.space(20)

    HoverHandler {
      onHoveredChanged: if (hovered) root.selectedIndex = row.index
    }

    ColumnLayout {
      id: rowContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(12)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      RowLayout {
        Layout.fillWidth: true
        spacing: Style.space(8)

        BorderSurface {
          Layout.preferredWidth: Style.space(36)
          Layout.preferredHeight: Style.space(36)
          Layout.alignment: Qt.AlignTop
          color: Style.selectedFillFor(root.foreground, Color.accent)
          radius: Style.cornerRadius

          OpticalGlyph {
            visible: row.hasFrameworkIcon
            anchors.fill: parent
            text: row.frameworkIcon
            color: Color.accent
            fontFamily: Style.font.family
            fontSize: Math.round(Style.font.heading * 1.25)
          }

          Text {
            visible: !row.hasFrameworkIcon
            anchors.centerIn: parent
            text: row.frameworkIcon
            color: Color.accent
            font.family: Style.font.family
            font.pixelSize: Style.font.heading
            font.bold: true
          }
        }

        ColumnLayout {
          Layout.fillWidth: true
          Layout.alignment: Qt.AlignTop
          spacing: 0

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(6)

            Text {
              Layout.fillWidth: true
              text: row.name
              color: root.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              font.bold: true
              elide: Text.ElideRight
            }

            Item {
              id: status
              implicitWidth: statusContent.implicitWidth
              implicitHeight: statusContent.implicitHeight
              Layout.alignment: Qt.AlignVCenter

              Row {
                id: statusContent
                spacing: Style.space(4)
                Rectangle {
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(5)
                  height: width
                  radius: width / 2
                  color: row.statusDotColor
                }
                Text {
                  text: row.lanAvailable ? "LAN ready" : "Local only"
                  color: row.statusTextColor
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  font.weight: Font.Medium
                }
              }

              HoverHandler { id: statusHover }
              PanelToolTip {
                visible: statusHover.hovered
                text: row.statusTooltip
                fontFamily: Style.font.family
              }
            }
          }

          Text {
            Layout.fillWidth: true
            text: row.framework + "  ·  :" + row.port
            color: root.dim
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
        }
      }

      Text {
        Layout.fillWidth: true
        text: row.effectiveUrl
        color: row.lanAvailable ? root.foreground : root.dim
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        elide: Text.ElideMiddle
      }

      RowLayout {
        Layout.fillWidth: true
        spacing: Style.space(4)

        Button {
          text: "Open"
          foreground: root.foreground
          bordered: true
          hasCursor: row.index === root.selectedIndex && root.selectedActionIndex === 0
          onHovered: function(on) { if (on) root.setActionCursor(row.index, 0) }
          onClicked: root.openRequested(row.server)
        }
        Button {
          text: "Copy"
          foreground: root.foreground
          hasCursor: row.index === root.selectedIndex && root.selectedActionIndex === 1
          onHovered: function(on) { if (on) root.setActionCursor(row.index, 1) }
          onClicked: root.copyRequested(row.server)
        }
        Button {
          text: "QR"
          foreground: row.lanAvailable ? root.foreground : root.dim
          accent: Color.accent
          active: row.lanAvailable
          enabled: row.lanAvailable
          hasCursor: row.index === root.selectedIndex && root.selectedActionIndex === 2
          tooltipText: row.lanAvailable ? "Open phone-ready QR code" : "Bind the server to 0.0.0.0 first"
          onHovered: function(on) { if (on) root.setActionCursor(row.index, 2) }
          onClicked: root.qrRequested(row.server)
        }

        Item { Layout.fillWidth: true }

        PanelActionButton {
          iconText: "\uf120"
          tooltipText: "Open terminal here"
          foreground: root.foreground
          hasCursor: row.index === root.selectedIndex && root.selectedActionIndex === 3
          bordered: hasCursor
          onHovered: function(on) { if (on) root.setActionCursor(row.index, 3) }
          onClicked: root.terminalRequested(row.server)
        }
        PanelActionButton {
          iconText: "\uf121"
          tooltipText: "Open project in editor"
          foreground: root.foreground
          hasCursor: row.index === root.selectedIndex && root.selectedActionIndex === 4
          bordered: hasCursor
          onHovered: function(on) { if (on) root.setActionCursor(row.index, 4) }
          onClicked: root.projectRequested(row.server)
        }
        PanelActionButton {
          iconText: "\uf2f9"
          tooltipText: "Restart server (Alt+R)"
          foreground: root.foreground
          hasCursor: row.index === root.selectedIndex && root.selectedActionIndex === 5
          bordered: hasCursor
          onHovered: function(on) { if (on) root.setActionCursor(row.index, 5) }
          onClicked: root.restartRequested(row.server)
        }
        PanelActionButton {
          iconText: row.forceStopAvailable ? "\uf714" : "\uf04d"
          tooltipText: row.forceStopAvailable ? "Force stop server" : "Stop server"
          foreground: Color.urgent
          hoverColor: Color.urgent
          hasCursor: row.index === root.selectedIndex && root.selectedActionIndex === 6
          bordered: hasCursor
          onHovered: function(on) { if (on) root.setActionCursor(row.index, 6) }
          onClicked: root.requestStop(row.server, row.forceStopAvailable)
        }
      }
    }
  }
}
