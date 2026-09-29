import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons

// Auxiliary panel pages share the same bounded, native scrolling as the list.
Flickable {
  id: root
  default property alias contents: column.data
  property alias spacing: column.spacing

  Layout.fillWidth: true
  Layout.fillHeight: true
  Layout.minimumHeight: 0
  implicitHeight: Math.min(contentHeight, Style.space(450))
  contentWidth: width
  contentHeight: column.implicitHeight
  clip: true
  boundsBehavior: Flickable.StopAtBounds
  flickableDirection: Flickable.VerticalFlick
  interactive: contentHeight > height
  ScrollBar.vertical: ScrollBar { id: scrollBar; policy: ScrollBar.AsNeeded }

  ColumnLayout {
    id: column
    width: root.width - (scrollBar.visible ? scrollBar.width + Style.space(4) : 0)
    spacing: Style.space(6)
  }
}
