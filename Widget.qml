pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "qml" as Internal
import "qml/RadarModel.js" as RadarModel

BarWidget {
  id: root
  moduleName: "emils.localhost"

  property string notice: ""
  property bool noticeUrgent: false
  property var pendingQrServer: null
  property var pendingFirewallRule: null
  property var managedFirewallRules: []
  property bool firewallRulesUnreadable: false
  property string firewallCheckOutput: ""
  property string firewallRulesOutput: ""
  property string firewallError: ""
  property string forceStopServerId: ""

  readonly property int serverCount: radar.serverCount
  // Keep the existing setting key so saved preferences survive the badge removal.
  readonly property bool showServerCount: setting("showCountBadge", true)
  readonly property string countLabel: showServerCount && serverCount > 0 ? String(serverCount) : ""
  readonly property string glyph: "\uf0ac"
  readonly property bool showWhenEmpty: setting("showWhenEmpty", false)
  readonly property bool opened: card.open
  readonly property var firewallStatusCommand: [
    "bash", "-c",
    "if ! command -v ufw >/dev/null || ! systemctl is-active --quiet ufw; then echo inactive; exit 0; fi; echo active; cat /etc/ufw/user.rules 2>/dev/null || echo unreadable"
  ]

  visible: serverCount > 0 || showWhenEmpty
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onVisibleChanged: if (!visible) card.open = false

  function showNotice(message, urgent) {
    notice = String(message || "")
    noticeUrgent = urgent === true
    noticeTimer.restart()
  }

  function effectiveUrl(server) {
    return server && server.lanAvailable ? server.lanUrl : (server ? server.localUrl : "")
  }

  function openServer(server) {
    var url = effectiveUrl(server)
    if (url) Quickshell.execDetached(["omarchy-launch-browser", url])
  }

  function copyServer(server) {
    var url = effectiveUrl(server)
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
    if (firewallCheckProcess.running || firewallAllowProcess.running || firewallRemoveProcess.running) {
      showNotice("LAN access setup is already running", false)
      return
    }

    pendingQrServer = server
    if (!setting("authorizeFirewallForQr", true)
        || server.lanInterface === "" || server.lanSubnet === "") {
      var directServer = pendingQrServer
      pendingQrServer = null
      showQr(directServer)
      return
    }

    firewallCheckOutput = ""
    firewallError = ""
    showNotice("Checking LAN access…", false)
    firewallCheckProcess.running = true
  }

  function authorizeQrPort() {
    var server = pendingQrServer
    if (!server) return
    firewallError = ""
    showNotice("Authorizing LAN access for :" + server.port + "…", false)
    firewallAllowProcess.command = [
      "pkexec", "/usr/bin/ufw", "allow", "in", "on", server.lanInterface,
      "from", server.lanSubnet, "to", "any", "port", String(server.port),
      "proto", "tcp", "comment", "omarchy-localhost"
    ]
    firewallAllowProcess.running = true
  }

  function cancelFirewallAuthorization() {
    pendingQrServer = null
    showNotice("LAN access was not changed", false)
  }

  function refreshFirewallRules() {
    if (firewallRulesProcess.running) return
    firewallRulesOutput = ""
    firewallRulesProcess.running = true
  }

  function removeFirewallRule(rule) {
    if (!rule || firewallRemoveProcess.running || firewallAllowProcess.running) return
    pendingFirewallRule = rule
    firewallError = ""
    firewallRemoveProcess.command = [
      "pkexec", "/usr/bin/ufw", "--force", "delete", "allow", "in", "on",
      String(rule.interfaceName), "from", String(rule.subnet), "to", "any",
      "port", String(rule.port), "proto", "tcp", "comment", "omarchy-localhost"
    ]
    firewallRemoveProcess.running = true
    showNotice("Removing LAN access for :" + rule.port + "…", false)
  }

  function openPanel() {
    card.open = true
    radar.scan()
    refreshFirewallRules()
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
    alwaysIncludePorts: String(root.setting("alwaysIncludePorts", "") || "")
    selectedLanInterface: String(root.setting("lanInterface", "") || "")
    onActionFinished: function(action, successful, detail, serverId) {
      if (action === "stop" && !successful && detail.indexOf("did not stop cleanly") !== -1)
        root.forceStopServerId = serverId
      else if (successful && root.forceStopServerId === serverId)
        root.forceStopServerId = ""
      root.showNotice(detail, !successful)
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

  Component.onCompleted: refreshFirewallRules()

  IpcHandler {
    target: root.moduleName
    function open(): string { root.openPanel(); return "ok" }
    function close(): string { root.closePanel(); return "ok" }
    function toggle(): string { root.togglePanel(); return "ok" }
    function refresh(): string { radar.refresh(); root.refreshFirewallRules(); return "ok" }
    function status(): string {
      var detectedServers = []
      for (var index = 0; index < radar.servers.count; index++) {
        var server = radar.servers.get(index)
        detectedServers.push({
          id: server.serverId,
          name: server.name,
          framework: server.framework,
          port: server.port,
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
        managedFirewallRules: root.managedFirewallRules,
        firewallRulesUnreadable: root.firewallRulesUnreadable
      })
    }
  }

  Process {
    id: firewallCheckProcess
    command: root.firewallStatusCommand
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.firewallCheckOutput = String(text || "")
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.firewallError = String(text || "").trim()
    }
    onExited: function(exitCode) {
      var server = root.pendingQrServer
      if (!server) return
      var active = root.firewallCheckOutput.indexOf("active\n") === 0
      var rules = active ? root.firewallCheckOutput.slice(7) : ""
      var unreadable = rules.split(/\r?\n/).indexOf("unreadable") !== -1
      if (!active || (!unreadable && exitCode === 0 && RadarModel.ufwAllowsPort(
          rules, server.lanInterface, server.lanSubnet, server.port))) {
        root.pendingQrServer = null
        root.showQr(server)
        return
      }
      if (unreadable)
        root.showNotice("UFW rules could not be read; confirming LAN access for :" + server.port, false)
      panel.requestFirewallAuthorization(server)
    }
  }

  Process {
    id: firewallRulesProcess
    command: root.firewallStatusCommand
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.firewallRulesOutput = String(text || "")
    }
    onExited: function(exitCode) {
      var active = exitCode === 0 && root.firewallRulesOutput.indexOf("active\n") === 0
      var body = active ? root.firewallRulesOutput.slice(7) : ""
      var unreadable = body.split(/\r?\n/).indexOf("unreadable") !== -1
      root.firewallRulesUnreadable = active && unreadable
      root.managedFirewallRules = active && !unreadable
        ? RadarModel.parseManagedUfwRules(body, "omarchy-localhost")
        : []
    }
  }

  Process {
    id: firewallAllowProcess
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.firewallError = String(text || "").trim()
    }
    onExited: function(exitCode) {
      var server = root.pendingQrServer
      root.pendingQrServer = null
      root.refreshFirewallRules()
      if (exitCode === 0 && server) {
        root.showNotice("LAN access allowed for :" + server.port, false)
        root.showQr(server)
      } else {
        root.showNotice(root.firewallError || "LAN access was not authorized", true)
      }
    }
  }

  Process {
    id: firewallRemoveProcess
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.firewallError = String(text || "").trim()
    }
    onExited: function(exitCode) {
      var rule = root.pendingFirewallRule
      root.pendingFirewallRule = null
      root.refreshFirewallRules()
      if (exitCode === 0 && rule)
        root.showNotice("Removed LAN access for :" + rule.port, false)
      else
        root.showNotice(root.firewallError || "Could not remove the LAN access rule", true)
    }
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
        root.refreshFirewallRules()
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
      scanError: radar.scanError
      warnings: radar.warnings
      diagnostics: radar.diagnostics
      scanSummary: radar.scanSummary
      scanning: radar.scanning
      firewallRules: root.managedFirewallRules
      firewallBusy: firewallAllowProcess.running || firewallRemoveProcess.running
      forceStopServerId: root.forceStopServerId

      onCloseRequested: root.closePanel()
      onRefreshRequested: {
        radar.refresh()
        root.refreshFirewallRules()
      }
      onOpenRequested: function(server) { root.openServer(server) }
      onCopyRequested: function(server) { root.copyServer(server) }
      onQrRequested: function(server) { root.openQr(server) }
      onTerminalRequested: function(server) {
        Quickshell.execDetached(["uwsm-app", "--", "xdg-terminal-exec", "--dir=" + server.cwd])
      }
      onProjectRequested: function(server) {
        Quickshell.execDetached(["omarchy-launch-editor", server.cwd])
      }
      onRestartRequested: function(server) { radar.restart(server) }
      onStopRequested: function(server) { radar.stop(server) }
      onForceStopRequested: function(server) { radar.forceStop(server) }
      onFirewallAuthorizationConfirmed: function(server) {
        root.pendingQrServer = server
        root.authorizeQrPort()
      }
      onFirewallAuthorizationCanceled: root.cancelFirewallAuthorization()
      onFirewallRemovalConfirmed: function(rule) { root.removeFirewallRule(rule) }
    }
  }
}
