import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Ui

Item {
  id: root

  property var servers: []
  property string lanIp: ""
  property bool loading: false
  property string error: ""
  property string notice: ""
  property bool noticeUrgent: false

  signal refreshRequested()
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
  readonly property int listHeight: servers.length === 0
    ? Style.space(150)
    : Math.min(serverList.contentHeight, Style.space(450))

  implicitWidth: panelWidth
  implicitHeight: header.implicitHeight + Style.space(18) + listHeight
    + ((notice !== "" || error !== "") ? Style.space(34) : 0)

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
          text: {
            if (root.servers.length === 0) return "Watching for development servers"
            var count = root.servers.length + " server" + (root.servers.length === 1 ? "" : "s")
            return root.lanIp ? count + "  ·  " + root.lanIp : count
          }
          color: root.dim
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      PanelActionButton {
        iconText: "\uf2f1"
        tooltipText: root.loading ? "Scanning…" : "Scan now"
        foreground: root.foreground
        fontFamily: Style.font.family
        enabled: !root.loading
        iconRotation: 0
        onClicked: root.refreshRequested()

        RotationAnimation on rotation {
          from: 0
          to: 360
          duration: 700
          loops: Animation.Infinite
          running: root.loading
        }
      }
    }

    Rectangle {
      Layout.fillWidth: true
      height: Math.max(1, Style.spacing.hairline)
      color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.14)
    }

    Item {
      Layout.fillWidth: true
      Layout.preferredHeight: root.listHeight

      ColumnLayout {
        visible: root.servers.length === 0
        anchors.centerIn: parent
        width: parent.width - Style.space(48)
        spacing: Style.space(8)

        Text {
          Layout.alignment: Qt.AlignHCenter
          text: "\uf0ac"
          color: root.dim
          font.family: Style.font.family
          font.pixelSize: Style.space(28)
          opacity: root.loading ? 0.45 : 0.8

          SequentialAnimation on opacity {
            running: root.loading
            loops: Animation.Infinite
            NumberAnimation { to: 0.35; duration: 450; easing.type: Easing.InOutSine }
            NumberAnimation { to: 0.8; duration: 450; easing.type: Easing.InOutSine }
          }
        }

        Text {
          Layout.fillWidth: true
          text: root.loading ? "Scanning listening ports…" : "No development servers yet"
          color: root.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          horizontalAlignment: Text.AlignHCenter
        }

        Text {
          Layout.fillWidth: true
          text: "Start Vite, Next, Astro, Rails, or another local server. It will appear here automatically."
          color: root.dim
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          wrapMode: Text.Wrap
          horizontalAlignment: Text.AlignHCenter
        }
      }

      ListView {
        id: serverList
        visible: root.servers.length > 0
        anchors.fill: parent
        clip: true
        spacing: Style.space(8)
        model: root.servers
        boundsBehavior: Flickable.StopAtBounds

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
          required property var modelData
          required property int index
          width: serverList.width - (serverList.contentHeight > serverList.height ? Style.space(8) : 0)
          server: modelData
          rowIndex: index
        }
      }
    }

    Text {
      visible: root.notice !== "" || root.error !== ""
      Layout.fillWidth: true
      text: root.error !== "" ? root.error : root.notice
      color: root.error !== "" || root.noticeUrgent ? Color.urgent : root.dim
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      wrapMode: Text.Wrap
      horizontalAlignment: Text.AlignHCenter
    }
  }

  component ServerRow: CursorSurface {
    id: row
    required property var server
    property int rowIndex: 0

    readonly property string effectiveUrl: server.lanAvailable ? server.lanUrl : server.localUrl
    readonly property color statusColor: server.lanAvailable ? Color.accent : Color.urgent
    readonly property string frameworkMark: {
      var marks = {
        next: "N", vite: "V", svelte: "S", astro: "A", nuxt: "N",
        angular: "A", react: "R", storybook: "S", python: "Py", rails: "Rb",
        laravel: "L", phoenix: "Ph", rust: "Rs", go: "Go", node: "JS"
      }
      return marks[server.frameworkId] || "<>"
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
            text: row.server.name
            color: root.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            font.bold: true
            elide: Text.ElideRight
          }

          Text {
            Layout.fillWidth: true
            text: row.server.framework + "  ·  :" + row.server.port
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
              text: row.server.lanAvailable ? "LAN READY" : "LOCAL ONLY"
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
        color: row.server.lanAvailable ? root.foreground : root.dim
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        elide: Text.ElideMiddle
      }

      Text {
        visible: !row.server.lanAvailable
        Layout.fillWidth: true
        text: row.server.hint
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
          foreground: row.server.lanAvailable ? root.foreground : root.dim
          accent: Color.accent
          active: row.server.lanAvailable
          enabled: row.server.lanAvailable
          focusable: true
          tooltipText: row.server.lanAvailable ? "Open phone-ready QR code" : "Bind the server to 0.0.0.0 first"
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
