import QtQuick
import qs.Commons
import qs.Ui

// Pair an icon with a vertically centered text label. Font line boxes include
// invisible ascent/descent space; align the painted icon to the capital letters.
Item {
  id: root
  required property var label
  property alias text: glyph.text
  property alias color: glyph.color
  property alias paintedSize: glyph.paintedSize
  readonly property real opticalOffset: label.baselineOffset + metrics.tightBoundingRect.y
    + metrics.tightBoundingRect.height / 2 - label.height / 2
  readonly property real paintedCenterY: glyph.y + glyph.paintedCenterY
  implicitWidth: Style.space(14)
  implicitHeight: label.implicitHeight

  TextMetrics {
    id: metrics
    font: root.label.font
    text: "H"
  }
  OpticalGlyph {
    id: glyph
    width: root.width
    height: root.height
    y: root.opticalOffset
    paintedSize: Style.space(10)
  }
}
