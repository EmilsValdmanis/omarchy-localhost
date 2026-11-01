import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Theme

// Auxiliary views share the server list's virtualized rows, scrollbar padding and fades.
Item {
  id: root
  property alias model: list.model
  property alias delegate: list.delegate
  property alias header: list.header
  property alias contentY: list.contentY
  readonly property int count: list.count
  readonly property bool interactive: list.interactive
  readonly property real viewportWidth: list.width
  property real scrollBarGap: Style.space(2)
  property string emptyText: ""
  property bool reserveScrollBar: false

  // Wait for wrapped rows to settle before changing their available width.
  // Deriving padding directly from ScrollBar.size feeds back into list height.
  function updateScrollPadding() { reserveScrollBar = list.contentHeight > list.height + 1 }

  function itemAtIndex(index) { return list.itemAtIndex(index) }
  function positionViewAtIndex(index, mode) { list.positionViewAtIndex(index, mode) }

  Layout.fillWidth: true
  Layout.fillHeight: true
  Layout.minimumHeight: 0
  implicitHeight: Math.min(Math.max(list.contentHeight, list.count ? 0 : Style.space(120)), Style.space(450))

  ListView {
    id: list
    anchors.fill: parent
    anchors.rightMargin: root.reserveScrollBar ? scrollbar.width + root.scrollBarGap : 0
    onContentHeightChanged: Qt.callLater(root.updateScrollPadding)
    onHeightChanged: Qt.callLater(root.updateScrollPadding)
    clip: true
    spacing: Style.space(2)
    boundsBehavior: Flickable.StopAtBounds
    flickableDirection: Flickable.VerticalFlick
    interactive: contentHeight > height
    reuseItems: true
    ScrollBar.vertical: ListScrollBar {
      id: scrollbar
      objectName: "auxiliaryScrollBar"
      visible: root.reserveScrollBar
      parent: root
      x: root.width - width
      height: list.height
    }
  }
  ListEdgeFades { anchors.fill: list; view: list }
  Text {
    visible: list.count === 0
    anchors.centerIn: list
    width: list.width - Style.space(16)
    text: root.emptyText
    textFormat: Text.PlainText
    wrapMode: Text.WordWrap
    horizontalAlignment: Text.AlignHCenter
    color: Qt.darker(Theme.Color.popups.text, 1.4)
    font.family: Style.font.family
    font.pixelSize: Style.font.body
  }
}
