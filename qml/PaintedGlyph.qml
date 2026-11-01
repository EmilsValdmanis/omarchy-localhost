import QtQuick
import qs.Commons
import qs.Commons as Theme

// Fit the visible glyph bounds, independent of the icon font's ascent/descent.
Item {
  id: root
  property string text: ""
  property string fontFamily: Style.font.family
  property real fontSize: Style.font.body
  property real paintedSize: 0
  property color color: Theme.Color.foreground
  readonly property real glyphScale: paintedSize > 0
    ? Math.min(paintedSize, width, height) / Math.max(1, metrics.tightBoundingRect.width, metrics.tightBoundingRect.height) : 1
  readonly property real paintedCenterX: glyph.x + (metrics.tightBoundingRect.x + metrics.tightBoundingRect.width / 2) * glyphScale
  readonly property real paintedCenterY: glyph.y + (glyph.baselineOffset + metrics.tightBoundingRect.y + metrics.tightBoundingRect.height / 2) * glyphScale

  TextMetrics {
    id: metrics
    font: glyph.font
    text: root.text
  }
  Text {
    id: glyph
    x: root.width / 2 - (metrics.tightBoundingRect.x + metrics.tightBoundingRect.width / 2) * root.glyphScale
    y: root.height / 2 - (baselineOffset + metrics.tightBoundingRect.y + metrics.tightBoundingRect.height / 2) * root.glyphScale
    text: root.text
    textFormat: Text.PlainText
    color: root.color
    font.family: root.fontFamily
    font.pixelSize: Math.max(1, Math.round(root.fontSize))
    transformOrigin: Item.TopLeft
    scale: root.glyphScale
    renderType: Text.CurveRendering
  }
}
