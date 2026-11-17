pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "qml" as Internal
import "qml/Actions.js" as Actions
import "qml/Diagnostics.js" as Diagnostics
import "qml/Paths.js" as Paths
import "qml/Ports.js" as Ports
import "qml/Sources.js" as Sources

BarWidget {
  id: root
  moduleName: "emils.localhost"

  property string notice: ""
  property bool noticeUrgent: false

  readonly property int serverCount: radar.serverCount
  // Keep the existing setting key so saved preferences survive the badge removal.
  readonly property bool showServerCount: setting("showCountBadge", true)
  readonly property string countLabel: showServerCount && serverCount > 0 ? String(serverCount) : ""
  readonly property string glyph: "\uf0ac"
  readonly property bool showWhenEmpty: setting("showWhenEmpty", false)
  readonly property bool hasManagedSkippedPorts: {
    var included = Ports.parsePortSet(setting("alwaysIncludePorts", ""))
    return radar.diagnostics.some(function(entry) {
      return entry.reason === Diagnostics.REASONS.ignored || entry.serviceKey || included[entry.port] === true
    })
  }
  readonly property bool opened: card.open

  visible: serverCount > 0 || showWhenEmpty || hasManagedSkippedPorts || radar.actionName === "restart" || !!radar.failedRestart
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onVisibleChanged: if (!visible) card.open = false

  function showNotice(message, urgent) {
    notice = String(message || "")
    noticeUrgent = urgent === true
    noticeTimer.restart()
  }

  // The host injects a capability-scoped facade; BarWidget types it as QObject.
  function settingsApiFor(host) { return host ? host.shell : null }

  function savePreferences(next, preference) {
    var api = settingsApiFor(bar)
    if (api && typeof api.updateEntryInline === "function" && api.updateEntryInline(moduleName, next)) return true
    showNotice("Could not save the " + preference + " preference.", true)
    return false
  }

  function setServiceSkipped(key, name, cwd, skip) {
    if (!key || (!!radar.skippedServices[key] === skip)) return
    var rules = Object.assign({}, radar.skippedServices)
    if (skip) rules[key] = { name: name, cwd: cwd }
    else delete rules[key]
    if (savePreferences(Object.assign({}, root.settings, { skippedServices: rules }), "service"))
      showNotice((skip ? "Skipped " : "Restored ") + name, false)
  }

  function setPortIncluded(port, include) {
    var next = Ports.portPreferenceSettings(root.settings, port, include)
    if (!next) return
    var changed = next.ignoredPorts !== String(setting("ignoredPorts", ""))
      || next.alwaysIncludePorts !== String(setting("alwaysIncludePorts", ""))
    if (changed && !savePreferences(next, "port")) return
    radar.refresh()
    showNotice(include ? "Checking :" + port + " · must respond to HTTP or HTTPS"
      : "Skipped :" + port + " · server is still running", false)
  }

  function openServer(server) {
    var url = Actions.actionUrl(server, false)
    if (url) Quickshell.execDetached(["omarchy-launch-browser", url])
  }

  function copyServer(server, shareOverLan) {
    var url = Actions.actionUrl(server, shareOverLan === true)
    if (!url) return
    Quickshell.execDetached(["wl-copy", url])
    showNotice("Copied " + url, false)
  }

  function showQr(server) {
    card.open = false
    var payload = JSON.stringify({
      name: server.name,
      framework: server.framework,
      url: server.lanUrl,
      port: server.port
    })
    Qt.callLater(function() {
      Quickshell.execDetached(["omarchy-shell", "shell", "summon", root.moduleName, payload])
    })
  }

  function openQr(server) {
    if (!server) return
    if (!server.lanAvailable) {
      showNotice("Bind the server to 0.0.0.0 to share it over the LAN", true)
      return
    }
    firewall.requestQr(server, setting("authorizeFirewallForQr", true))
  }

  function openPanel() {
    card.open = true
    radar.scan()
    firewall.refresh()
  }

  function closePanel() { card.open = false }
  function togglePanel() {
    if (card.open) closePanel()
    else openPanel()
  }

  // Direct IPC contract used by `omarchy-shell emils.localhost toggle`.
  function open() { openPanel() }
  function close() { closePanel() }
  function toggle() { togglePanel() }

  Internal.RadarService {
    id: radar
    objectName: "localhostRadarService"
    refreshIntervalSec: Math.min(30, Math.max(1, Number(root.setting("refreshIntervalSec", 2)) || 2))
    includeDocker: root.setting("includeDocker", true)
    ignoredPorts: String(root.setting("ignoredPorts", "") || "")
    skippedServices: Sources.savedServices(root.setting("skippedServices", {}))
    alwaysIncludePorts: String(root.setting("alwaysIncludePorts", "") || "")
    selectedLanInterface: String(root.setting("lanInterface", "") || "")
    panelActive: card.open
    onActionFinished: function(action, successful, detail, serverId) {
      if (action === "restart" && !successful && radar.failedRestart && radar.failedRestart.serverId === serverId) return
      if (radar.stoppingProjectRoot === "") root.showNotice(detail, !successful)
    }
  }

  Internal.CommandProcess {
    id: restartLogCheck
    onCompleted: function(exitCode) {
      if (exitCode === 0)
        Quickshell.execDetached(["omarchy-launch-editor", command[2]])
      else
        root.showNotice("The restart log is no longer available.", true)
    }
  }

  Timer {
    id: noticeTimer
    interval: 2800
    repeat: false
    onTriggered: {
      root.notice = ""
      root.noticeUrgent = false
    }
  }

  IpcHandler {
    target: root.moduleName
    function open(): string { root.openPanel(); return "ok" }
    function close(): string { root.closePanel(); return "ok" }
    function toggle(): string { root.togglePanel(); return "ok" }
    function refresh(): string { radar.refresh(); firewall.refresh(); return "ok" }
    function status(): string {
      var detectedServers = []
      for (let index = 0; index < radar.servers.count; index++) {
        let server = radar.servers.get(index)
        detectedServers.push({
          id: server.serverId,
          name: server.name,
          framework: server.framework,
          port: server.port,
          cwdDeleted: server.cwdDeleted,
          localUrl: server.localUrl,
          lanUrl: server.lanUrl,
          lanInterface: server.lanInterface,
          lanSubnet: server.lanSubnet,
          restartAvailable: server.restartAvailable,
          restartReason: server.restartReason,
          source: server.source
        })
      }
      return JSON.stringify({
        serverCount: root.serverCount,
        servers: detectedServers,
        scanning: radar.scanning,
        scanError: radar.scanError,
        warnings: radar.warnings,
        diagnostics: radar.diagnostics,
        scanSummary: radar.scanSummary,
        lanIp: radar.lanIp,
        lanInterface: radar.lanInterface,
        lanSubnet: radar.lanSubnet,
        managedFirewallRules: firewall.managedRules,
        firewallRulesUnreadable: firewall.rulesUnreadable
      })
    }
  }

  Internal.FirewallService {
    id: firewall
    onNoticeRequested: function(message, urgent) { root.showNotice(message, urgent) }
    onAuthorizationRequested: function(server) { panel.requestFirewallAuthorization(server) }
    onQrReady: function(server) { root.showQr(server) }
  }

  WidgetButton {
    id: button
    objectName: "localhostBarButton"
    anchors.fill: parent
    bar: root.bar
    text: root.vertical ? "" : root.glyph + (root.countLabel ? " " + root.countLabel : "")
    labelVisible: !root.vertical
    hasVisualContent: true
    fixedHeight: root.vertical
      ? (root.countLabel ? 2 : 1) * Style.bar.iconSlot : -1
    tooltipText: root.serverCount > 0
      ? "Localhost · " + root.serverCount + " server" + (root.serverCount === 1 ? "" : "s")
      : "Localhost · no servers"
    onPressed: function(mouseButton) {
      if (mouseButton === Qt.RightButton) {
        radar.refresh()
        firewall.refresh()
      } else root.togglePanel()
    }

    Column {
      visible: root.vertical
      anchors.fill: parent

      OpticalGlyph {
        width: button.width
        height: Style.bar.iconSlot
        text: root.glyph
        fontFamily: button.fontFamily
        fontSize: Style.font.icon
        color: button.foreground
      }

      Text {
        visible: root.countLabel !== ""
        width: button.width
        height: Style.bar.iconSlot
        textFormat: Text.PlainText
        text: root.countLabel
        color: button.foreground
        font.family: button.fontFamily
        font.pixelSize: button.fontSize
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
      }
    }
  }

  KeyboardPanel {
    id: card
    anchorItem: button
    bar: root.bar
    owner: root
    focusTarget: panel.keyboardFocusTarget
    contentWidth: fittedContentWidth(panel.implicitWidth, Style.space(560))
    contentHeight: fittedContentHeight(panel.implicitHeight, Style.space(680))

    Internal.ServerPanel {
      id: panel
      anchors.fill: parent
      panelActive: card.open
      servers: radar.servers
      revision: radar.revision
      systemMemory: radar.systemMemory
      lanIp: radar.lanIp
      notice: root.notice
      noticeUrgent: root.noticeUrgent
      failedRestart: radar.failedRestart
      onOpenRestartLogRequested: function(path) { restartLogCheck.start(["test", "-r", path]) }
      onDismissRestartFailureRequested: radar.failedRestart = null
      scanError: radar.scanError
      warnings: radar.warnings
      diagnostics: radar.diagnostics
      includedPorts: Ports.parsePortSet(root.setting("alwaysIncludePorts", ""))
      scanSummary: radar.scanSummary
      scanning: radar.scanning
      firewallRules: firewall.managedRules
      firewallBusy: firewall.mutationBusy
      forceStopServerId: currentServer && radar.forceStopSourceKeys[Sources.key(currentServer)]
        ? currentServer.serverId : ""

      onCloseRequested: root.closePanel()
      onIncludePortRequested: function(port) { root.setPortIncluded(port, true) }
      onSkipPortRequested: function(port) { root.setPortIncluded(port, false) }
      onSkipServiceRequested: function(server) { root.setServiceSkipped(server.serviceKey, server.serviceName, server.cwd, true) }
      onRestoreServiceRequested: function(key, name) { root.setServiceSkipped(key, name, "", false) }
      onRefreshRequested: {
        radar.refresh()
        firewall.refresh()
      }
      onOpenRequested: function(server) { root.openServer(server) }
      onCopyRequested: function(server) { root.copyServer(server, false) }
      onCopyLanRequested: function(server) { root.copyServer(server, true) }
      onQrRequested: function(server) { root.openQr(server) }
      onTerminalRequested: function(server) {
        Quickshell.execDetached(["uwsm-app", "--", "xdg-terminal-exec", "--dir=" + server.cwd])
      }
      onProjectRequested: function(server) {
        Quickshell.execDetached(["omarchy-launch-editor", server.cwd])
      }
      onRestartRequested: function(server) { radar.restart(server) }
      onStopRequested: function(server) { radar.stop(server) }
      actionBusy: radar.actionBusy
      stoppingProjectRoot: radar.stoppingProjectRoot
      onProjectStopRequested: function(projectRoot) {
        if (radar.stopProject(projectRoot))
          root.showNotice("Stopping all servers in " + Paths.basename(projectRoot) + "…", false)
      }
      onForceStopRequested: function(server) { radar.forceStop(server) }
      onFirewallAuthorizationConfirmed: function(server) {
        firewall.authorize(server)
      }
      onFirewallAuthorizationCanceled: firewall.cancelAuthorization()
      onFirewallRemovalConfirmed: function(rule) { firewall.remove(rule) }
    }
  }
}
