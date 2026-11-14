// The real panel requires Wayland layer-shell. Host settings tests use no window.
import QtQuick

Item {
  property var anchorItem
  property var bar
  property var owner
  property var focusTarget
  property bool open: false
  property int contentWidth
  property int contentHeight
  function fittedContentWidth(value, limit) { return Math.min(value, limit) }
  function fittedContentHeight(value, limit) { return Math.min(value, limit) }
}
