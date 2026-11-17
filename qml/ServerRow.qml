pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Theme
import qs.Ui
import "Frameworks.js" as Frameworks
import "Memory.js" as Memory

CursorSurface {
  id: row
  required property int index
  required property var server
  property bool selected: false
  property color memoryColor: Theme.Color.accent
  readonly property color dim: Qt.darker(foreground, 1.4)
  readonly property string frameworkIcon: Frameworks.frameworkIcon(server.frameworkId)
  readonly property string detail: server.projectPath && server.projectPath !== "." ? server.projectPath : ""
  readonly property var memoryHistory: Memory.parseMemoryHistory(server.memoryHistoryJson)

  signal rowSelected()
  signal openRequested()

  hasCursor: selected
  implicitHeight: Math.max(labels.implicitHeight, Style.space(28)) + Style.space(14)

  HoverHandler { cursorShape: Qt.PointingHandCursor }
  TapHandler {
    onTapped: row.rowSelected()
    onDoubleTapped: row.openRequested()
  }

  RowLayout {
    anchors.fill: parent
    anchors.leftMargin: Style.space(8)
    anchors.rightMargin: Style.space(6)
    spacing: Style.space(9)

    Item {
      id: frameworkItem
      objectName: "serverFrameworkIcon"
      readonly property bool showDependencies: row.server.source === "docker"
        && (row.server.serviceKey.startsWith("compose:") || row.server.dependencyStates !== "")
      Layout.preferredWidth: Style.space(22)
      Layout.preferredHeight: Style.space(24)
      Accessible.role: Accessible.StaticText
      Accessible.name: showDependencies ? "Docker. " + dependencies.text : row.server.framework
      HoverHandler { id: frameworkHover }
      PanelToolTip {
        visible: frameworkHover.hovered && !frameworkItem.showDependencies
        text: row.server.framework
      }
      ComposeDependencyTooltip {
        id: dependencies
        serviceName: row.server.name.split(" / ").pop()
        visible: frameworkHover.hovered && frameworkItem.showDependencies
        details: row.server.dependencyStates
      }
      PaintedGlyph {
        objectName: "frameworkGlyph"
        anchors.fill: parent
        visible: row.frameworkIcon !== ""
        text: row.frameworkIcon
        color: row.selected ? Theme.Color.accent : row.foreground
        fontFamily: Style.font.family
        fontSize: row.server.frameworkId === "docusaurus" ? Style.font.body : Style.font.heading
        paintedSize: Style.space(row.server.frameworkId === "docusaurus" ? 12 : 16)
      }
      ComposeProblemDot {
        anchors.topMargin: Style.space(2)
        dependencyStates: row.server.dependencyStates
      }
      Text {
        anchors.centerIn: parent
        visible: row.frameworkIcon === ""
        textFormat: Text.PlainText
        text: row.server.framework.charAt(0).toUpperCase()
        color: row.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.body
      }
    }

    ColumnLayout {
      id: labels
      Layout.fillWidth: true
      spacing: Style.space(1)
      RowLayout {
        Layout.fillWidth: true
        spacing: Style.space(5)

        Text {
          id: serverNameLabel
          objectName: "serverName"
          Layout.fillWidth: true
          Layout.maximumWidth: Math.ceil(implicitWidth)
          textFormat: Text.PlainText
          text: row.server.name.replace(/^@[^/]+\//, "")
          color: row.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          font.bold: true
          elide: Text.ElideRight
        }

        Item {
          objectName: "serverLanIcon"
          visible: row.server.lanAvailable
          Layout.preferredWidth: Style.space(14)
          Layout.preferredHeight: serverNameLabel.implicitHeight
          Accessible.role: Accessible.StaticText
          Accessible.name: "LAN sharing available"

          InlineIcon {
            anchors.fill: parent
            label: serverNameLabel
            text: "\uf1e0"
            color: row.dim
          }
          HoverHandler { id: lanHover }
          PanelToolTip {
            visible: lanHover.hovered
            text: "LAN sharing available" + (row.server.lanUrl ? "\n" + row.server.lanUrl : "")
          }
        }

        Item { Layout.fillWidth: true }
      }
      Text {
        objectName: "serverPath"
        visible: row.server.cwdDeleted || row.detail !== ""
        Layout.fillWidth: true
        textFormat: Text.PlainText
        text: row.server.cwdDeleted ? "Working directory deleted" : row.detail
        color: row.server.cwdDeleted ? Theme.Color.urgent : row.dim
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        elide: Text.ElideMiddle
      }
    }

    Item {
      Layout.preferredWidth: Style.space(62)
      Layout.preferredHeight: Style.space(20)

      MemorySparkline {
        anchors.fill: parent
        samples: row.memoryHistory
        lineColor: row.memoryColor
        opacity: row.server.memoryBytes >= 0 ? 1 : 0.35
      }
      HoverHandler { id: memoryHover }
      PanelToolTip {
        visible: memoryHover.hovered
        text: row.server.memoryBytes >= 0
          ? "Recent server RAM · last " + row.memoryHistory.length + " samples"
          : "RAM usage unavailable"
      }
    }

    Text {
      objectName: "serverMemory"
      Layout.preferredWidth: Style.space(66)
      textFormat: Text.PlainText
      text: Memory.formatMemory(row.server.memoryBytes)
      color: row.server.memoryBytes >= 0 ? row.foreground : row.dim
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      horizontalAlignment: Text.AlignRight
      elide: Text.ElideRight
    }

    Button {
      objectName: "openPort"
      text: ":" + row.server.port
      fontSize: Style.font.caption
      horizontalPadding: Style.space(7)
      verticalPadding: Style.space(4)
      foreground: row.foreground
      enabled: !!row.server.localUrl
      tooltipText: enabled ? "Open " + row.server.localUrl : row.server.hint
      onClicked: row.openRequested()
    }
  }
}
