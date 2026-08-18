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
  implicitHeight: panelLayout.implicitHeight

  ColumnLayout {
    id: panelLayout
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

    Item {
      Layout.fillWidth: true
      Layout.preferredHeight: root.listHeight

      ListView {
        id: serverList
        anchors.fill: parent
        clip: true
        spacing: Style.space(8)
        model: root.servers
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height

        ScrollBar.vertical: ScrollBar {
          id: serverScrollBar
          policy: serverList.contentHeight > serverList.height ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
          width: Style.space(14)
          padding: Style.space(3)
          minimumSize: 0.12
          interactive: true

          contentItem: Rectangle {
            implicitWidth: Style.space(8)
            implicitHeight: Style.space(36)
            radius: width / 2
            color: root.foreground
            opacity: serverScrollBar.pressed ? 0.9 : (serverScrollBar.hovered ? 0.7 : 0.42)

            Behavior on opacity { NumberAnimation { duration: 80 } }
          }

          background: Rectangle {
            implicitWidth: Style.space(14)
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.07)
            radius: width / 2
          }
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
          width: serverList.width - (serverScrollBar.visible ? Style.space(16) : 0)
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
    required property string source
    required property string containerId
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
      source: source,
      containerId: containerId,
      port: port,
      cwd: cwd,
      localUrl: localUrl,
      lanUrl: lanUrl,
      lanAvailable: lanAvailable,
      hint: hint
    })

    readonly property string effectiveUrl: lanAvailable ? lanUrl : localUrl
    readonly property color statusDotColor: lanAvailable ? Color.accent : Color.urgent
    readonly property color statusTextColor: lanAvailable ? Color.accent : root.dim
    readonly property string statusTooltip: lanAvailable
      ? row.hint
      : "Bound to localhost only.\nStart with --host / 0.0.0.0 to use it from another device."
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
            id: titleRow
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
                  id: statusLabel
                  text: row.lanAvailable ? "LAN ready" : "Local only"
                  color: row.statusTextColor
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  font.weight: Font.Medium
                }
              }

              MouseArea {
                id: statusHover
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.NoButton
              }

              PanelToolTip {
                visible: statusHover.containsMouse
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
