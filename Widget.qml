import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "emils.localhost"

  property string notice: ""
  property bool noticeUrgent: false

  readonly property int serverCount: radar.servers.length
  readonly property bool showCountBadge: setting("showCountBadge", true)

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

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

  function openQr(server) {
    if (!server || !server.lanAvailable) return
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

  function openPanel() {
    card.open = true
    radar.scan()
  }

  function closePanel() { card.open = false }

  function togglePanel() {
    card.open = !card.open
    if (card.open) radar.scan()
  }

  RadarService {
    id: radar
    refreshIntervalSec: Math.max(1, Number(root.setting("refreshIntervalSec", 2)))
    onActionFinished: function(action, successful, detail) {
      root.showNotice(detail, !successful)
    }
  }

  Timer {
    id: noticeTimer
    interval: 2400
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
    function refresh(): string { radar.scan(); return "ok" }
  }

  BarIconButton {
    id: button
    anchors.centerIn: parent
    bar: root.bar
    text: "\uf0ac"
    foreground: root.serverCount > 0 ? Color.accent
      : (root.bar ? root.bar.barForeground : Color.foreground)
    tooltipText: root.serverCount > 0
      ? "Localhost · " + root.serverCount + " server" + (root.serverCount === 1 ? "" : "s")
      : "Localhost · watching for dev servers"
    onPressed: function(mouseButton) {
      root.togglePanel()
    }

    Rectangle {
      visible: root.showCountBadge && root.serverCount > 0
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.rightMargin: Style.space(1)
      anchors.topMargin: Style.space(1)
      width: Math.max(Style.space(12), badgeText.implicitWidth + Style.space(5))
      height: Style.space(12)
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
        font.pixelSize: Style.space(8)
        font.bold: true
      }
    }
  }

  PopupCard {
    id: card
    anchorItem: button
    bar: root.bar
    owner: root
    centerOnBar: true
    contentWidth: fittedContentWidth(panel.implicitWidth, Style.space(560))
    contentHeight: fittedContentHeight(panel.implicitHeight, Style.space(620))

    ServerPanel {
      id: panel
      anchors.fill: parent
      servers: radar.servers
      lanIp: radar.lanIp
      loading: radar.loading
      error: radar.error
      notice: root.notice
      noticeUrgent: root.noticeUrgent

      onRefreshRequested: radar.scan()
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
    }
  }
}
