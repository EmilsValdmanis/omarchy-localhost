import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "RadarModel.js" as RadarModel

BarWidget {
  id: root
  moduleName: "emils.localhost"

  property string notice: ""
  property bool noticeUrgent: false
  property var pendingQrServer: null
  property var pendingFirewallRule: null
  property var managedFirewallRules: []
  property string firewallCheckOutput: ""
  property string firewallRulesOutput: ""
  property string firewallError: ""
  property string forceStopServerId: ""

  readonly property int serverCount: radar.serverCount
  readonly property bool showCountBadge: setting("showCountBadge", true)
  readonly property bool showWhenEmpty: setting("showWhenEmpty", false)
  readonly property bool opened: card.open

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
    if (!server || !server.lanAvailable) return
    if (firewallCheckProcess.running || firewallAllowProcess.running || firewallRemoveProcess.running) {
      showNotice("LAN access setup is already running", false)
      return
    }

    pendingQrServer = server
    if (!setting("authorizeFirewallForQr", true)
        || radar.lanInterface === "" || radar.lanSubnet === "") {
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
      "pkexec", "/usr/bin/ufw", "allow", "in", "on", radar.lanInterface,
      "from", radar.lanSubnet, "to", "any", "port", String(server.port),
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

  // Shape contract used by `omarchy-shell shell toggle emils.localhost`.
  function open() { openPanel() }
  function close() { closePanel() }
  function toggle() { togglePanel() }

  RadarService {
    id: radar
    refreshIntervalSec: Math.max(1, Number(root.setting("refreshIntervalSec", 2)))
    includeDocker: root.setting("includeDocker", true)
    ignoredPorts: String(root.setting("ignoredPorts", "") || "")
    alwaysIncludePorts: String(root.setting("alwaysIncludePorts", "") || "")
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
    function refresh(): string { radar.scan(); root.refreshFirewallRules(); return "ok" }
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
        managedFirewallRules: root.managedFirewallRules
      })
    }
  }

  Process {
    id: firewallCheckProcess
    command: [
      "bash", "-c",
      "if ! command -v ufw >/dev/null || ! systemctl is-active --quiet ufw; then echo inactive; exit 0; fi; echo active; cat /etc/ufw/user.rules"
    ]
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
      if (!active || (exitCode === 0 && RadarModel.ufwAllowsPort(
          rules, radar.lanInterface, radar.lanSubnet, server.port))) {
        root.pendingQrServer = null
        root.showQr(server)
        return
      }
      panel.requestFirewallAuthorization(server)
    }
  }

  Process {
    id: firewallRulesProcess
    command: [
      "bash", "-c",
      "if ! command -v ufw >/dev/null || ! systemctl is-active --quiet ufw; then echo inactive; exit 0; fi; echo active; cat /etc/ufw/user.rules"
    ]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.firewallRulesOutput = String(text || "")
    }
    onExited: function(exitCode) {
      var active = exitCode === 0 && root.firewallRulesOutput.indexOf("active\n") === 0
      root.managedFirewallRules = active
        ? RadarModel.parseManagedUfwRules(root.firewallRulesOutput.slice(7), "omarchy-localhost")
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

  BarIconButton {
    id: button
    anchors.centerIn: parent
    bar: root.bar
    tooltipText: root.serverCount > 0
      ? "Localhost · " + root.serverCount + " server" + (root.serverCount === 1 ? "" : "s")
      : "Localhost · no servers"
    onPressed: function(mouseButton) {
      if (mouseButton === Qt.RightButton) {
        radar.scan()
        root.refreshFirewallRules()
      } else root.togglePanel()
    }

    iconComponent: Component {
      Item {
        OpticalGlyph {
          anchors.fill: parent
          text: "\uf0ac"
          fontFamily: button.fontFamily
          fontSize: button.fontSize
          color: Color.accent
        }

        Rectangle {
          visible: root.showCountBadge && root.serverCount > 0
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.rightMargin: -Style.space(2)
          anchors.topMargin: -Style.space(1)
          width: Math.max(Style.space(11), badgeText.implicitWidth + Style.space(4))
          height: Style.space(11)
          radius: height / 2
          color: Color.accent
          border.width: Math.max(1, Style.spacing.hairline)
          border.color: root.bar ? root.bar.background : Color.background

          Text {
            id: badgeText
            anchors.centerIn: parent
            text: root.serverCount > 9 ? "9+" : String(root.serverCount)
            color: Color.background
            font.family: Style.font.family
            font.pixelSize: Style.space(7)
            font.bold: true
          }
        }
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

    ServerPanel {
      id: panel
      anchors.fill: parent
      servers: radar.servers
      revision: radar.revision
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
        radar.scan()
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
