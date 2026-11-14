import QtQuick
import "Firewall.js" as Firewall

Item {
  id: root
  visible: false
  property var managedRules: []
  property bool rulesUnreadable: false
  property var pendingServer: null
  property var pendingRule: null
  readonly property bool mutationBusy: allowProcess.busy || removeProcess.busy
  readonly property bool busy: checkProcess.busy || mutationBusy

  signal noticeRequested(string message, bool urgent)
  signal authorizationRequested(var server)
  signal qrReady(var server)

  function requestQr(server, authorize) {
    if (!server) return
    if (busy) {
      noticeRequested("LAN access setup is already running", false)
      return
    }
    pendingServer = server
    if (!authorize || server.lanInterface === "" || server.lanSubnet === "") {
      pendingServer = null
      qrReady(server)
      return
    }
    noticeRequested("Checking LAN access…", false)
    checkProcess.start()
  }

  function authorize(server) {
    if (!server || mutationBusy) return
    pendingServer = server
    noticeRequested("Authorizing LAN access for :" + server.port + "…", false)
    allowProcess.start(Firewall.commandFor({ interfaceName: server.lanInterface, subnet: server.lanSubnet, port: server.port }, false))
  }

  function cancelAuthorization() {
    pendingServer = null
    noticeRequested("LAN access was not changed", false)
  }

  function refresh() { if (!rulesProcess.busy) rulesProcess.start() }

  function remove(rule) {
    if (!rule || mutationBusy) return
    pendingRule = rule
    noticeRequested("Removing LAN access for :" + rule.port + "…", false)
    removeProcess.start(Firewall.commandFor(rule, true))
  }

  Component.onCompleted: refresh()

  CommandProcess {
    id: checkProcess
    objectName: "firewallCheckProcess"
    command: Firewall.statusCommand
    onCompleted: function(exitCode) {
      var server = root.pendingServer
      if (!server) return
      if (exitCode !== 0) {
        root.pendingServer = null
        root.noticeRequested(errorOutput || "Could not check LAN access", true)
        return
      }
      var status = Firewall.parseStatus(output, exitCode)
      if (!status.active || (!status.unreadable && Firewall.ufwAllowsPort(
          status.rules, server.lanInterface, server.lanSubnet, server.port))) {
        root.pendingServer = null
        root.qrReady(server)
        return
      }
      if (status.unreadable)
        root.noticeRequested("UFW rules could not be read; confirming LAN access for :" + server.port, false)
      root.authorizationRequested(server)
    }
  }

  CommandProcess {
    id: rulesProcess
    objectName: "firewallRulesProcess"
    command: Firewall.statusCommand
    onCompleted: function(exitCode) {
      var status = Firewall.parseStatus(output, exitCode)
      root.rulesUnreadable = status.unreadable
      root.managedRules = status.managedRules
    }
  }

  CommandProcess {
    id: allowProcess
    objectName: "firewallAllowProcess"
    onCompleted: function(exitCode) {
      var server = root.pendingServer
      root.pendingServer = null
      root.refresh()
      if (exitCode === 0 && server) {
        root.noticeRequested("LAN access allowed for :" + server.port, false)
        root.qrReady(server)
      } else root.noticeRequested(errorOutput || "LAN access was not authorized", true)
    }
  }

  CommandProcess {
    id: removeProcess
    objectName: "firewallRemoveProcess"
    onCompleted: function(exitCode) {
      var rule = root.pendingRule
      root.pendingRule = null
      root.refresh()
      if (exitCode === 0 && rule)
        root.noticeRequested("Removed LAN access for :" + rule.port, false)
      else root.noticeRequested(errorOutput || "Could not remove the LAN access rule", true)
    }
  }
}
