import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Ui

Item {
  id: root

  property var servers: null
  property string lanIp: ""
  property string notice: ""
  property bool noticeUrgent: false

  signal openRequested(var server)
  signal copyRequested(var server)
  signal qrRequested(var server)
  signal terminalRequested(var server)
  signal projectRequested(var server)
  signal restartRequested(var server)
  signal stopRequested(var server)

  readonly property color foreground: Color.popups.text
  readonly property color dim: Qt.darker(foreground, 1.45)
  readonly property int panelWidth: Style.space(500)
  readonly property int serverCount: servers ? servers.count : 0
  readonly property int listHeight: Math.min(serverList.contentHeight, Style.space(450))

  implicitWidth: panelWidth
  implicitHeight: header.implicitHeight + Style.space(18) + listHeight
    + (notice !== "" ? Style.space(34) : 0)

  ColumnLayout {
    anchors.fill: parent
    spacing: Style.space(12)

    RowLayout {
      id: header
      Layout.fillWidth: true
      spacing: Style.space(10)

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

    }

    Rectangle {
      Layout.fillWidth: true
      height: Math.max(1, Style.spacing.hairline)
      color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.14)
    }

    ListView {
      id: serverList
      Layout.fillWidth: true
      Layout.preferredHeight: root.listHeight
      clip: true
      spacing: Style.space(8)
      model: root.servers
      boundsBehavior: Flickable.StopAtBounds
      interactive: contentHeight > height

      function scrollByWheel(delta) {
        var minimum = originY
        var maximum = Math.max(minimum, originY + contentHeight - height)
        contentY = Math.max(minimum, Math.min(maximum, contentY + delta))
      }

      WheelHandler {
        target: null
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        enabled: serverList.interactive

        onWheel: function(event) {
          var pixelDelta = Number(event.pixelDelta.y || 0)
          var delta = pixelDelta !== 0
            ? pixelDelta
            : Number(event.angleDelta.y || 0) / 120 * Style.space(96)
          if (delta === 0) {
            event.accepted = false
            return
          }
          serverList.scrollByWheel(-delta)
          event.accepted = true
        }
      }

      ScrollBar.vertical: ScrollBar {
        policy: serverList.contentHeight > serverList.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
      }

      add: Transition {
        ParallelAnimation {
          NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 180; easing.type: Easing.OutCubic }
          NumberAnimation { property: "scale"; from: 0.97; to: 1; duration: 180; easing.type: Easing.OutCubic }
        }
      }

      remove: Transition {
        ParallelAnimation {
          NumberAnimation { property: "opacity"; to: 0; duration: 100; easing.type: Easing.OutCubic }
          NumberAnimation { property: "scale"; to: 0.98; duration: 100; easing.type: Easing.OutCubic }
        }
      }

      displaced: Transition {
        NumberAnimation { properties: "x,y"; duration: 180; easing.type: Easing.OutCubic }
      }

      delegate: ServerRow {
        width: serverList.width - (serverList.contentHeight > serverList.height ? Style.space(8) : 0)
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
  }

  component ServerRow: CursorSurface {
    id: row
    required property int index
    required property string serverId
    required property string name
    required property string framework
    required property string frameworkId
    required property int pid
    required property int port
    required property string cwd
    required property string localUrl
    required property string lanUrl
    required property bool lanAvailable
    required property string hint

    readonly property var server: ({
      id: serverId,
      name: name,
      framework: framework,
      frameworkId: frameworkId,
      pid: pid,
      port: port,
      cwd: cwd,
      localUrl: localUrl,
      lanUrl: lanUrl,
      lanAvailable: lanAvailable,
      hint: hint
    })

    readonly property string effectiveUrl: lanAvailable ? lanUrl : localUrl
    readonly property color statusColor: lanAvailable ? Color.accent : Color.urgent
    readonly property string frameworkMark: {
      var marks = {
        next: "N", vite: "V", svelte: "S", astro: "A", nuxt: "N",
        angular: "A", react: "R", storybook: "S", python: "Py", rails: "Rb",
        laravel: "L", phoenix: "Ph", rust: "Rs", go: "Go", node: "JS"
      }
      return marks[frameworkId] || "<>"
    }

    bordered: true
    foreground: root.foreground
    implicitHeight: rowContent.implicitHeight + Style.space(20)

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
        spacing: Style.space(10)

        Rectangle {
          Layout.preferredWidth: Style.space(34)
          Layout.preferredHeight: Style.space(34)
          radius: Style.cornerRadius
          color: Style.selectedFillFor(root.foreground, Color.accent)

          Text {
            anchors.centerIn: parent
            text: row.frameworkMark
            color: root.foreground
            font.family: Style.font.family
            font.pixelSize: row.frameworkMark.length > 1 ? Style.font.caption : Style.font.body
            font.bold: true
          }
        }

        ColumnLayout {
          Layout.fillWidth: true
          spacing: 0

          Text {
            Layout.fillWidth: true
            text: row.name
            color: root.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            font.bold: true
            elide: Text.ElideRight
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

        Rectangle {
          Layout.preferredWidth: statusLabel.implicitWidth + Style.space(16)
          Layout.preferredHeight: statusLabel.implicitHeight + Style.space(8)
          radius: height / 2
          color: Qt.rgba(row.statusColor.r, row.statusColor.g, row.statusColor.b, 0.12)

          Row {
            anchors.centerIn: parent
            spacing: Style.space(5)

            Rectangle {
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(6)
              height: width
              radius: width / 2
              color: row.statusColor
            }

            Text {
              id: statusLabel
              text: row.lanAvailable ? "LAN READY" : "LOCAL ONLY"
              color: row.statusColor
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              font.bold: true
            }
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

      Text {
        visible: !row.lanAvailable
        Layout.fillWidth: true
        text: row.hint
        color: root.dim
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        wrapMode: Text.Wrap
      }

      RowLayout {
        Layout.fillWidth: true
        spacing: Style.space(4)

        Button {
          text: "Open"
          foreground: root.foreground
          focusable: true
          bordered: true
          onClicked: root.openRequested(row.server)
        }

        Button {
          text: "Copy"
          foreground: root.foreground
          focusable: true
          onClicked: root.copyRequested(row.server)
        }

        Button {
          text: "QR"
          foreground: row.lanAvailable ? root.foreground : root.dim
          accent: Color.accent
          active: row.lanAvailable
          enabled: row.lanAvailable
          focusable: true
          tooltipText: row.lanAvailable ? "Open phone-ready QR code" : "Bind the server to 0.0.0.0 first"
          onClicked: root.qrRequested(row.server)
        }

        Item { Layout.fillWidth: true }

        PanelActionButton {
          iconText: "\uf120"
          tooltipText: "Open terminal here"
          foreground: root.foreground
          fontFamily: Style.font.family
          onClicked: root.terminalRequested(row.server)
        }

        PanelActionButton {
          iconText: "\uf121"
          tooltipText: "Open project in editor"
          foreground: root.foreground
          fontFamily: Style.font.family
          onClicked: root.projectRequested(row.server)
        }

        PanelActionButton {
          iconText: "\uf2f9"
          tooltipText: "Restart server"
          foreground: root.foreground
          fontFamily: Style.font.family
          onClicked: root.restartRequested(row.server)
        }

        PanelActionButton {
          iconText: "\uf04d"
          tooltipText: "Stop server"
          foreground: Color.urgent
          hoverColor: Color.urgent
          fontFamily: Style.font.family
          onClicked: root.stopRequested(row.server)
        }
      }
    }
  }
}
