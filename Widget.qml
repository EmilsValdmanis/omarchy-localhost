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

  readonly property int serverCount: radar.serverCount
  readonly property bool showCountBadge: setting("showCountBadge", true)

  visible: serverCount > 0
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onServerCountChanged: if (serverCount === 0) card.open = false

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
    if (serverCount === 0) return
    card.open = true
  }

  function closePanel() { card.open = false }

  function togglePanel() {
    if (serverCount === 0) return
    card.open = !card.open
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
    function status(): string {
      return JSON.stringify({
        serverCount: root.serverCount,
        scanning: radar.scanning,
        scanError: radar.scanError,
        lanIp: radar.lanIp
      })
    }
  }

  BarIconButton {
    id: button
    anchors.centerIn: parent
    bar: root.bar
    tooltipText: "Localhost · " + root.serverCount + " server" + (root.serverCount === 1 ? "" : "s")
    onPressed: function(mouseButton) {
      root.togglePanel()
    }

    iconComponent: Component {
      Item {
        OpticalGlyph {
          width: parent.width
          height: parent.height
          y: Style.spaceReal(1)
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

  PopupCard {
    id: card
    anchorItem: button
    bar: root.bar
    owner: root
    contentWidth: fittedContentWidth(panel.implicitWidth, Style.space(560))
    contentHeight: fittedContentHeight(panel.implicitHeight, Style.space(620))

    ServerPanel {
      id: panel
      anchors.fill: parent
      servers: radar.servers
      lanIp: radar.lanIp
      notice: root.notice
      noticeUrgent: root.noticeUrgent

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
